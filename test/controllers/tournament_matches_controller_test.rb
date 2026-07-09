# Tests d'intégration pour TournamentMatchesController (Lot 3).
# Saisie du vainqueur, droits organisateur, génération auto de la ronde suivante, idempotence.
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

  test "l'organisateur enregistre un vainqueur" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match),
          params: { tournament_match: { winner_id: @match.player_a_id } }

    @match.reload
    assert_equal @match.player_a_id, @match.winner_id
    assert_equal "completed", @match.status
  end

  test "réponse Turbo Stream : le board est remplacé (le partial compile)" do
    sign_in @admin
    patch tournament_tournament_match_path(@tournament, @match),
          params: { tournament_match: { winner_id: @match.player_a_id } },
          as: :turbo_stream

    assert_response :success
    assert_match "tournament_board", response.body
  end

  test "un non-organisateur est refusé (redirection, aucun résultat enregistré)" do
    sign_in @lambda
    patch tournament_tournament_match_path(@tournament, @match),
          params: { tournament_match: { winner_id: @match.player_a_id } }

    assert_response :redirect
    assert_nil @match.reload.winner_id
  end

  test "ronde terminée → génération automatique de la ronde suivante" do
    sign_in @admin
    # Résoudre tous les matchs de la ronde 1 sauf le dernier.
    pending = @tournament.current_round.tournament_matches.where(status: "pending").to_a
    pending[0..-2].each { |m| m.update!(winner_id: m.player_a_id, status: "completed") }
    last = pending.last

    assert_difference -> { @tournament.tournament_rounds.count }, 1 do
      patch tournament_tournament_match_path(@tournament, last),
            params: { tournament_match: { winner_id: last.player_a_id } }
    end
  end

  test "idempotence : re-saisir le même vainqueur ne double pas les rondes" do
    sign_in @admin
    @tournament.current_round.tournament_matches.where(status: "pending").find_each do |m|
      m.update!(winner_id: m.player_a_id, status: "completed")
    end
    SwissPairing.new(@tournament).next_round!
    rounds_before = @tournament.tournament_rounds.count

    # Re-saisir un match déjà décidé de la ronde 1.
    patch tournament_tournament_match_path(@tournament, @match),
          params: { tournament_match: { winner_id: @match.player_a_id } }

    assert_equal rounds_before, @tournament.reload.tournament_rounds.count
  end
end
