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
# ── Deux régimes de progression ──────────────────────────────────────────────
# Par défaut, #advance! attend que le tour précédent soit ENTIÈREMENT joué avant
# de créer le suivant : c'est le régime des playoffs de la ronde suisse et du
# championnat, où tout le monde joue le même jour.
#
# `incremental: true` (Critérium Fédéral, cf. CriteriumFlow#builder_for) crée
# chaque match du tour n+1 DÈS QUE ses deux matchs nourriciers sont joués. Sur un
# tournoi étalé dans le temps, un quart de finale devient donc jouable sans
# attendre les trois autres huitièmes.
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
  # `incremental` : progression anticipée (cf. l'en-tête du fichier). Réservé au
  #   Critérium — les autres formats gardent le régime historique, et c'est
  #   volontaire : ce mode renseigne `expected_matches`, une colonne que seul
  #   CriteriumFlow sait tenir à jour.
  def initialize(tournament, finalists: nil, phase: "bracket", branch: TournamentRound::MAIN_BRANCH,
                 persist_seeds: true, owns_completion: true, incremental: false)
    @tournament      = tournament
    @finalists       = finalists
    @phase           = phase
    @branch          = branch
    @persist_seeds   = persist_seeds
    @owns_completion = owns_completion
    @incremental     = incremental
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
    # `slots / 2` est EXACTEMENT le nombre de matchs posés juste en dessous (byes
    # inclus) : la colonne ne décrit donc rien de nouveau, elle rend seulement
    # l'invariant lisible par TournamentRound#complete?.
    round   = create_round!(number: 1, expected_matches: @incremental ? slots / 2 : nil)

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
    return advance_incrementally! if @incremental

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

  def create_round!(number:, expected_matches: nil)
    @tournament.tournament_rounds.create!(phase: @phase, branch: @branch, number: number,
                                          status: "in_progress", expected_matches: expected_matches)
  end

  # ── Progression anticipée (mode incrémental) ────────────────────────────────
  # Chaque appel complète UN tour, puis on recommence : créer la demi-finale peut
  # rendre la finale créable dans la même passe. La boucle termine parce qu'un
  # tableau a un nombre borné de tours et qu'on ne repasse jamais sur un tour déjà
  # complet.
  #
  # ⚠️ Renvoie nil quand rien n'a été créé — JAMAIS un tour existant. C'est un
  # contrat, pas un détail : CriteriumFlow#complete_if_finished! renonce à
  # terminer le tournoi dès que la passe a créé quelque chose, donc un retour
  # non-nil systématique empêcherait le tournoi de se terminer, définitivement.
  def advance_incrementally!
    created = nil

    while (round = fill_next_round!)
      created = round
    end

    complete_tournament_if_owned!
    created
  end

  # Le premier tour, dans l'ordre, auquel il manque un match créable. nil = rien à
  # faire (soit tout est créé, soit les nourriciers ne sont pas joués).
  #
  # ⚠️ On balaie TOUS les tours, pas seulement le dernier : dès qu'un tour n+1
  # partiel existe, `rounds.last` le désigne et on ne reviendrait jamais compléter
  # le tour n. C'est la différence de fond avec le régime historique.
  def fill_next_round!
    series = rounds.to_a
    return nil if series.empty?

    expected = expected_count_of(series.first)

    series.each do |round|
      # Un tour à un seul match est la finale du tableau : rien en aval.
      return nil if expected <= 1

      filled = fill_successor_of!(round, expected / 2)
      return filled if filled

      expected /= 2
    end

    nil
  end

  # Pose dans le successeur de `round` tous les matchs dont les deux nourriciers
  # sont joués. Renvoie le tour successeur si au moins un match a été créé.
  def fill_successor_of!(round, expected)
    successor = rounds.find { |r| r.number == round.number + 1 }
    return nil if successor && successor.tournament_matches.count >= expected

    feeders = round.tournament_matches.index_by(&:position)
    created = false

    expected.times do |position|
      pair = feeders.values_at(position * 2, (position * 2) + 1)
      # Les DEUX nourriciers doivent être joués : c'est ce qui autorise à jouer un
      # quart sans attendre les autres huitièmes, et ce qui interdit de créer un
      # match dont un adversaire est encore inconnu.
      next unless pair.all? { |match| match&.status == "completed" }

      successor ||= reopen_or_create_successor!(round, expected)
      next if successor.tournament_matches.exists?(position: position)

      created = true if place_match!(successor, pair, position)
    end

    created ? successor : nil
  end

  # Le tour successeur, prêt à recevoir un match. S'il existe déjà en "completed"
  # (données antérieures à ce mode, ou tour clos avant l'ajout d'un match), on le
  # rouvre : un tour clos est VERROUILLÉ, donc son nouveau match serait injouable
  # (cf. TournamentMatchPolicy#update?).
  def reopen_or_create_successor!(round, expected)
    existing = rounds.find { |r| r.number == round.number + 1 }
    if existing
      existing.update!(status: "in_progress") if existing.status == "completed"
      existing.update!(expected_matches: expected) if existing.expected_matches != expected
      return existing
    end

    create_round!(number: round.number + 1, expected_matches: expected)
  end

  # ⚠️ SAVEPOINT obligatoire (`requires_new: true`) : en PostgreSQL une violation
  # d'unicité AVORTE la transaction courante. Sans point de reprise, deux passes
  # concurrentes feraient perdre SILENCIEUSEMENT tout le travail de #advance!,
  # le `rescue` de CriteriumFlow#sync_node! avalant l'erreur.
  def place_match!(round, pair, position)
    player_a, player_b = pair_players(pair)

    ActiveRecord::Base.transaction(requires_new: true) do
      build_match!(round, player_a, player_b, position)
    end
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Les deux joueurs qui montent, un forfait déclaré entre-temps écarté : gagner
  # son huitième puis abandonner ne doit pas faire traverser tout le tableau en
  # défaites. L'adversaire prend alors un bye plutôt qu'une victoire par forfait.
  #
  # ⚠️ Cas dégénéré : les DEUX vainqueurs ont abandonné. Aucun match n'est alors
  # créable (`player_a` est NOT NULL), et laisser la position vide gèlerait la
  # branche pour toujours — le tableau ne finirait jamais et le tournoi non plus.
  # On retombe donc sur le comportement historique : un match en forfait, dont le
  # « vainqueur » poursuit et prend des byes ensuite. Laid, mais vivant.
  def pair_players(pair)
    raw     = pair.map(&:winner)
    playing = raw.map { |player| player&.withdrawn? ? nil : player }

    playing.compact.empty? ? raw : playing
  end

  # Nombre de matchs attendus au premier tour. La colonne d'abord ; à défaut le
  # compte réel, qui est exact parce que #build! crée TOUJOURS le premier tour
  # d'un bloc, byes inclus (utile sur les tours antérieurs au backfill).
  def expected_count_of(round) = round.expected_matches || round.tournament_matches.count

  # Le mode incrémental sert au Critérium, où `owns_completion` est false : c'est
  # CriteriumFlow qui décide de la fin du tournoi, en regardant TOUS les tableaux.
  # La garde reste explicite pour que le mode soit correct hors de ce contexte.
  def complete_tournament_if_owned!
    return unless @owns_completion

    last = rounds.last
    return unless last && expected_count_of(rounds.first) / (2**(last.number - rounds.first.number)) <= 1
    return unless last.complete?

    @tournament.update!(status: "completed")
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
