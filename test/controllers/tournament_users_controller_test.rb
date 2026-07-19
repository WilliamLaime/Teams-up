# Tests d'intégration pour TournamentUsersController (rejoindre / quitter un tournoi).
require "test_helper"

class TournamentUsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user  = create_test_user(email: "joiner@example.com")
    @sport = Sport.create!(name: "Padel test", slug: "padel-test-#{SecureRandom.hex(4)}", icon: "🎾")
  end

  teardown { teardown_db }

  def tournament(status: "open", max_players: 2)
    Tournament.create!(name: "T", sport: @sport, format: "ronde_suisse", status: status,
                       max_players: max_players, date: Date.tomorrow, place: "Terrain test")
  end

  def join!(tournament, tag)
    user = create_test_user(email: "#{tag}-#{SecureRandom.hex(3)}@test.fr")
    tournament.tournament_users.create!(user: user, role: "joueur", status: "approved")
  end

  test "POST create inscrit un utilisateur à un tournoi ouvert et non complet" do
    sign_in @user
    t = tournament(max_players: 3)

    assert_difference "t.tournament_users.count", 1 do
      post tournament_tournament_users_path(t)
    end
    assert t.tournament_users.exists?(user: @user, role: "joueur")
  end

  test "POST create autorise la dernière place disponible (non-régression off-by-one)" do
    sign_in @user
    t = tournament(max_players: 2)
    join!(t, "first")

    assert_difference "t.tournament_users.count", 1 do
      post tournament_tournament_users_path(t)
    end
    assert_response :redirect
    assert t.tournament_users.exists?(user: @user, role: "joueur")
    assert_equal "closed", t.reload.status # se clôture tout seul, désormais complet
  end

  test "POST create refuse un tournoi complet" do
    t = tournament(max_players: 1)
    join!(t, "already")

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      post tournament_tournament_users_path(t)
    end
    assert_response :redirect
  end

  test "POST create refuse un tournoi aux inscriptions closes" do
    t = tournament(status: "closed", max_players: 8)

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      post tournament_tournament_users_path(t)
    end
  end

  test "POST create refuse un tournoi déjà lancé" do
    t = tournament(status: "in_progress", max_players: 8)

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      post tournament_tournament_users_path(t)
    end
  end
end
