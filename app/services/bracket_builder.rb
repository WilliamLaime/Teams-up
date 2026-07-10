# ── Service BracketBuilder ────────────────────────────────────────────────────
# Construit et fait avancer le tableau final à élimination directe (Lot 3).
#
#   • #build!   : premier tour. Sélectionne les finalistes (qualifiés + meilleurs
#     actifs si besoin), leur attribue une tête de série, puis pose les matchs selon
#     le seeding standard (1 vs N, 2 vs N-1…) qui garantit que les têtes de série 1
#     et 2 ne peuvent se rencontrer qu'en finale. Les places manquantes (effectif ≠
#     puissance de 2) deviennent des byes offerts aux meilleures têtes de série.
#
#   • #advance! : tour suivant, en appariant les vainqueurs du tour précédent. Quand
#     il ne reste qu'un vainqueur, le tournoi passe en "completed".
#
# Seeding réel (Lot 4) : classement par victoires, puis set average et point average
# (cf. #ranked) — les compteurs sont recalculés par SwissPairing#recompute_stats!.
class BracketBuilder
  # `finalists` (optionnel) : liste de TournamentUser à faire entrer dans le tableau.
  # Le suisse le laisse nil (les finalistes sont dérivés de l'état qualified/active) ;
  # le championnat / les poules injectent leur propre top-N (cf. LeagueBuilder / PoolBuilder).
  def initialize(tournament, finalists: nil)
    @tournament = tournament
    @finalists  = finalists
  end

  # Premier tour du tableau final.
  def build!
    finalists = @finalists || select_finalists
    assign_seeds!(finalists)

    slots = next_power_of_two(finalists.size)
    seed_to_player = finalists.index_by(&:seed)
    round = @tournament.tournament_rounds.create!(phase: "bracket", number: 1, status: "in_progress")

    seed_order(slots).each_slice(2).with_index do |(seed_a, seed_b), position|
      player_a = seed_to_player[seed_a]
      player_b = seed_to_player[seed_b]
      # Sécurité : la tête de série la plus faible peut manquer (bye) → garder un player_a valide.
      player_a, player_b = player_b, player_a if player_a.nil?

      round.tournament_matches.create!(
        player_a: player_a, player_b: player_b, is_bye: player_b.nil?, position: position
      )
    end

    round
  end

  # Tour suivant (ou clôture du tournoi).
  def advance!
    last = @tournament.bracket_rounds.last
    return last unless last&.complete?

    winners = last.tournament_matches.order(:position).map(&:winner)
    if winners.size <= 1
      @tournament.update!(status: "completed")
      return nil
    end

    round = @tournament.tournament_rounds.create!(phase: "bracket", number: last.number + 1, status: "in_progress")
    winners.each_slice(2).with_index do |(player_a, player_b), position|
      round.tournament_matches.create!(
        player_a: player_a, player_b: player_b, is_bye: player_b.nil?, position: position
      )
    end

    round
  end

  private

  # Finalistes : qualifiés d'abord, complétés au besoin par les meilleurs actifs.
  # Plafonné à final_size ; les éliminés ne sont jamais repêchés.
  def select_finalists
    scope = @tournament.tournament_users.players.approved
    qualified = ranked(scope.qualified)
    return qualified.first(@tournament.final_size) if qualified.size >= @tournament.final_size

    (qualified + ranked(scope.active)).first(@tournament.final_size)
  end

  # Classe une relation de joueurs par force (seeding réel, Lot 4) : victoires desc,
  # défaites asc, puis set average et point average desc. Déterministe.
  def ranked(relation)
    relation.to_a.sort_by { |tu| [-tu.wins, tu.losses, -tu.set_average, -tu.point_average] }
  end

  # Attribue les têtes de série 1..N dans l'ordre de force.
  def assign_seeds!(finalists)
    finalists.each_with_index { |tu, index| tu.update!(seed: index + 1) }
  end

  # Ordre de seeding standard d'un tableau à `slots` places (puissance de 2).
  # Ex. slots=8 → [1, 8, 4, 5, 2, 7, 3, 6] : découpé par paires, 1 et 2 sont en moitiés opposées.
  def seed_order(slots)
    order = [1]
    while order.size < slots
      mirror = (order.size * 2) + 1
      order = order.flat_map { |seed| [seed, mirror - seed] }
    end
    order
  end

  # Plus petite puissance de 2 ≥ `count` (au minimum 2).
  def next_power_of_two(count)
    power = 1
    power *= 2 while power < count
    [power, 2].max
  end
end
