# Tests d'intégration pour TournamentsController (Lot 2 : création)
# Vérifie le rendu du formulaire et le flux de création (admin, co-organisateur,
# auto-inscription optionnelle du créateur).
require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user       = create_test_user(email: "owner@example.com", first_name: "Alice", last_name: "Test")
    @co_org     = create_test_user(email: "coorg@example.com", first_name: "Bob",   last_name: "Test")
    @sport      = Sport.create!(name: "Padel Test", slug: "padel", icon: "🎾")
  end

  teardown { teardown_db }

  # ─── GET /tournois/new : le formulaire se rend (ERB compile) ────────────────
  test "GET /tournois/new retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get new_tournament_path
    assert_response :success
    assert_select "form"
    assert_select ".match-form-section", 4 # 4 sections numérotées
  end

  test "GET /tournois/new redirige un visiteur non connecté" do
    get new_tournament_path
    assert_response :redirect
  end

  # ─── POST /tournois : création nominale ─────────────────────────────────────
  test "POST /tournois crée un tournoi dont le créateur est l'admin non inscrit" do
    sign_in @user

    assert_difference "Tournament.count", 1 do
      post tournaments_path, params: {
        tournament: {
          name: "Open Test", sport_id: @sport.id, format: "ronde_suisse",
          max_players: 16, date: Date.tomorrow.to_s, place: "Club Test"
        }
      }
    end

    t = Tournament.last
    assert_equal @user, t.user            # créateur = admin
    assert_equal "open", t.status
    assert_equal 0, t.approved_players_count # pas inscrit comme joueur par défaut
    assert_redirected_to tournament_path(t)
  end

  # ─── Co-organisateur + auto-inscription ─────────────────────────────────────
  test "POST /tournois avec co-organisateur et auto-inscription" do
    sign_in @user

    post tournaments_path, params: {
      tournament: {
        name: "Open Test 2", sport_id: @sport.id, format: "poules",
        max_players: 8, date: Date.tomorrow.to_s, place: "Club Test"
      },
      co_organizer_email: @co_org.email,
      self_register: "1"
    }

    t = Tournament.last
    # Le créateur s'est auto-inscrit comme joueur → 1 place occupée
    assert_equal 1, t.approved_players_count
    # Le co-org existe mais n'occupe PAS de place de joueur
    assert t.tournament_users.exists?(user: @co_org, role: "co_organisateur")
    assert_equal 1, t.tournament_users.where(role: "joueur").count
    assert t.organizer?(@co_org)
  end

  # ─── GET /tournois/search : autocomplete co-organisateur ────────────────────
  test "GET /tournois/search renvoie du JSON filtré" do
    sign_in @user
    get search_tournaments_path(q: "Bob"), headers: { "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.any? { |u| u["email"] == @co_org.email }
    refute body.any? { |u| u["email"] == @user.email } # s'exclut lui-même
  end

  test "GET /tournois/search retourne vide sous 3 caractères" do
    sign_in @user
    get search_tournaments_path(q: "Bo"), headers: { "Accept" => "application/json" }
    assert_equal [], JSON.parse(response.body)
  end
end
