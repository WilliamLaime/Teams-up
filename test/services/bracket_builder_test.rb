require "test_helper"

# Tests du moteur « Tableau final » (BracketBuilder).
#
# Ce fichier est un FILET DE SÉCURITÉ : BracketBuilder est réutilisé par les trois
# formats (ronde suisse, poules, championnat) et va être paramétré pour le Critérium
# Fédéral (phase/branche, consolante, mini-tableaux de classement). Ces tests figent
# le comportement actuel afin qu'un refactor le préserve.
#
# Deux propriétés sont testées de près, car tout le reste en dépend :
#   • l'ordre de seeding standard (les têtes de série 1 et 2 ne peuvent se
#     rencontrer qu'en finale) ;
#   • les byes, offerts aux MEILLEURES têtes de série quand l'effectif n'est pas
#     une puissance de 2.
class BracketBuilderTest < ActiveSupport::TestCase
  def setup
    # Ping-pong : mode :sets (11 points, best_of 5 → 7 en finale), le sport visé
    # par le Critérium Fédéral. `slug` unique pour ne pas heurter les seeds.
    @sport = Sport.create!(name: "Ping test", slug: "ping-pong-#{SecureRandom.hex(4)}", icon: "🏓")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  # Tournoi « poules » sans aucune ronde jouée : on appelle BracketBuilder
  # directement avec des finalistes explicites, pour tester le tableau seul.
  def build_tournament(count, bracket_size: nil)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                   format: "poules", status: "in_progress", max_players: count,
                                   bracket_size: bracket_size,
                                   date: Date.tomorrow, place: "Terrain test")
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      # draw_order croissant : ordre stable et reproductible (en production il est
      # tiré au sort une fois au lancement par TournamentsController#assign_draw_order!).
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved",
                                         draw_order: i)
    end
    tournament
  end

  # Finalistes dans un ordre de force explicite : on force `wins` décroissant pour
  # que Tournament#rank_key (donc assign_seeds!) attribue les seeds 1..N dans
  # l'ordre du tableau renvoyé.
  def finalists_in_seed_order(tournament, count)
    players = tournament.tournament_users.players.order(:draw_order).to_a.first(count)
    players.each_with_index { |tu, i| tu.update!(wins: count - i) }
    players
  end

  def play_round!(round, winners_by_position: nil)
    round.tournament_matches.where(is_bye: false).order(:position).each do |match|
      winner = winners_by_position ? winners_by_position.call(match) : match.player_a
      win_tournament_match!(match, winner)
    end
    round
  end

  # ── Ordre de seeding standard ────────────────────────────────────────────────

  test "seed_order : ordre protégé standard pour 2, 4, 8 et 16 places" do
    builder = BracketBuilder.new(build_tournament(2))

    assert_equal [1, 2], builder.send(:seed_order, 2)
    assert_equal [1, 4, 2, 3], builder.send(:seed_order, 4)
    # L'ordre du règlement FFTT : 1-8 · 4-5 · 2-7 · 3-6.
    assert_equal [1, 8, 4, 5, 2, 7, 3, 6], builder.send(:seed_order, 8)
    assert_equal [1, 16, 8, 9, 4, 13, 5, 12, 2, 15, 7, 10, 3, 14, 6, 11],
                 builder.send(:seed_order, 16)
  end

  test "seed_order : les seeds 1 et 2 sont dans des moitiés opposées" do
    builder = BracketBuilder.new(build_tournament(2))

    [4, 8, 16, 32].each do |slots|
      order = builder.send(:seed_order, slots)
      half  = order.first(slots / 2)
      assert_includes half, 1, "le seed 1 doit être dans la 1re moitié (#{slots} places)"
      refute_includes half, 2, "le seed 2 doit être dans la 2e moitié (#{slots} places)"
    end
  end

  # ── build! ──────────────────────────────────────────────────────────────────

  test "build! : 8 finalistes → 4 matchs, aucun bye, seeds 1..8 persistés" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 8)

    round = BracketBuilder.new(tournament, finalists: finalists).build!

    assert_equal "bracket", round.phase
    assert_equal 1, round.number
    assert_equal "in_progress", round.status
    assert_equal 4, round.tournament_matches.count
    refute round.tournament_matches.any?(&:is_bye), "8 finalistes = puissance de 2 → aucun bye"
    assert_equal (1..8).to_a, finalists.map { |tu| tu.reload.seed }.sort
  end

  test "build! : les appariements du 1er tour suivent l'ordre protégé" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 8)

    round = BracketBuilder.new(tournament, finalists: finalists).build!

    pairs = round.tournament_matches.order(:position).map do |match|
      [match.player_a.reload.seed, match.player_b.reload.seed].sort
    end
    assert_equal [[1, 8], [4, 5], [2, 7], [3, 6]], pairs
  end

  test "build! : 6 finalistes → tableau de 8, les 2 byes vont aux meilleurs seeds" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 6)

    round = BracketBuilder.new(tournament, finalists: finalists).build!

    assert_equal 4, round.tournament_matches.count, "tableau de 8 → 4 matchs (byes compris)"
    byes = round.tournament_matches.select(&:is_bye)
    assert_equal 2, byes.size, "6 finalistes dans 8 places → 2 byes"
    # Les places 7 et 8 sont vides → leurs adversaires (seeds 1 et 2) sont exemptés.
    assert_equal [1, 2], byes.map { |m| m.player_a.reload.seed }.sort
    # Un bye ne doit jamais laisser player_a nil (contrainte NOT NULL + affichage).
    assert byes.all? { |m| m.player_a.present? && m.player_b.nil? }
  end

  test "build! : 5 finalistes → tableau de 8, 3 byes aux seeds 1, 2 et 3" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 5)

    round = BracketBuilder.new(tournament, finalists: finalists).build!

    byes = round.tournament_matches.select(&:is_bye)
    assert_equal 3, byes.size
    assert_equal [1, 2, 3], byes.map { |m| m.player_a.reload.seed }.sort
    # Un seul match réellement joué au 1er tour (seeds 4 et 5).
    real = round.tournament_matches.reject(&:is_bye)
    assert_equal 1, real.size
    assert_equal [4, 5], [real.first.player_a.reload.seed, real.first.player_b.reload.seed].sort
  end

  test "build! : chaque finaliste apparaît exactement une fois dans le tableau" do
    tournament = build_tournament(16, bracket_size: 16)
    finalists  = finalists_in_seed_order(tournament, 11)

    round = BracketBuilder.new(tournament, finalists: finalists).build!

    placed = round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    assert_equal finalists.map(&:id).sort, placed.sort,
                 "aucun finaliste perdu ni dupliqué (11 entrants dans un tableau de 16)"
  end

  test "build! : positions uniques dans la ronde" do
    tournament = build_tournament(16, bracket_size: 16)
    round = BracketBuilder.new(tournament, finalists: finalists_in_seed_order(tournament, 16)).build!

    positions = round.tournament_matches.pluck(:position)
    assert_equal positions.uniq.sort, positions.sort
    assert_equal (0..7).to_a, positions.sort
  end

  # ── advance! ────────────────────────────────────────────────────────────────

  test "advance! : ne crée rien tant que le tour en cours n'est pas terminé" do
    tournament = build_tournament(8, bracket_size: 8)
    BracketBuilder.new(tournament, finalists: finalists_in_seed_order(tournament, 8)).build!

    assert_no_difference -> { tournament.tournament_rounds.count } do
      BracketBuilder.new(tournament).advance!
    end
  end

  test "advance! : apparie les vainqueurs du tour précédent" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 8)
    first      = BracketBuilder.new(tournament, finalists: finalists).build!
    play_round!(first)

    second = BracketBuilder.new(tournament).advance!

    assert_equal 2, second.number
    assert_equal 2, second.tournament_matches.count, "4 vainqueurs → 2 demi-finales"
    expected = first.tournament_matches.order(:position).map(&:winner_id)
    placed   = second.tournament_matches.order(:position).flat_map { |m| [m.player_a_id, m.player_b_id] }
    assert_equal expected, placed, "les vainqueurs se retrouvent dans l'ordre des positions"
  end

  test "advance! : un bye qualifie d'office et le tour suivant se génère" do
    tournament = build_tournament(8, bracket_size: 8)
    finalists  = finalists_in_seed_order(tournament, 6)
    first      = BracketBuilder.new(tournament, finalists: finalists).build!
    play_round!(first)

    second = BracketBuilder.new(tournament).advance!

    assert_equal 2, second.tournament_matches.count
    # Les 2 exemptés (seeds 1 et 2) doivent être présents au tour suivant.
    survivors = second.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    exempted  = first.tournament_matches.select(&:is_bye).map(&:player_a_id)
    exempted.each { |id| assert_includes survivors, id, "un exempté doit passer au tour suivant" }
  end

  test "advance! : termine le tournoi quand il ne reste qu'un vainqueur" do
    tournament = build_tournament(4, bracket_size: 4)
    finalists  = finalists_in_seed_order(tournament, 4)
    play_round!(BracketBuilder.new(tournament, finalists: finalists).build!)
    final = BracketBuilder.new(tournament).advance!
    play_round!(final)

    assert_nil BracketBuilder.new(tournament).advance!, "plus de tour à créer après la finale"
    assert tournament.reload.completed?
    assert_equal final.tournament_matches.first.winner, tournament.champion
  end

  test "advance! : appelé deux fois de suite ne crée qu'un seul tour" do
    tournament = build_tournament(8, bracket_size: 8)
    play_round!(BracketBuilder.new(tournament, finalists: finalists_in_seed_order(tournament, 8)).build!)

    BracketBuilder.new(tournament).advance!
    assert_equal 2, tournament.bracket_rounds.count

    # Le 2e tour n'est pas joué → aucun nouveau tour (garde anti double-clic).
    BracketBuilder.new(tournament).advance!
    assert_equal 2, tournament.bracket_rounds.count
  end

  # ── select_finalists (chemin ronde suisse / championnat, sans finalists:) ────

  test "select_finalists : les qualifiés d'abord, complétés par les meilleurs actifs" do
    tournament = build_tournament(8, bracket_size: 4)
    players = tournament.tournament_users.players.order(:draw_order).to_a
    # 2 qualifiés (bilan faible) + 6 actifs (bilan fort) : les qualifiés passent
    # AVANT les actifs même moins bons — un qualifié n'est jamais recalé.
    players[0..1].each { |tu| tu.update!(state: "qualified", wins: 1) }
    players[2..].each_with_index { |tu, i| tu.update!(state: "active", wins: 9 - i) }

    round = BracketBuilder.new(tournament).build!

    entrants = round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    assert_equal 4, entrants.size, "final_size 4 → 4 entrants"
    players[0..1].each { |tu| assert_includes entrants, tu.id, "un qualifié entre toujours" }
    # Les 2 places restantes vont aux meilleurs actifs (wins 9 et 8).
    assert_includes entrants, players[2].id
    assert_includes entrants, players[3].id
  end

  # ── Paramétrage phase / branche (Critérium Fédéral) ─────────────────────────

  test "phase et branche : un tableau secondaire vit à côté du tableau final" do
    tournament = build_tournament(16, bracket_size: 8)
    ok = finalists_in_seed_order(tournament, 8)
    BracketBuilder.new(tournament, finalists: ok).build!

    ko = tournament.tournament_users.players.order(:draw_order).to_a.last(8)
    round = BracketBuilder.new(tournament, finalists: ko, phase: "consolation",
                              persist_seeds: false, owns_completion: false).build!

    assert_equal "consolation", round.phase
    assert_equal "main", round.branch
    assert_equal 4, round.tournament_matches.count
    # Le garde-fou du plan : la consolante ne doit JAMAIS apparaître dans
    # bracket_rounds, sinon #champion renverrait son vainqueur.
    assert_equal 1, tournament.bracket_rounds.count
    assert_equal %w[bracket], tournament.bracket_rounds.map(&:phase)
  end

  test "persist_seeds: false — un tableau secondaire n'écrase pas les têtes de série" do
    tournament = build_tournament(16, bracket_size: 8)
    ok = finalists_in_seed_order(tournament, 8)
    BracketBuilder.new(tournament, finalists: ok).build!
    seeds_before = ok.map { |tu| tu.reload.seed }

    ko = tournament.tournament_users.players.order(:draw_order).to_a.last(8)
    BracketBuilder.new(tournament, finalists: ko, phase: "consolation",
                      persist_seeds: false, owns_completion: false).build!

    assert_equal seeds_before, ok.map { |tu| tu.reload.seed },
                 "seed est une colonne unique : un 2e tableau ne doit pas la réécrire"
    assert ko.all? { |tu| tu.reload.seed.nil? }, "la consolante ne persiste aucun seed"
  end

  test "owns_completion: false — terminer un tableau secondaire ne termine pas le tournoi" do
    tournament = build_tournament(4, bracket_size: 4)
    entrants = finalists_in_seed_order(tournament, 2)
    round = BracketBuilder.new(tournament, finalists: entrants, phase: "classification",
                               branch: "ok:3-4", persist_seeds: false,
                               owns_completion: false).build!
    play_round!(round)

    assert_nil BracketBuilder.new(tournament, phase: "classification", branch: "ok:3-4",
                                  owns_completion: false).advance!
    refute tournament.reload.completed?,
           "le match pour la 3e place ne décide pas de la fin du tournoi"
  end

  test "deux branches concurrentes coexistent au même tour, l'index unique tient" do
    tournament = build_tournament(8)
    players = tournament.tournament_users.players.order(:draw_order).to_a

    # Le match 3e/4e et le mini-tableau 5e-8e se jouent EN PARALLÈLE : même phase,
    # même numéro de tour, branches différentes.
    third = BracketBuilder.new(tournament, finalists: players.first(2), phase: "classification",
                               branch: "ok:3-4", persist_seeds: false, owns_completion: false).build!
    fifth = BracketBuilder.new(tournament, finalists: players.last(4), phase: "classification",
                               branch: "ok:5-8", persist_seeds: false, owns_completion: false).build!

    assert_equal 1, third.number
    assert_equal 1, fifth.number
    assert_equal 2, tournament.tournament_rounds.classification.count

    # En revanche, la MÊME (phase, branche, numéro) reste interdite — c'est cette
    # contrainte qui sert de garde anti-double-clic aux moteurs.
    assert_raises ActiveRecord::RecordNotUnique do
      tournament.tournament_rounds.create!(phase: "classification", branch: "ok:3-4",
                                         number: 1, status: "in_progress")
    end
  end

  test "un joueur retiré entrant dans un tableau produit un forfait, pas un match bloqué" do
    tournament = build_tournament(4, bracket_size: 4)
    entrants = finalists_in_seed_order(tournament, 4)
    entrants.last.update!(state: "withdrawn")

    round = BracketBuilder.new(tournament, finalists: entrants).build!

    forfeited = round.tournament_matches.find { |m| m.player_b_id == entrants.last.id || m.player_a_id == entrants.last.id }
    assert forfeited.forfeit, "le match doit être posé en forfait"
    assert_equal "completed", forfeited.status, "il ne doit pas attendre de score"
    refute_equal entrants.last.id, forfeited.winner_id, "le joueur retiré ne gagne pas"
  end

  test "select_finalists : les éliminés ne sont jamais repêchés" do
    tournament = build_tournament(8, bracket_size: 4)
    players = tournament.tournament_users.players.order(:draw_order).to_a
    players[0..3].each { |tu| tu.update!(state: "qualified", wins: 3) }
    # Bilan excellent mais éliminé (3 défaites en ronde suisse) → hors tableau.
    players[4..].each { |tu| tu.update!(state: "eliminated", wins: 99) }

    round = BracketBuilder.new(tournament).build!

    entrants = round.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    players[4..].each { |tu| refute_includes entrants, tu.id, "un éliminé ne revient jamais" }
  end
end
