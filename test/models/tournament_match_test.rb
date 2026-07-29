require "test_helper"

class TournamentMatchTest < ActiveSupport::TestCase
  def setup
    # Sport "padel-test-*" → tombe dans le fallback des règles de score
    # (best_of 3, target 6, win_by_two false) : suffisant pour la dérivation.
    @sport = Sport.create!(name: "Padel test", slug: "padel-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @tournament = Tournament.create!(name: "T", sport: @sport, format: "ronde_suisse", status: "in_progress",
                                     max_players: 8, date: Date.tomorrow, place: "Terrain test")
    @round = @tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    @a = tu("a")
    @b = tu("b")
    @c = tu("c")
  end

  def teardown
    teardown_db
  end

  def tu(tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@test.fr")
    @tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  # Crée un match A vs B et lui affecte un score, puis sauvegarde.
  def match_with(sets, player_a: @a, player_b: @b)
    match = @round.tournament_matches.new(player_a: player_a, player_b: player_b, position: rand(1_000_000))
    match.assign_score(sets)
    match.save!
    match
  end

  # ── Validation du vainqueur ────────────────────────────────────────────────
  test "le vainqueur doit être l'un des deux joueurs du match" do
    match = @round.tournament_matches.new(player_a: @a, player_b: @b, position: 0, winner: @c)
    assert_not match.valid?
    assert_includes match.errors[:winner], "doit être l'un des deux joueurs du match"
  end

  # ── Bye ─────────────────────────────────────────────────────────────────────
  test "bye : player_a gagne d'office et le match est clôturé" do
    match = @round.tournament_matches.create!(player_a: @a, is_bye: true, position: 0)
    assert_nil match.player_b_id
    assert_equal @a.id, match.winner_id
    assert_equal "completed", match.status
    assert match.decided?
  end

  # ── Dérivation du vainqueur depuis le score ──────────────────────────────────
  test "score 2-0 : vainqueur dérivé et match complété" do
    match = match_with([[6, 4], [6, 3]])
    assert_equal @a.id, match.winner_id
    assert_equal "completed", match.status
    assert match.decided?
  end

  test "score 2-1 : vainqueur dérivé côté gagnant des sets" do
    match = match_with([[4, 6], [6, 3], [7, 5]])
    assert_equal @a.id, match.winner_id
    assert_equal "2-1", match.sets_summary
  end

  test "score incomplet : match en attente, sans vainqueur" do
    match = match_with([[6, 4]])
    assert_nil match.winner_id
    assert_equal "pending", match.status
    refute match.decided?
  end

  test "sets_summary nil tant qu'aucun score n'est saisi" do
    match = @round.tournament_matches.create!(player_a: @a, player_b: @b, position: 0)
    assert_nil match.sets_summary
    refute match.score_entered?
  end

  test "loser renvoie l'adversaire du vainqueur (nil sur un bye)" do
    match = match_with([[6, 1], [6, 2]])
    assert_equal @b.id, match.loser.id

    bye = @round.tournament_matches.create!(player_a: @c, is_bye: true, position: 99)
    assert_nil bye.loser
  end

  test "assign_score ignore les lignes vides ou incomplètes" do
    match = match_with([[6, 4], ["", ""], [6, 2], [7]])
    assert_equal 2, match.sets.size
    assert_equal @a.id, match.winner_id
  end

  # ── Agrégats set / points ─────────────────────────────────────────────────
  test "sets_won_by et points_won_by comptent le bon côté" do
    match = match_with([[6, 4], [3, 6], [6, 2]])
    assert_equal 2, match.sets_won_by(@a)
    assert_equal 1, match.sets_won_by(@b)
    assert_equal 15, match.points_won_by(@a) # 6+3+6
    assert_equal 12, match.points_won_by(@b) # 4+6+2
    assert_equal 12, match.points_lost_by(@a)
  end

  test "display_score_for/score_summary : mode :sets → nombre de sets remportés (comme sets_won_by)" do
    match = match_with([[6, 4], [3, 6], [6, 2]]) # sport padel-test-* → mode :sets
    assert_equal match.sets_won_by(@a), match.display_score_for(@a)
    assert_equal match.sets_won_by(@b), match.display_score_for(@b)
    assert_equal "2-1", match.score_summary
  end

  test "display_score_for/score_summary : mode :score → le vrai score marqué, pas 0/1" do
    football = Sport.find_or_create_by!(slug: "football") { |s| s.name = "Football"; s.icon = "⚽" }
    @tournament.update!(sport: football)
    # Une seule paire (le score final) : 3 buts à 2, PAS "1 set gagné" (sets_won_by
    # vaudrait 1-0, cf. bug signalé : le score affiché était toujours 1-0/0-0).
    match = match_with([[3, 2]])
    assert_equal 3, match.display_score_for(@a)
    assert_equal 2, match.display_score_for(@b)
    assert_equal "3-2", match.score_summary
    # sets_won_by, lui, ne vaudrait que 0 ou 1 (le "set" gagné) — preuve du bug évité.
    assert_equal 1, match.sets_won_by(@a)
    assert_equal 0, match.sets_won_by(@b)
  end

  # ── Validation des sets / règle des 2 points ──────────────────────────────
  test "un set nul est refusé" do
    match = @round.tournament_matches.new(player_a: @a, player_b: @b, position: 0)
    match.assign_score([[6, 6]])
    refute match.valid?
    assert(match.errors[:sets].any? { |m| m.include?("nul") })
  end

  test "trop de sets est refusé" do
    match = @round.tournament_matches.new(player_a: @a, player_b: @b, position: 0)
    match.assign_score([[6, 0], [6, 0], [6, 0], [6, 0]]) # best_of 3 → 4 sets interdits
    refute match.valid?
    assert(match.errors[:sets].any? { |m| m.include?("trop de sets") })
  end

  test "règle des 2 points d'écart (ping-pong)" do
    pp_sport = Sport.create!(name: "Ping Pong", slug: "ping-pong", icon: "🏓")
    pp_tournament = Tournament.create!(name: "PP", sport: pp_sport, format: "ronde_suisse", status: "in_progress",
                                       max_players: 8, date: Date.tomorrow, place: "Terrain test")
    round = pp_tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    p1 = pp_tournament.tournament_users.create!(user: create_test_user(email: "pp1-#{SecureRandom.hex(3)}@t.fr"),
                                                role: "joueur", status: "approved")
    p2 = pp_tournament.tournament_users.create!(user: create_test_user(email: "pp2-#{SecureRandom.hex(3)}@t.fr"),
                                                role: "joueur", status: "approved")

    build = lambda do |sets|
      m = round.tournament_matches.new(player_a: p1, player_b: p2, position: rand(1_000_000))
      m.assign_score(sets)
      m
    end

    assert build.call([[11, 9]]).valid?,  "11-9 doit être valide"
    refute build.call([[11, 10]]).valid?, "11-10 (1 pt d'écart) doit être refusé"
    assert build.call([[12, 10]]).valid?, "12-10 doit être valide"
  end

  test "ping-pong best_of 5 : il faut 3 sets pour gagner" do
    pp_sport = Sport.create!(name: "Ping Pong", slug: "ping-pong", icon: "🏓")
    pp_tournament = Tournament.create!(name: "PP", sport: pp_sport, format: "ronde_suisse", status: "in_progress",
                                       max_players: 8, date: Date.tomorrow, place: "Terrain test")
    round = pp_tournament.tournament_rounds.create!(phase: "swiss", number: 1, status: "in_progress")
    p1 = pp_tournament.tournament_users.create!(user: create_test_user(email: "q1-#{SecureRandom.hex(3)}@t.fr"),
                                                role: "joueur", status: "approved")
    p2 = pp_tournament.tournament_users.create!(user: create_test_user(email: "q2-#{SecureRandom.hex(3)}@t.fr"),
                                                role: "joueur", status: "approved")

    m = round.tournament_matches.new(player_a: p1, player_b: p2, position: 0)
    m.assign_score([[11, 5], [11, 6]]) # 2-0 insuffisant en best_of 5
    m.save!
    assert_nil m.winner_id
    assert_equal "pending", m.status

    m.assign_score([[11, 5], [11, 6], [11, 7]]) # 3-0 → gagné
    m.save!
    assert_equal p1.id, m.winner_id
    assert_equal "completed", m.status
  end
end
