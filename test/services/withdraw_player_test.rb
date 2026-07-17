require "test_helper"

# Tests de l'abandon / forfait (Lot 5) : WithdrawPlayer + court-circuit forfait de
# TournamentMatch + auto-forfait des journées futures (build_match!).
class WithdrawPlayerTest < ActiveSupport::TestCase
  def setup
    @sport = Sport.create!(name: "Tennis test", slug: "tennis-test-#{SecureRandom.hex(4)}", icon: "🎾")
    @admin = create_test_user(email: "admin-#{SecureRandom.hex(4)}@test.fr")
  end

  def teardown
    teardown_db
  end

  def build_tournament(count, format:)
    tournament = Tournament.create!(name: "T#{SecureRandom.hex(3)}", sport: @sport, user: @admin,
                                    format: format, status: "open", max_players: count,
                                    date: Date.tomorrow, place: "Terrain test")
    count.times do |i|
      user = create_test_user(email: "p#{i}-#{SecureRandom.hex(3)}@test.fr")
      tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
    end
    tournament
  end

  def resolve_current_round!(tournament)
    tournament.current_round.tournament_matches.where(status: "pending", is_bye: false).find_each do |match|
      win_tournament_match!(match, match.player_a)
    end
  end

  test "un match en forfait est gagné par l'adversaire du joueur retiré" do
    tournament = build_tournament(8, format: "championnat")
    TournamentEngine.for(tournament).next_round!
    match = tournament.current_round.tournament_matches.where(is_bye: false).first
    retired = match.player_a
    opponent = match.player_b

    match.update!(forfeit: true, retired_player_id: retired.id)

    assert match.decided?
    assert_equal opponent.id, match.winner_id
    assert_equal "completed", match.status
  end

  test "déclarer forfait : état withdrawn + match en cours perdu par forfait" do
    tournament = build_tournament(8, format: "championnat")
    TournamentEngine.for(tournament).next_round!
    match = tournament.current_round.tournament_matches.where(is_bye: false).first
    retired = match.player_a
    opponent = match.player_b

    WithdrawPlayer.new(tournament, retired).call!

    assert retired.reload.withdrawn?
    match.reload
    assert match.forfeit?
    assert_equal opponent.id, match.winner_id
  end

  test "championnat : le joueur retiré perd toutes ses journées futures par forfait" do
    tournament = build_tournament(8, format: "championnat")
    TournamentEngine.for(tournament).next_round!
    retired = tournament.current_round.tournament_matches.where(is_bye: false).first.player_a

    WithdrawPlayer.new(tournament, retired).call!

    # Jouer le reste du tournoi jusqu'aux playoffs.
    30.times do
      break if tournament.reload.bracket_started? || tournament.reload.completed?

      resolve_current_round!(tournament)
      TournamentEngine.for(tournament).next_round!
    end

    # Tous les matchs de championnat du joueur retiré sont des forfaits → 0 victoire.
    retired_matches = TournamentMatch.joins(:tournament_round)
                                     .where(tournament_rounds: { tournament_id: tournament.id, phase: "league" })
                                     .where("player_a_id = :id OR player_b_id = :id", id: retired.id)
    assert retired_matches.all?(&:forfeit?), "toutes les rencontres du retiré doivent être des forfaits"
    assert_equal 0, retired.reload.wins
    # Ayant tout perdu, il ne fait pas partie des 4 qualifiés (final_size = 4).
    assert_not retired.reload.qualified?, "un joueur ayant tout perdu ne doit pas être qualifié"
  end

  test "swiss : un joueur withdrawn n'est plus apparié aux rondes suivantes" do
    tournament = build_tournament(8, format: "ronde_suisse")
    TournamentEngine.for(tournament).next_round!
    retired = tournament.current_round.tournament_matches.where(is_bye: false).first.player_a

    WithdrawPlayer.new(tournament, retired).call!
    resolve_current_round!(tournament)
    TournamentEngine.for(tournament).next_round!

    round2 = tournament.swiss_rounds.last
    ids = round2.tournament_matches.flat_map { |m| [m.player_a_id, m.player_b_id] }.compact
    assert_not_includes ids, retired.id, "le joueur retiré ne doit plus être apparié"
  end
end
