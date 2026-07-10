require "test_helper"

# Tests du moteur « Championnat » (Lot 5) : round-robin intégral (méthode du cercle)
# puis playoffs. On vérifie l'algorithme pur (.schedule) et le flux persisté
# journée par journée jusqu'au tableau final.
class LeagueBuilderTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Tennis test", slug: "tennis-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  def build_tournament(count)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: "championnat", status: "open", max_players: count)
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  def resolve_current_round!(tournament)
    round = tournament.current_round
    round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
      win_tournament_match!(match, match.player_a)
    end
    round
  end

  def play_to_completion!(tournament)
    100.times do
      break if tournament.reload.completed?

      resolve_current_round!(tournament)
      TournamentEngine.for(tournament).next_round!
    end
  end

  # ── Algorithme pur ────────────────────────────────────────────────────────────
  test ".schedule : N pairs, N-1 journées, chaque paire une seule fois (effectif pair)" do
    players = (1..6).to_a
    schedule = LeagueBuilder.schedule(players)

    assert_equal 5, schedule.size, "6 joueurs → 5 journées"
    schedule.each { |journee| assert_equal 3, journee.size, "3 matchs par journée" }

    seen = []
    schedule.each { |journee| journee.each { |a, b| seen << [a, b].minmax } }
    assert_equal players.combination(2).map(&:minmax).sort, seen.sort,
                 "chaque paire de joueurs s'affronte exactement une fois"
  end

  test ".schedule : effectif impair → un bye (nil) par journée" do
    schedule = LeagueBuilder.schedule((1..5).to_a)

    assert_equal 5, schedule.size, "5 joueurs (padding à 6) → 5 journées"
    schedule.each do |journee|
      byes = journee.count { |a, b| a.nil? || b.nil? }
      assert_equal 1, byes, "une journée doit contenir exactement un bye"
    end
  end

  # ── Persistance journée par journée ───────────────────────────────────────────
  test "lancement : crée la journée 1 (phase league)" do
    tournament = build_tournament(4)
    TournamentEngine.for(tournament).next_round!

    round = tournament.league_rounds.first
    assert_equal 1, round.number
    assert_equal "league", round.phase
    assert_equal 2, round.tournament_matches.count
  end

  test "idempotence : régénérer sans terminer la journée ne crée rien" do
    tournament = build_tournament(4)
    TournamentEngine.for(tournament).next_round!
    assert_equal 1, tournament.league_rounds.count

    TournamentEngine.for(tournament).next_round!
    assert_equal 1, tournament.league_rounds.count
  end

  test "la journée suivante n'est générée qu'une fois la courante terminée" do
    tournament = build_tournament(4)
    TournamentEngine.for(tournament).next_round!
    resolve_current_round!(tournament)
    TournamentEngine.for(tournament).next_round!

    assert_equal 2, tournament.league_rounds.count
  end

  test "flux complet 8 joueurs → 7 journées → Final 4 → un vainqueur, completed" do
    tournament = build_tournament(8)
    TournamentEngine.for(tournament).next_round!
    play_to_completion!(tournament)

    assert tournament.reload.completed?, "le tournoi doit être terminé"
    assert_equal 7, tournament.league_rounds.count, "8 joueurs → 7 journées de championnat"
    assert tournament.bracket_started?, "les playoffs doivent avoir eu lieu"
    # final_size 4 (≤ 8 joueurs) → exactement 4 finalistes marqués qualified.
    assert_equal 4, tournament.tournament_users.qualified.count
    final = tournament.bracket_rounds.last
    assert_equal 1, final.tournament_matches.count, "la finale = un seul match"
  end
end
