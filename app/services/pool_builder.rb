# ── Service PoolBuilder ───────────────────────────────────────────────────────
# Moteur du format « Poules » (Lot 5) : on répartit les joueurs en poules, on joue
# un round-robin DANS chaque poule (toutes poules en parallèle), puis les meilleurs
# de chaque poule entrent en tableau final.
#
# Réutilise l'algorithme de calendrier round-robin de LeagueBuilder (.schedule) et
# le recompute partagé (RoundRobinStats). Une « journée » = une TournamentRound de
# phase "pool" regroupant la journée de MÊME index de toutes les poules (respecte
# l'index unique (tournament_id, phase, number)). La poule d'un match se dérive de
# player_a.pool (pas de colonne dédiée sur le match).
#
# ── Le calendrier ENTIER est créé au lancement ─────────────────────────────────
# Contrairement à la ronde suisse, dont chaque ronde dépend des résultats de la
# précédente, un round-robin est intégralement connu d'avance : dans une poule de
# 4, chacun affronte les 3 autres, point. Le générer journée par journée n'apportait
# donc rien et coûtait beaucoup :
#   • un joueur ne voyait qu'un seul de ses 3 adversaires, alors que depuis le Lot 7
#     c'est LUI qui planifie ses rencontres — il lui faut les connaître toutes pour
#     convenir des dates ;
#   • les poules ne pouvaient avancer qu'au même rythme, la plus lente bloquant
#     tout le monde ;
#   • le calendrier était recalculé à chaque journée et devait retomber à
#     l'identique (cf. RoundRobinStats#ordered_player_scope) — un ordre de joueurs
#     qui bougeait en cours de route dédoublait ou perdait des rencontres. Créé
#     d'un coup, il n'est calculé qu'une fois : le problème disparaît.
#
# Les journées restent des TournamentRound (l'ordre du calendrier, et un repère
# pour l'organisateur), mais elles ne sont plus une porte : toutes les rencontres
# d'une poule sont saisissables dès le lancement, dans l'ordre que les joueurs
# veulent. D'où le verrouillage de la phase EN BLOC, quand la dernière rencontre
# est jouée (cf. #close_pool_rounds!), et non journée par journée : « ta journée
# est terminée » n'a plus de sens pour qui ne voit que sa poule.
class PoolBuilder
  include RoundRobinStats

  def initialize(tournament)
    @tournament = tournament
  end

  # Répartit les poules et crée TOUT le calendrier au premier appel, puis bascule
  # sur le tableau final quand la dernière rencontre de poule est jouée.
  # Idempotent (même garde-fou anti double-clic que le suisse).
  def next_round!
    ActiveRecord::Base.transaction do
      # Critérium Fédéral : dès que la phase finale a commencé, c'est CriteriumFlow
      # qui pilote — et le court-circuit doit venir AVANT toute lecture de
      # `current_round`. Cette méthode suppose UN tour courant unique, alors que le
      # Critérium fait tourner plusieurs branches en parallèle (le match pour la 3e
      # place et le mini-tableau des places 5 à 8) : la garde
      # `return current if current && !current.complete?` bloquerait la génération
      # de l'une parce que l'autre n'est pas finie.
      return CriteriumFlow.new(@tournament).advance! if criterium_final_phase?

      # Tableau final déjà lancé : la phase de poules est derrière nous, on rend la
      # main à son moteur (même garde qu'avant, `current_round` privilégiant les
      # tours de tableau).
      if @tournament.bracket_started?
        current = @tournament.current_round
        return current if current && !current.complete?

        current&.update!(status: "completed")
        return BracketBuilder.new(@tournament).advance!
      end

      assign_pools! if pools_unassigned?

      recompute_stats_for("pool", apply_state: false, count_byes: false)

      create_missing_pool_rounds!

      # Tant qu'une seule rencontre de poule manque, il n'y a rien à faire de plus :
      # le classement vient d'être rafraîchi, et aucune poule ne peut qualifier
      # qui que ce soit.
      return current_pool_round unless pool_phase_complete?

      close_pool_rounds!
      start_playoffs!
    end
  end

  private

  def criterium_final_phase? = @tournament.criterium? && @tournament.final_phase_started?

  # ── Répartition en poules ──────────────────────────────────────────────────────
  # Nombre de poules : délègue à Tournament#pool_count, seule source de vérité
  # (aussi utilisée pour dimensionner le tableau final, cf. Tournament#final_size).
  def pool_count = @tournament.pool_count

  def pools_unassigned? = player_scope.where(pool: nil).exists?

  # Qui va dans quelle poule : délégué à PoolSeeding (Lot 7), qui applique le mode
  # choisi par l'organisateur — tirage au sort intégral (le serpentin historique)
  # ou chapeaux. Ce moteur-ci n'a pas à connaître la différence : il lui suffit que
  # chaque joueur reparte avec un `pool`.
  def assign_pools! = PoolSeeding.new(@tournament).assign!

  # ── Calendrier ──────────────────────────────────────────────────────────────────
  # Calendrier round-robin de chaque poule.
  # => { pool_index => [journée = [[a, b], …], …] }
  #
  # ⚠️ Cette méthode est rappelée à CHAQUE journée et doit donc renvoyer exactement
  # le même calendrier à chaque fois : c'est l'index de journée qui sélectionne les
  # rencontres à créer. L'ordre des joueurs doit donc être TOTAL — cf.
  # RoundRobinStats#ordered_player_scope, qui documente pourquoi `draw_order` seul
  # ne suffit pas et ce qui casse quand l'ordre bouge en cours de route.
  def pool_schedules
    ordered_player_scope.to_a.group_by(&:pool).transform_values do |members|
      LeagueBuilder.schedule(members)
    end
  end

  # Crée les journées qui manquent — donc TOUTES au premier appel, aucune ensuite.
  # Écrit comme un rattrapage et non comme un « create_all » : c'est ce qui rend la
  # méthode idempotente (double-clic, rechargement Turbo) et ce qui répare aussi les
  # tournois lancés AVANT ce changement, dont seules les premières journées existent.
  def create_missing_pool_rounds!
    schedules      = pool_schedules
    total_journees = schedules.values.map(&:size).max.to_i
    existing       = @tournament.pool_rounds.count

    (existing...total_journees).each do |index|
      create_pool_round!(number: index + 1, schedules: schedules, index: index)
    end
  rescue ActiveRecord::RecordNotUnique
    # Deux requêtes concurrentes ont créé la même journée : l'index unique
    # (tournoi, phase, branche, numéro) a tranché, il n'y a rien à réparer.
    nil
  end

  # Journée « en cours » = la PREMIÈRE non terminée, pas la dernière créée : les
  # rencontres ne se jouent plus dans l'ordre du calendrier (deux joueurs peuvent
  # boucler leur 3e confrontation avant que la 1re journée soit finie).
  def current_pool_round
    rounds = @tournament.pool_rounds.to_a
    rounds.find { |round| !round.complete? } || rounds.last
  end

  # Toutes les rencontres de toutes les poules sont-elles jouées ?
  def pool_phase_complete?
    rounds = @tournament.pool_rounds.to_a
    rounds.any? && rounds.all?(&:complete?)
  end

  # Verrouillage EN BLOC de la phase (cf. l'en-tête) : à partir d'ici, seul
  # l'organisateur peut corriger un score (TournamentMatchPolicy#update? refuse un
  # tour "completed", #correct? prend le relais). Verrouiller journée par journée
  # aurait fermé la carte d'un joueur sur un critère qu'il ne voit même pas — que
  # l'AUTRE rencontre de la même journée de sa poule ait été saisie.
  def close_pool_rounds!
    @tournament.pool_rounds.where.not(status: "completed").each do |round|
      round.update!(status: "completed")
    end
  end

  # Crée la journée `number` en concaténant la journée d'index `index` de chaque
  # poule. `position` est un compteur global à la ronde (unicité de (round, position)),
  # les tailles de poules pouvant différer (effectifs « Libre »).
  def create_pool_round!(number:, schedules:, index:)
    round = @tournament.tournament_rounds.create!(phase: "pool", number: number, status: "in_progress")

    position = 0
    schedules.keys.compact.sort.each do |pool_index|
      pairs = schedules[pool_index][index]
      next if pairs.nil? # cette poule a moins de journées (poule plus petite)

      pairs.each do |a, b|
        build_match!(round, a, b, position)
        position += 1
      end
    end

    round
  end

  # ── Bascule playoffs ─────────────────────────────────────────────────────────────
  def start_playoffs!
    # Critérium Fédéral : ce n'est pas un top-N par poule qui entre en phase finale,
    # mais les 1ers (d'office), les 2es et 3es (en barrage) et les 4es (en
    # consolante) — tout le monde continue. CriteriumFlow s'en charge.
    return CriteriumFlow.new(@tournament).advance! if @tournament.criterium?

    finalists = pool_finalists
    finalists.each { |tu| tu.update!(state: "qualified") }
    BracketBuilder.new(@tournament, finalists: finalists).build!
  end

  # Qualifiés : les meilleurs de chaque poule pour remplir final_size, complétés
  # par les meilleurs restants toutes poules confondues si final_size n'est pas
  # divisible par le nombre de poules (effectifs « Libre »).
  def pool_finalists
    per_pool = [@tournament.final_size / pool_count, 1].max

    picked = []
    @tournament.pools.keys.sort.each do |pool_index|
      picked.concat(ranked(@tournament.pools[pool_index]).first(per_pool))
    end

    if picked.size < @tournament.final_size
      remaining = ranked(player_scope.to_a) - picked
      picked.concat(remaining.first(@tournament.final_size - picked.size))
    end

    picked.first(@tournament.final_size)
  end

  # Classement d'un groupe de joueurs — délègue à Tournament#rank_key (Lot 6),
  # source unique de vérité partagée avec ranked_players et BracketBuilder.
  def ranked(players)
    players.sort_by { |tu| @tournament.rank_key(tu) }
  end
end
