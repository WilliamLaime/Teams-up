# Tests d'intégration pour TournamentMatchesController (Lot 4).
# Saisie du score set-par-set (vainqueur dérivé), droits (organisateur + joueurs),
# verrouillage du tour, génération auto de la ronde suivante.
require "test_helper"

class TournamentMatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin  = create_test_user(email: "admin@example.com")
    @lambda = create_test_user(email: "lambda@example.com")
    @sport  = Sport.create!(name: "Tennis Test", slug: "tennis", icon: "🎾")

    @tournament = Tournament.create!(name: "T", sport: @sport, user: @admin,
                                     format: "ronde_suisse", status: "open", max_players: 8)
    8.times do |i|
      u = create_test_user(email: "j#{i}@example.com")
      @tournament.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    SwissPairing.new(@tournament).next_round! # génère la ronde 1
    @match = @tournament.current_round.tournament_matches.where(is_bye: false).first
  end

  teardown { teardown_db }

  # Score « sec » pour player_a (2 sets à 6-0), conforme au tennis.
  def straight_win = { tournament_match: { games_a: [6, 6], games_b: [0, 0] } }

  test "l'organisateur enregistre un score, le vainqueur est dérivé" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    @match.reload
    assert_equal @match.player_a_id, @match.winner_id
    assert_equal "completed", @match.status
    assert_equal [[6, 0], [6, 0]], @match.sets
  end

  test "un joueur du match peut saisir le score" do
    sign_in @match.player_a.user
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    assert_equal @match.player_a_id, @match.reload.winner_id
  end

  test "réponse Turbo Stream : le board est remplacé (le partial compile)" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win, as: :turbo_stream

    assert_response :success
    assert_match "tournament_board", response.body
  end

  test "un tiers (ni organisateur ni joueur) est refusé" do
    sign_in @lambda
    patch tournament_tournament_match_path(@tournament, @match), params: straight_win

    assert_response :redirect
    assert_nil @match.reload.winner_id
  end

  test "ronde terminée → génération automatique de la ronde suivante" do
    sign_in @admin
    pending = @tournament.current_round.tournament_matches.where(status: "pending", is_bye: false).to_a
    pending[0..-2].each { |m| win_tournament_match!(m, m.player_a) }
    last = pending.last

    assert_difference -> { @tournament.tournament_rounds.count }, 1 do
      patch tournament_tournament_match_path(@tournament, last), params: straight_win
    end
  end

  test "tour verrouillé : re-saisir un match d'une ronde close est refusé et ne double pas les rondes" do
    sign_in @admin
    @tournament.current_round.tournament_matches.where(is_bye: false).find_each { |m| win_tournament_match!(m, m.player_a) }
    SwissPairing.new(@tournament).next_round! # clôt la ronde 1, en crée une 2e
    rounds_before = @tournament.tournament_rounds.count

    patch tournament_tournament_match_path(@tournament, @match.reload), params: straight_win
    assert_response :redirect
    assert_equal rounds_before, @tournament.reload.tournament_rounds.count
  end
end
