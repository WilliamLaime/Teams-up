# ── Service BracketBuilder ────────────────────────────────────────────────────
# Construit et fait avancer UN tableau à élimination directe (Lot 3).
#
#   • #build!   : premier tour. Sélectionne les finalistes (qualifiés + meilleurs
#     actifs si besoin), leur attribue une tête de série, puis pose les matchs selon
#     le seeding standard (1 vs N, 2 vs N-1…) qui garantit que les têtes de série 1
#     et 2 ne peuvent se rencontrer qu'en finale. Les places manquantes (effectif ≠
#     puissance de 2) deviennent des byes offerts aux meilleures têtes de série.
#
#   • #advance! : tour suivant, en appariant les vainqueurs du tour précédent. Quand
#     il ne reste qu'un vainqueur, le tableau est terminé.
#
# Seeding réel (Lot 4) : classement par victoires, puis set average et point average
# (cf. #ranked) — les compteurs sont recalculés par SwissPairing#recompute_stats!.
#
# ── Réutilisation par le Critérium Fédéral ────────────────────────────────────
# Le Critérium joue PLUSIEURS tableaux : le tableau final (« OK »), la consolante
# (« KO ») et les mini-tableaux de classement (3e/4e, 5e-8e…). Ce sont tous le même
# objet — un tableau à élimination directe — d'où le paramétrage `phase:` / `branch:`.
# Toutes les valeurs par défaut reproduisent le comportement historique : la ronde
# suisse, le championnat et les poules classiques ne voient aucune différence.
class BracketBuilder
  include RoundRobinStats

  # `finalists` (optionnel) : liste de TournamentUser à faire entrer dans le tableau,
  #   DÉJÀ ordonnée par force (le 1er élément prend la tête de série 1).
  #   Le suisse le laisse nil (les finalistes sont dérivés de l'état qualified/active) ;
  #   le championnat / les poules injectent leur propre top-N (cf. LeagueBuilder /
  #   PoolBuilder), et le Critérium ses entrants par table (cf. CriteriumFlow).
  # `phase` / `branch` : quel tableau on construit (cf. TournamentRound).
  # `persist_seeds` : écrire la tête de série sur tournament_users.seed. À laisser
  #   false pour tout tableau SECONDAIRE — `seed` est une colonne unique par
  #   inscription, donc la consolante écraserait les têtes de série du tableau final.
  # `owns_completion` : ce tableau décide-t-il de la fin du tournoi ? false pour le
  #   Critérium, où la finale « OK » est souvent jouée alors que la consolante et
  #   les matchs de classement tournent encore (cf. CriteriumFlow#advance!).
  def initialize(tournament, finalists: nil, phase: "bracket", branch: TournamentRound::MAIN_BRANCH,
                 persist_seeds: true, owns_completion: true)
    @tournament      = tournament
    @finalists       = finalists
    @phase           = phase
    @branch          = branch
    @persist_seeds   = persist_seeds
    @owns_completion = owns_completion
  end

  # Premier tour du tableau.
  def build!
    entrants = @finalists || select_finalists
    assign_seeds!(entrants) if @persist_seeds

    slots = next_power_of_two(entrants.size)
    # Appariement sur l'INDEX dans le tableau reçu, et non sur la colonne `seed` :
    # un tableau secondaire ne persiste pas les têtes de série (cf. persist_seeds),
    # et deux tableaux concurrents s'écraseraient mutuellement.
    by_seed = entrants.each_with_index.to_h { |tu, index| [index + 1, tu] }
    round   = create_round!(number: 1)

    seed_order(slots).each_slice(2).with_index do |(seed_a, seed_b), position|
      player_a = by_seed[seed_a]
      player_b = by_seed[seed_b]
      # Sécurité : la tête de série la plus faible peut manquer (bye) → garder un
      # player_a valide, la colonne est NOT NULL.
      player_a, player_b = player_b, player_a if player_a.nil?

      build_match!(round, player_a, player_b, position)
    end

    round
  end

  # Tour suivant. Renvoie nil quand le tableau est terminé (un seul vainqueur), et
  # clôt alors le tournoi si ce tableau en est responsable.
  def advance!
    last = rounds.last
    return last unless last&.complete?

    winners = last.tournament_matches.order(:position).map(&:winner)
    if winners.size <= 1
      @tournament.update!(status: "completed") if @owns_completion
      return nil
    end

    round = create_round!(number: last.number + 1)
    winners.each_slice(2).with_index do |(player_a, player_b), position|
      build_match!(round, player_a, player_b, position)
    end

    round
  end

  # Ordre de seeding standard d'un tableau à `slots` places (puissance de 2).
  # Ex. slots=8 → [1, 8, 4, 5, 2, 7, 3, 6] : découpé par paires, 1 et 2 sont en
  # moitiés opposées. Public : CriteriumFlow s'en sert pour vérifier ses appariements.
  #
  # Exposé AUSSI en méthode de classe : la vue du tableau final s'en sert pour
  # annoncer les têtes de série attendues sur les cases encore vides de la
  # première colonne (cf. TournamentsHelper#bracket_seed_labels), sans avoir à
  # instancier un builder — le calcul ne dépend que du nombre de places.
  def self.seed_order(slots)
    order = [1]
    while order.size < slots
      mirror = (order.size * 2) + 1
      order = order.flat_map { |seed| [seed, mirror - seed] }
    end
    order
  end

  def seed_order(slots) = self.class.seed_order(slots)

  private

  # Les tours DE CE TABLEAU (phase + branche), dans l'ordre.
  def rounds = @tournament.tournament_rounds.where(phase: @phase, branch: @branch).ordered

  def create_round!(number:)
    @tournament.tournament_rounds.create!(phase: @phase, branch: @branch,
                                          number: number, status: "in_progress")
  end

  # Finalistes : qualifiés d'abord, complétés au besoin par les meilleurs actifs.
  # Plafonné à final_size ; les éliminés ne sont jamais repêchés.
  def select_finalists
    scope = @tournament.tournament_users.players.approved
    qualified = ranked(scope.qualified)
    return qualified.first(@tournament.final_size) if qualified.size >= @tournament.final_size

    (qualified + ranked(scope.active)).first(@tournament.final_size)
  end

  # Classe une relation de joueurs par force (seeding réel, Lot 4) — mêmes critères
  # que le classement affiché (Tournament#rank_key, Lot 6), source unique de vérité.
  def ranked(relation)
    relation.to_a.sort_by { |tu| @tournament.rank_key(tu) }
  end

  # Attribue les têtes de série 1..N dans l'ordre de force.
  def assign_seeds!(finalists)
    finalists.each_with_index { |tu, index| tu.update!(seed: index + 1) }
  end

  # Plus petite puissance de 2 ≥ `count` (au minimum 2).
  def next_power_of_two(count)
    power = 1
    power *= 2 while power < count
    [power, 2].max
  end
end
