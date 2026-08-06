# ── Service CriteriumFlow ─────────────────────────────────────────────────────
# Moteur du format « Critérium Fédéral » (FFTT). MATÉRIALISE en TournamentRound la
# topologie déclarée par CriteriumStructure : barrages, tableau final (« OK »),
# consolante (« KO ») et mini-tableaux de classement.
#
# ── Un réconciliateur, pas une machine à états ─────────────────────────────────
# #advance! ne demande jamais « où en est-on ? ». Il parcourt TOUS les nœuds
# déclarés, recalcule ceux qui devraient exister d'après les tours déjà terminés,
# et ne crée que ce qui manque. Deux propriétés en découlent, indispensables :
#
#   • idempotence — double-clic, rechargement Turbo, appels concurrents : le
#     deuxième appel ne crée rien. L'index unique (tournoi, phase, branche, numéro)
#     est le garde-fou de dernier recours, exactement comme pour les journées de poule.
#   • déterminisme — aucun `shuffle`, `rand` ni `Time.now` ici. `draw_order`, tiré
#     une fois au lancement, est la seule source d'aléa. C'est la condition pour
#     qu'une correction de score (Lot 8) puisse détruire l'aval et le reconstruire
#     à l'identique.
#
# ── Pourquoi une boucle sur les nœuds, et pas un enchaînement écrit à la main ──
# Le format compte jusqu'à 11 tableaux (tableau final, consolante, et leurs
# classements imbriqués). Les câbler un par un demanderait de réécrire dans ce
# fichier les places, les sources et les appariements que CriteriumStructure
# déclare déjà — deux descriptions du règlement à garder en phase. Ici, un nœud
# n'a que deux états possibles : pas encore ouvert (ses sources sont-elles
# résolues ?) ou en cours (son dernier tour est-il terminé ?). Ajouter un nœud à
# la structure ne demande AUCUNE modification de ce service.
#
# Point d'entrée unique : #advance!. Il n'y a pas de #start! — le premier appel
# (poules terminées, rien en phase finale) crée les barrages, les suivants font
# progresser. C'est le même code.
class CriteriumFlow
  include RoundRobinStats

  def initialize(tournament)
    @tournament = tournament
  end

  # Fait avancer le tournoi d'un cran. Renvoie le tour créé, ou le tour en cours
  # s'il n'y avait rien à créer (contrat de PoolBuilder#next_round!).
  def advance!
    ActiveRecord::Base.transaction do
      # Les classements de poule sont memoïsés sur le tournoi. Ce service peut être
      # appelé APRÈS une correction de score sur la même instance (cf.
      # TournamentMatchesController#apply_correction!) : sans cette purge, il
      # apparierait le tableau final sur un classement périmé alors que les
      # barrages, eux, viennent d'être reconstruits sur le classement neuf.
      @tournament.reset_standings!
      @standings = nil

      close_finished_rounds!

      created = [ensure_barrage!, *sync_nodes!].compact
      complete_if_finished!(created)

      created.last || current_final_round
    end
  end

  # ── Correction d'un score DANS la phase finale (Lot 8) ──────────────────────
  # Corriger un quart de finale n'invalide pas la consolante : elle se joue en
  # parallèle, avec d'autres joueurs. Détruire toute la phase finale (ce que fait
  # une correction en POULE, où le classement de départ change et où tout est donc
  # caduc) y effacerait des scores encore parfaitement valides.
  #
  # On cherche donc le premier tour DEVENU FAUX — celui dont les joueurs réels ne
  # sont plus ceux que la structure produirait aujourd'hui — et on ne détruit qu'à
  # partir de lui. `id` croissant EST l'ordre causal : un tour n'est jamais créé
  # avant ses sources, donc « après le tour périmé » est exactement « en aval ».
  # #advance! reconstruit ensuite : il est déterministe, il retombe à l'identique
  # sur tout ce que la correction n'a pas touché.
  #
  # `from` = le tour corrigé lui-même : lui n'est jamais périmé (ses joueurs n'ont
  # pas changé, seul le vainqueur a changé), et l'exclure garantit qu'on ne détruit
  # jamais le tour qu'on vient d'éditer.
  def reconcile!(from: nil)
    ActiveRecord::Base.transaction do
      @tournament.reset_standings!
      @standings = nil

      stale = first_stale_round(after: from)
      @tournament.tournament_rounds.final_phase.where(id: stale.id..).destroy_all if stale

      advance!
    end
  end

  # ── Résolution des entrants d'un nœud ───────────────────────────────────────
  # PUBLIC parce que TournamentStandings en a besoin : pour attribuer une place
  # aux « 9es ex æquo », il faut savoir QUI est entré dans ce palier. Une seule
  # implémentation de « qui entre ici », partagée par le moteur et le classement —
  # sinon les deux pourraient diverger et le classement mentirait.
  #
  # Renvoie [] tant que les sources ne sont pas jouées : c'est ce qui fait qu'un
  # mini-tableau ne s'ouvre pas avant l'heure, sans aucun test d'étape explicite.
  def entrants_for(node)
    groups = node.sources.map { |source| resolve(source) }

    case node.pairing
    # Tableau final : les 1ers de poule (1er groupe) gardent les têtes de série
    # hautes, les vainqueurs de barrage prennent les basses.
    when :exempt_first then avoid_own_pool_first_round(groups.flatten, protected_count: groups.first.size)
    # Consolante : tout le monde classé par force, puis on écarte les joueurs de
    # même poule du premier tour (ils viennent de s'affronter).
    when :seeded       then avoid_own_pool_first_round(by_strength(groups.flatten), protected_count: 0)
    # Mini-tableau de classement : on CONSERVE l'ordre dans lequel les joueurs ont
    # perdu (position dans le tour parent). L'appariement miroir les reprend alors
    # en moitiés opposées du tableau parent, donc deux joueurs qui s'y sont déjà
    # rencontrés ne se retrouvent pas immédiatement.
    when :carry_over   then groups.flatten
    # Classement intégral : les sources sont les rangs de poule dans l'ordre (les
    # 1ers, puis les 2es…), donc `flatten` EST déjà l'ordre de tête de série voulu.
    # On protège les 1ers de poule comme dans le tableau final : l'appariement
    # miroir les place alors en moitiés opposées, et aucun ne rencontre un autre 1er
    # au premier tour.
    when :pool_rank    then avoid_own_pool_first_round(groups.flatten, protected_count: groups.first.size)
    else                    by_strength(groups.flatten)
    end
  end

  private

  def structure = @structure ||= @tournament.criterium_structure

  # ── Barrages ────────────────────────────────────────────────────────────────
  # Les 2es de poule contre les 3es, croisés. Nœud de TRANSIT : les vainqueurs
  # montent au tableau final, les perdants descendent en consolante. C'est le seul
  # nœud dont les DEUX camps continuent, d'où son traitement à part.
  def ensure_barrage!
    # Toutes les variantes n'ont pas de barrages : le classement intégral envoie
    # tout le monde dans un tableau unique, et une poule unique n'a aucune phase
    # finale. C'est la structure qui tranche — sans cette garde, un 2e et un 3e de
    # poule existant suffiraient à en fabriquer (cf. Tournament#criterium_mode).
    return nil if structure.node("barrage").blank?
    return nil if @tournament.barrage_rounds.exists?
    return nil unless pools_complete?

    pairs = barrage_pairs
    return nil if pairs.empty?

    round = create_round!(phase: "barrage", number: 1)
    pairs.each_with_index { |(player_a, player_b), position| build_match!(round, player_a, player_b, position) }
    round
  rescue ActiveRecord::RecordNotUnique
    # Deux requêtes concurrentes ont tenté de créer le même tour : l'index unique
    # a tranché, on renvoie celui qui a gagné.
    @tournament.barrage_rounds.first
  end

  # Appariement croisé. Les 2es par force DÉCROISSANTE face aux 3es par force
  # CROISSANTE : le meilleur 2e affronte le plus faible 3e, ce qui récompense le
  # classement de poule. Puis réparation des collisions « même poule ».
  #
  # `zip` complète avec nil quand une poule n'a pas de 3e (poule de 2, effectif
  # « Libre ») : build_match! en fait un bye, et ce 2e monte au tableau final
  # d'office. C'est le comportement voulu, et il ne demande aucun cas particulier.
  def barrage_pairs
    seconds = qualifiers_at(2)
    thirds  = qualifiers_at(3).reverse # déjà triés par force décroissante → croissante

    avoid_same_pool(seconds, thirds)
  end

  # Échange les 3es entre eux jusqu'à ce qu'aucun match n'oppose deux joueurs de la
  # même poule. Une solution existe toujours dès 2 poules (chaque poule ne fournit
  # qu'un 2e et qu'un 3e), et le balayage est déterministe — pas d'aléa, donc
  # reproductible à l'identique après correction.
  def avoid_same_pool(seconds, thirds)
    thirds = seconds.zip(thirds).map(&:last) # aligne les longueurs (nil = bye)

    seconds.each_index do |i|
      next unless same_pool?(seconds[i], thirds[i])

      swap = seconds.each_index.find do |j|
        j != i && !same_pool?(seconds[i], thirds[j]) && !same_pool?(seconds[j], thirds[i])
      end
      thirds[i], thirds[swap] = thirds[swap], thirds[i] if swap
    end

    seconds.zip(thirds)
  end

  def same_pool?(player_a, player_b)
    player_a.present? && player_b.present? && player_a.pool == player_b.pool
  end

  # ── Les tableaux, pilotés par la structure ──────────────────────────────────
  # Tous les nœuds jouables, dans l'ordre de dépendance (un tableau avant les
  # mini-tableaux nés de ses perdants). Les paliers d'ex æquo ne se jouent pas —
  # ils n'existent que pour attribuer une place (cf. TournamentStandings) — et les
  # barrages ont leur propre chemin.
  def playable_nodes = structure.nodes.reject { |node| node.transit? || node.tie? }

  def sync_nodes! = playable_nodes.map { |node| sync_node!(node) }

  # Deux seuls cas : le nœud n'est pas ouvert (ses sources sont-elles prêtes ?),
  # ou il est en cours (son dernier tour est-il terminé ?).
  def sync_node!(node)
    existing = rounds_of(node).to_a
    return open_node!(node) if existing.empty?
    return nil unless existing.last.complete?

    # #advance! renvoie nil quand le tableau a atteint sa finale : rien à créer.
    builder_for(node).advance!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Premier tour d'un tableau.
  #
  # ⚠️ On exige que TOUTES les sources soient jouées, pas seulement qu'il y ait
  # assez de monde pour apparier. La consolante se nourrit des 4es de poule ET des
  # perdants de barrage : les 4es sont connus dès la fin des poules, donc sans cette
  # garde le tableau s'ouvrirait à 4 joueurs au lieu de 8 et les perdants de barrage
  # n'y entreraient JAMAIS. Même piège pour le tableau final (1ers de poule connus
  # avant les vainqueurs de barrage).
  #
  # `entrants.size < 2` en revanche n'est pas une erreur : un tableau de 8 à 6
  # entrants ne produit que 2 perdants au premier tour, donc son mini-tableau des
  # 7e/8e n'aura jamais lieu. Le nœud reste simplement vide, et la compaction des
  # places absorbe le trou (cf. TournamentStandings).
  def open_node!(node)
    return nil unless sources_ready?(node)

    entrants = entrants_for(node)
    return nil if entrants.size < 2

    # Les entrants du tableau final sont les qualifiés du tournoi. Les perdants de
    # barrage ne sont PAS éliminés : ils rejoignent la consolante, donc ils restent
    # `active` — c'est le tableau final, et lui seul, qui qualifie.
    entrants.each { |tu| tu.update!(state: "qualified") } if node.key == "ok"

    builder_for(node, entrants).build!
  end

  # `owns_completion: false` : la finale du tableau final est souvent jouée alors
  # que la consolante et les matchs de classement tournent encore. C'est
  # #complete_if_finished! qui décide de la fin du tournoi, pas un tableau isolé.
  #
  # `persist_seeds` UNIQUEMENT pour le tableau final : `tournament_users.seed` est
  # une colonne unique par inscription, donc un second tableau écraserait les têtes
  # de série du premier. Les autres apparient sur l'ordre reçu (cf. BracketBuilder).
  #
  # `finalists` n'est nécessaire qu'au premier tour (#build!) ; #advance! dérive ses
  # entrants des vainqueurs du tour précédent.
  def builder_for(node, entrants = nil)
    BracketBuilder.new(@tournament, finalists: entrants, phase: node.phase, branch: node.branch,
                                    persist_seeds: node.key == "ok", owns_completion: false)
  end

  def rounds_of(node)
    @tournament.tournament_rounds.where(phase: node.phase, branch: node.branch).ordered
  end

  # ── Détection de l'aval périmé (cf. #reconcile!) ────────────────────────────
  # Le premier tour, dans l'ordre causal, dont les joueurs ne sont plus les bons.
  def first_stale_round(after: nil)
    rounds = final_rounds
    rounds = rounds.select { |_node, round| round.id > after.id } if after

    rounds.find { |node, round| stale?(node, round) }&.last
  end

  # Tous les tours jouables de la phase finale, ordre causal (= ordre des `id`).
  # Les barrages n'y figurent pas : ils naissent du classement des poules, qui ne
  # bouge pas quand on corrige un match de phase finale.
  def final_rounds
    playable_nodes.flat_map { |node| rounds_of(node).map { |round| [node, round] } }
                  .sort_by { |_node, round| round.id }
  end

  # Ce tour oppose-t-il encore les bons joueurs ?
  #
  # On compare des ENSEMBLES d'inscriptions, pas des appariements. C'est suffisant
  # ici, et seulement ici : à l'intérieur de la phase finale, l'ordre des entrants
  # ne dépend que du classement des poules (inchangé par cette correction) et de la
  # position des matchs sources. Un vainqueur qui change change donc forcément
  # QUI entre en aval, jamais seulement dans quel ordre.
  #
  # Entrants attendus vides = sources non résolues (le tour source a été détruit,
  # ou n'est plus complet) : on ne conclut rien plutôt que de détruire à l'aveugle.
  # Ce tour-là sera de toute façon repris par le tour source, forcément plus ancien.
  def stale?(node, round)
    expected = expected_entrants(node, round.number).map(&:id).to_set
    return false if expected.empty?

    expected != participants_of(round)
  end

  # Round 1 : les entrants du nœud. Tours suivants : les vainqueurs du précédent —
  # la même lecture que celle qui a servi à les créer.
  def expected_entrants(node, number)
    return entrants_for(node) if number == 1

    camp_of(node.key, number - 1, :winner)
  end

  def participants_of(round)
    round.tournament_matches.flat_map { |match| [match.player_a_id, match.player_b_id] }.compact.to_set
  end

  # ── Résolution des sources ──────────────────────────────────────────────────
  # Toutes les sources d'un nœud ont-elles livré leur contenu DÉFINITIF ?
  #
  # Un tour source jamais créé (parce que son tableau n'a pas assez d'entrants)
  # laisse le nœud fermé pour toujours, et c'est le comportement voulu : personne
  # n'y jouera, donc ses places ne seront pas attribuées.
  def sources_ready?(node)
    node.sources.all? do |source|
      case source
      when CriteriumStructure::PoolQualifiers then pools_complete?
      when CriteriumStructure::Winners, CriteriumStructure::Losers
        round_complete?(source.key, source.round)
      else false
      end
    end
  end

  def round_complete?(key, number)
    node  = structure.node(key)
    round = node && rounds_of(node).find { |r| r.number == number }

    round.present? && round.complete?
  end

  def resolve(source)
    case source
    when CriteriumStructure::PoolQualifiers then qualifiers_at(source.rank)
    when CriteriumStructure::Winners        then camp_of(source.key, source.round, :winner)
    when CriteriumStructure::Losers         then camp_of(source.key, source.round, :loser)
    else []
    end
  end

  # Les vainqueurs (ou les perdants) du tour `number` d'un nœud, dans l'ordre des
  # matchs. [] si le tour n'existe pas ou n'est pas fini : c'est ce qui empêche
  # d'ouvrir un tableau avec des entrants incomplets.
  #
  # ⚠️ Les byes ne sont écartés que du côté PERDANTS : le « perdant » d'un bye
  # n'existe pas, mais son vainqueur, oui — c'est le joueur exempté, et il doit
  # continuer. Un barrage sans 3e de poule (poule incomplète) est un bye dont le 2e
  # monte d'office au tableau final ; l'écarter le ferait disparaître du tournoi.
  #
  # C'est aussi ce qui rend juste la formule des places : un tableau de 8 à 6
  # entrants n'envoie que 2 joueurs vers son mini-tableau 5e-8e, pas 4.
  def camp_of(key, number, camp)
    node  = structure.node(key)
    round = node && rounds_of(node).find { |r| r.number == number }
    return [] if round.blank? || !round.complete?

    matches = round.tournament_matches.sort_by(&:position)
    matches = matches.reject(&:is_bye) if camp == :loser

    matches.filter_map(&camp)
  end

  # Post-passe : écarter du premier tour deux joueurs de la même poule (ils
  # viennent de s'y affronter). `protected_count` = nombre d'entrants de tête qu'on
  # ne déplace PAS, pour ne pas défaire le seeding des 1ers de poule. Si aucun
  # échange ne résout la collision, on la laisse : le tableau doit exister, une
  # affiche imparfaite valant mieux qu'un blocage.
  def avoid_own_pool_first_round(entrants, protected_count:)
    entrants = entrants.dup
    swappable = (protected_count...entrants.size).to_a

    first_round_pairs(entrants.size).each do |index_a, index_b|
      next unless same_pool?(entrants[index_a], entrants[index_b])

      # On déplace celui des deux qui n'est pas protégé.
      moving = swappable.include?(index_b) ? index_b : index_a
      other  = moving == index_b ? index_a : index_b

      target = swappable.find do |j|
        next false if j == moving
        # L'adversaire de la place visée peut être un bye (nil) : personne à heurter.
        partner = partner_of(j, entrants.size)

        !same_pool?(entrants[other], entrants[j]) &&
          (partner.nil? || !same_pool?(entrants[partner], entrants[moving]))
      end
      entrants[moving], entrants[target] = entrants[target], entrants[moving] if target
    end

    entrants
  end

  # Les paires du premier tour, exprimées en INDEX dans le tableau des entrants
  # (BracketBuilder apparie sur l'index, pas sur la colonne `seed`). Les byes
  # (index hors effectif) sont écartés : ils n'opposent personne.
  def first_round_pairs(count)
    slots = next_power_of_two(count)
    BracketBuilder.new(@tournament).seed_order(slots)
                  .each_slice(2)
                  .filter_map do |seed_a, seed_b|
                    pair = [seed_a - 1, seed_b - 1]
                    pair if pair.all? { |index| index < count }
                  end
  end

  # L'adversaire de l'entrant d'index `index` au premier tour (nil = bye).
  def partner_of(index, count)
    pair = first_round_pairs(count).find { |a, b| [a, b].include?(index) }
    pair && (pair.first == index ? pair.last : pair.first)
  end

  # ── Fin de tournoi ──────────────────────────────────────────────────────────
  # Le tournoi n'est terminé que quand il n'y a plus RIEN à créer ni à jouer.
  #
  # `created.any?` est le cœur de la règle, et ce n'est pas une optimisation : ce
  # service étant une fonction pure de l'état, si un passage n'a rien créé et que
  # tout est joué, alors aucun passage ultérieur ne créera quoi que ce soit sans
  # nouveau score — c'est un point fixe. Sans cette garde, un tour intégralement
  # composé de byes (donc « terminé » à la création) ferait conclure le tournoi
  # alors que son tour suivant reste à générer.
  def complete_if_finished!(created)
    return if @tournament.completed?
    return if created.any?
    return unless ok_finished? # le champion doit être connu
    return unless @tournament.tournament_rounds.final_phase.all?(&:complete?)

    @tournament.update!(status: "completed")
  end

  # Le tableau final est-il allé jusqu'à sa finale (dernier tour = 1 seul match) ?
  #
  # Une poule unique (≤ 7 joueurs) n'a AUCUN tableau : exiger une finale y
  # laisserait le tournoi éternellement « en cours » alors que tout est joué et que
  # le classement de la poule a déjà désigné le vainqueur.
  def ok_finished?
    return true if structure.node("ok").blank?

    last = @tournament.bracket_rounds.last
    last.present? && last.complete? && last.tournament_matches.size == 1
  end

  # ── Lecture de l'état ───────────────────────────────────────────────────────
  def pools_complete?
    standings.any? && standings.values.all?(&:complete?)
  end

  # Les Nes de chaque poule, toutes poules confondues, triés par force.
  # C'est PoolStandings (règlement FFTT) qui décide du rang dans la poule.
  def qualifiers_at(rank)
    by_strength(standings.values.filter_map { |pool| pool.qualifier(rank) })
  end

  # Ordre de force inter-poules. Le règlement FFTT ne définit pas de classement
  # entre poules (il s'appuie sur le classement officiel des joueurs, que l'app
  # n'a pas) : on réutilise donc #rank_key, cohérent avec le reste de l'app et
  # surtout DÉTERMINISTE (draw_order en dernier ressort).
  def by_strength(players) = players.sort_by { |tu| @tournament.rank_key(tu) }

  def standings = @standings ||= @tournament.pool_standings

  # ── Écriture ────────────────────────────────────────────────────────────────
  # Passe en "completed" tout tour dont les matchs sont tous joués. PoolBuilder ne
  # le fait plus pour nous : #advance! court-circuite sa boucle habituelle.
  def close_finished_rounds!
    rounds = @tournament.tournament_rounds.where(phase: %w[pool] + Tournament::FINAL_PHASES)
    rounds.where.not(status: "completed").each do |round|
      round.update!(status: "completed") if round.complete?
    end
  end

  def create_round!(phase:, number:, branch: TournamentRound::MAIN_BRANCH)
    @tournament.tournament_rounds.create!(phase: phase, branch: branch, number: number,
                                         status: "in_progress")
  end

  # Le tour de phase finale le plus récent — valeur de retour par défaut d'#advance!
  # quand il n'y avait rien à créer.
  def current_final_round
    @tournament.tournament_rounds.final_phase.order(:id).last
  end

  def next_power_of_two(count)
    power = 1
    power *= 2 while power < count
    [power, 2].max
  end
end
