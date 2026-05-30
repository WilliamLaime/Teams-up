# Tests d'intégration pour PagesController
# Ce controller gère les pages statiques et semi-statiques de l'application.
# Certaines actions sont publiques (about, contact, partenariat, etc.),
# d'autres requièrent une connexion (home).
# Pas de Pundit (skip_after_action :verify_authorized).
require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur connecté (pour tester les pages nécessitant une connexion)
    @user = create_test_user(email: "pages_user@example.com", first_name: "Alice", last_name: "Test")
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # Pages publiques (skip_before_action :authenticate_user!)
  # Ces pages sont accessibles sans être connecté.
  # Mais redirect_to_landing_if_visitor est toujours actif SAUF pour les
  # controllers dans %w[landing pwa errors] et les paths starting with /sitemap.
  # PagesController n'est PAS dans cette liste donc les visiteurs non connectés
  # sont redirigés vers root_path pour les pages "pages".
  # SAUF pour les actions dans skip_before_action only: [...]
  # Note : redirect_to_landing_if_visitor est toujours actif, il redirige AUSSI
  # les visiteurs vers root même si authenticate_user! est skippé.
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : /quisommesnous est accessible pour un utilisateur connecté → 200
  test "GET /quisommesnous retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get about_path
    assert_response :success
  end

  # Cas nominal : /contact est accessible pour un utilisateur connecté → 200
  test "GET /contact retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get contact_path
    assert_response :success
  end

  # Cas nominal : /partenariat est accessible pour un utilisateur connecté → 200
  test "GET /partenariat retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get partenariat_path
    assert_response :success
  end

  # Cas nominal : /confidentialite est accessible pour un utilisateur connecté → 200
  test "GET /confidentialite retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get confidentialite_path
    assert_response :success
  end

  # Cas nominal : /conditions est accessible pour un utilisateur connecté → 200
  test "GET /conditions retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get conditions_path
    assert_response :success
  end

  # Cas nominal : /sitemap est accessible pour un utilisateur connecté → 200
  test "GET /sitemap retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get sitemap_path
    assert_response :success
  end

  # Edge case pour /sitemap : accessible à un visiteur non connecté car
  # redirect_to_landing_if_visitor a une exception pour les paths démarrant par /sitemap
  test "GET /sitemap retourne 200 pour un visiteur non connecté (exception sitemap)" do
    # Pas de sign_in → visiteur non connecté
    get sitemap_path
    # L'exception dans redirect_to_landing_if_visitor laisse passer /sitemap
    assert_response :success
  end

  # Cas d'erreur : les pages publiques redirigent quand même les visiteurs non connectés
  # car redirect_to_landing_if_visitor ne fait exception que pour landing, pwa, errors, sitemap
  test "GET /quisommesnous redirige vers root pour un visiteur non connecté" do
    get about_path
    assert_redirected_to root_path
  end

  test "GET /contact redirige vers root pour un visiteur non connecté" do
    get contact_path
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /accueil — action home
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : /accueil est accessible pour un utilisateur connecté → 200
  test "GET /accueil retourne 200 pour un utilisateur connecté" do
    sign_in @user
    get home_path
    assert_response :success
  end

  # Cas d'erreur : /accueil redirige un visiteur non connecté vers root_path
  # (redirect_to_landing_if_visitor intercepte avant authenticate_user!)
  test "GET /accueil redirige vers root pour un visiteur non connecté" do
    get home_path
    assert_redirected_to root_path
  end
end
