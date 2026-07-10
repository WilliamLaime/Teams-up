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

  # ─── GET /tournois/bientot : page d'attente publique + non-indexée ──────────
  test "GET /tournois/bientot se rend pour un visiteur non connecté et est noindex" do
    get coming_soon_tournaments_path
    assert_response :success
    assert_select "meta[name=?][content*=?]", "robots", "noindex"
    assert_select ".tournament-soon__title"
  end

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
    assert_equal @user, t.user # créateur = admin
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
    assert(body.any? { |u| u["email"] == @co_org.email })
    refute(body.any? { |u| u["email"] == @user.email }) # s'exclut lui-même
  end

  test "GET /tournois/search retourne vide sous 3 caractères" do
    sign_in @user
    get search_tournaments_path(q: "Bo"), headers: { "Accept" => "application/json" }
    assert_equal [], JSON.parse(response.body)
  end

  # ─── POST /tournois/:id/start : lancement (Lot 3) ───────────────────────────
  def open_tournament_with_players(count)
    t = Tournament.create!(name: "Start Test", sport: @sport, user: @user,
                           format: "ronde_suisse", status: "open", max_players: count)
    count.times do |i|
      u = create_test_user(email: "sp#{i}@example.com")
      t.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    t
  end

  test "POST start lance le tournoi et crée la ronde 1 (organisateur)" do
    sign_in @user
    t = open_tournament_with_players(8)

    post start_tournament_path(t)

    assert_equal "in_progress", t.reload.status
    assert_equal 1, t.swiss_rounds.count
    assert t.swiss_rounds.first.tournament_matches.any?
  end

  test "POST start refuse un non-organisateur" do
    sign_in @co_org # ni admin ni co-org de ce tournoi
    t = open_tournament_with_players(8)

    post start_tournament_path(t)
    assert_response :redirect
    assert_equal "open", t.reload.status
  end

  test "POST start refuse un effectif insuffisant" do
    sign_in @user
    t = open_tournament_with_players(1)

    post start_tournament_path(t)
    assert_equal "open", t.reload.status
    assert_redirected_to tournament_path(t)
  end

  # ─── GET /tournois/:id : rendu du board (le partiel ERB compile) ────────────
  test "GET show rend le panneau de lancement pour un tournoi ouvert" do
    sign_in @user
    t = open_tournament_with_players(8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-start-panel"
  end

  test "GET show rend les rondes suisses pour un tournoi lancé" do
    sign_in @user
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round!

    get tournament_path(t)
    assert_response :success
    assert_select ".swiss-round"
    assert_select ".tmatch-card"
  end

  test "GET show : les boutons vainqueur n'apparaissent que pour l'organisateur" do
    t = open_tournament_with_players(8)
    t.update!(status: "in_progress")
    SwissPairing.new(t).next_round!

    sign_in @co_org # non-organisateur
    get tournament_path(t)
    assert_select ".swiss-round" # les rondes sont bien affichées
    assert_select ".tmatch-card__win-btn", 0 # mais aucun bouton vainqueur
  end

  # ─── Formats Lot 5 : rendu des nouvelles vues (les partials ERB compilent) ────
  def launched_tournament(format, count)
    t = Tournament.create!(name: "Fmt #{format}", sport: @sport, user: @user,
                           format: format, status: "open", max_players: count)
    count.times do |i|
      u = create_test_user(email: "f-#{format}-#{i}@example.com")
      t.tournament_users.create!(user: u, role: "joueur", status: "approved")
    end
    t.update!(status: "in_progress")
    TournamentEngine.for(t).next_round!
    t
  end

  test "GET show rend la phase championnat" do
    sign_in @user
    t = launched_tournament("championnat", 8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-phase__title", text: "Championnat"
    assert_select ".swiss-round"
  end

  test "GET show rend la phase poules (matchs groupés par poule)" do
    sign_in @user
    t = launched_tournament("poules", 8)
    get tournament_path(t)
    assert_response :success
    assert_select ".tournament-phase__title", text: "Poules"
    assert_select ".pool-label"
  end

  test "GET show : bouton forfait visible pour l'organisateur d'un tournoi en cours" do
    sign_in @user
    t = launched_tournament("championnat", 8)
    get tournament_path(t)
    assert_select ".participant-chip__forfeit"
  end
end
