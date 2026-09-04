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

  # ── Co-organisateur qui rejoint ──────────────────────────────────────────────
  # L'incident prod du 4 septembre 2026 : nommé co-organisateur, l'utilisateur
  # n'avait plus AUCUN moyen de s'inscrire, et l'admin devait le retirer de
  # l'organisation pour l'inscrire — sans pouvoir le renommer ensuite.

  test "POST create : un co-organisateur non joueur prend une place SANS créer de 2e ligne" do
    t = tournament(max_players: 3)
    t.tournament_users.create!(user: @user, role: "co_organisateur", status: "approved")

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      post tournament_tournament_users_path(t)
    end

    entry = t.tournament_users.find_by(user: @user)
    assert_equal "joueur", entry.role, "il occupe désormais une place de joueur"
    assert entry.co_organizer?, "et garde ses droits de gestion"
    assert_equal 1, t.reload.approved_players_count
    assert t.organizer?(@user)
    assert t.player?(@user)
  end

  test "POST create : un co-organisateur ne peut pas rejoindre un tournoi complet" do
    t = tournament(max_players: 1)
    join!(t, "already")
    t.tournament_users.create!(user: @user, role: "co_organisateur", status: "approved")

    sign_in @user
    post tournament_tournament_users_path(t)

    assert_response :redirect
    assert_equal "co_organisateur", t.tournament_users.find_by(user: @user).role
  end

  test "POST create : deuxième inscription d'un joueur déjà inscrit → refus, pas d'erreur 500" do
    t = tournament(max_players: 3)
    t.tournament_users.create!(user: @user, role: "joueur", status: "approved")

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      post tournament_tournament_users_path(t)
    end
    assert_response :redirect
  end

  # Symétrie du cas ci-dessus : quitter ne retire que la place de joueur.
  test "DELETE destroy : un joueur co-organisateur garde ses droits de gestion" do
    t = tournament(max_players: 3)
    entry = t.tournament_users.create!(user: @user, role: "joueur", status: "approved")
    entry.update!(co_organizer: true)

    sign_in @user
    assert_no_difference "t.tournament_users.count" do
      delete tournament_tournament_user_path(t, entry)
    end

    assert_equal "co_organisateur", entry.reload.role
    assert entry.co_organizer?
    assert_equal 0, t.reload.approved_players_count
    assert t.organizer?(@user)
  end

  test "DELETE destroy : un simple joueur voit sa ligne supprimée" do
    t = tournament(max_players: 3)
    entry = t.tournament_users.create!(user: @user, role: "joueur", status: "approved")

    sign_in @user
    assert_difference "t.tournament_users.count", -1 do
      delete tournament_tournament_user_path(t, entry)
    end
  end
end
