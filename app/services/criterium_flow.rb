# ── Service CriteriumFlow ─────────────────────────────────────────────────────
# Moteur du format « Critérium Fédéral » (FFTT). MATÉRIALISE en TournamentRound la
# topologie déclarée par CriteriumStructure : barrages, tableau final (« OK »), puis
# (Lot 5) consolante et mini-tableaux de classement.
#
# ── Un réconciliateur, pas une machine à états ─────────────────────────────────
# #advance! ne demande jamais « où en est-on ? ». Il recalcule à chaque appel les
# tours qui DEVRAIENT exister d'après les tours déjà terminés, et ne crée que ceux
# qui manquent. Deux propriétés en découlent, toutes deux indispensables :
#
#   • idempotence — double-clic, rechargement Turbo, appels concurrents : le
#     deuxième appel ne crée rien. L'index unique (tournoi, phase, branche, numéro)
#     est le garde-fou de dernier recours, exactement comme pour les journées de poule.
#   • déterminisme — aucun `shuffle`, `rand` ni `Time.now` ici. `draw_order`, tiré
#     une fois au lancement, est la seule source d'aléa. C'est la condition pour
#     qu'une correction de score (Lot 8) puisse détruire l'aval et le reconstruire
#     à l'identique.
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
      close_finished_rounds!

      created = [ensure_barrage!, ensure_ok_bracket!, advance_ok!].compact
      complete_if_finished!

      created.last || current_final_round
    end
  end

  private

  # ── Barrages ────────────────────────────────────────────────────────────────
  # Les 2es de poule contre les 3es, croisés. Nœud de TRANSIT : les vainqueurs
  # montent au tableau final, les perdants descendront en consolante (Lot 5).
  def ensure_barrage!
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

  # ── Tableau final (« OK ») ──────────────────────────────────────────────────
  def ensure_ok_bracket!
    return nil if @tournament.bracket_rounds.exists?
    return nil unless barrage_done?

    finalists = ok_finalists
    return nil if finalists.size < 2

    # Les entrants du tableau final sont les qualifiés du tournoi. Les perdants de
    # barrage ne sont PAS éliminés : ils rejoignent la consolante (Lot 5), donc on
    # les laisse `active`.
    finalists.each { |tu| tu.update!(state: "qualified") }

    ok_builder(finalists: finalists).build!
  rescue ActiveRecord::RecordNotUnique
    @tournament.bracket_rounds.first
  end

  # Les 1ers de poule (exemptés de barrage) prennent les têtes de série hautes, les
  # vainqueurs de barrage les basses. L'ordre miroir de BracketBuilder#seed_order
  # (1 vs N, 2 vs N-1…) garantit alors qu'aucun 1er de poule n'en rencontre un autre
  # au premier tour — c'est l'« ordre protégé » du règlement.
  def ok_finalists
    firsts   = qualifiers_at(1)
    promoted = barrage_winners

    avoid_own_pool_first_round(firsts + promoted, protected_count: firsts.size)
  end

  # Post-passe : un vainqueur de barrage ne doit pas retomber sur le 1er de SA
  # PROPRE poule au premier tour (il vient de le côtoyer en poule). On n'échange
  # que des vainqueurs de barrage entre eux, pour ne pas défaire le seeding des
  # 1ers de poule. Si aucun échange ne résout la collision, on la laisse : le
  # tableau doit exister, une affiche imparfaite valant mieux qu'un blocage.
  def avoid_own_pool_first_round(entrants, protected_count:)
    entrants = entrants.dup
    swappable = (protected_count...entrants.size).to_a

    first_round_pairs(entrants.size).each do |index_a, index_b|
      next unless same_pool?(entrants[index_a], entrants[index_b])

      # On déplace celui des deux qui est un vainqueur de barrage.
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

  # Tour suivant du tableau final. Ne fait rien tant que le tour courant n'est pas
  # terminé — c'est ce qui rend un second appel inoffensif.
  def advance_ok!
    last = @tournament.bracket_rounds.last
    return nil unless last&.complete?

    ok_builder.advance!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # `owns_completion: false` : la finale du tableau final est souvent jouée alors
  # que la consolante et les matchs de classement tournent encore (Lot 5). C'est
  # #complete_if_finished! qui décide de la fin du tournoi, pas le tableau.
  # `finalists` n'est nécessaire qu'au premier tour (#build!) ; #advance! dérive
  # ses entrants des vainqueurs du tour précédent.
  def ok_builder(finalists: nil)
    BracketBuilder.new(@tournament, finalists: finalists, phase: "bracket",
                                   owns_completion: false)
  end

  # ── Fin de tournoi ──────────────────────────────────────────────────────────
  # Le tournoi n'est terminé que quand TOUS les tableaux le sont — pas seulement
  # le tableau final.
  def complete_if_finished!
    return if @tournament.completed?
    return unless ok_finished?
    return unless @tournament.tournament_rounds.final_phase.all?(&:complete?)

    @tournament.update!(status: "completed")
  end

  # Le tableau final est-il allé jusqu'à sa finale (dernier tour = 1 seul match) ?
  def ok_finished?
    last = @tournament.bracket_rounds.last
    last.present? && last.complete? && last.tournament_matches.size == 1
  end

  # ── Lecture de l'état ───────────────────────────────────────────────────────
  def pools_complete?
    standings.any? && standings.values.all?(&:complete?)
  end

  def barrage_done?
    round = @tournament.barrage_rounds.first
    round.present? && round.complete?
  end

  # Les vainqueurs de barrage (byes inclus : un 2e sans 3e monte d'office),
  # triés par force pour prendre les têtes de série basses du tableau final.
  def barrage_winners
    round = @tournament.barrage_rounds.first
    return [] if round.blank?

    by_strength(round.tournament_matches.map(&:winner).compact)
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
