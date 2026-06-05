# Tests d'intégration pour LandingController
# La landing page est publique (skip_before_action :authenticate_user!).
# Routes testées :
#   GET  /           → landing page pour les visiteurs, redirect pour les connectés
#   POST /inscription → enregistre un email dans la waitlist
require "test_helper"

class LandingControllerTest < ActionDispatch::IntegrationTest
  # Helpers Devise pour simuler sign_in
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes ────────────────────────────────────────────────
  setup do
    # Utilisateur connecté pour tester la redirection des connectés
    @user = create_test_user(email: "landing_user@example.com", first_name: "Alice", last_name: "Test")
  end

  # Nettoie toutes les tables dans le bon ordre FK après chaque test
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET / — action index
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un visiteur non connecté voit la landing page → 200 OK
  # La landing est publique (skip_before_action :authenticate_user! et
  # redirect_to_landing_if_visitor exclut le controller "landing")
  test "GET / retourne 200 pour un visiteur non connecté" do
    get root_path
    assert_response :success
  end

  # Cas nominal : un utilisateur connecté est redirigé vers /matches
  # Le controller appelle redirect_to matches_path if user_signed_in?
  test "GET / redirige un utilisateur connecté vers /matches" do
    sign_in @user
    get root_path
    assert_redirected_to matches_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /inscription — action subscribe
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un email valide est enregistré dans la waitlist
  # La table waitlist_entries doit augmenter de 1 et l'utilisateur est redirigé
  test "POST /inscription crée une entrée waitlist avec un email valide" do
    assert_difference "WaitlistEntry.count", 1 do
      post waitlist_subscribe_path, params: { email: "nouveau@example.com" }
    end

    # Le controller redirige vers root_path après l'inscription
    assert_redirected_to root_path

    # Le flash notice confirme l'inscription
    assert_match "premier", flash[:notice]
  end

  # Cas nominal : l'email est normalisé en minuscules avant sauvegarde
  test "POST /inscription normalise l'email en minuscules" do
    post waitlist_subscribe_path, params: { email: "Majuscules@Example.COM" }
    entry = WaitlistEntry.last
    assert_equal "majuscules@example.com", entry.email
  end

  # Cas d'erreur : un email déjà enregistré affiche un message rassurant (pas une erreur brutale)
  # Le controller distingue :taken des autres erreurs pour donner un message positif
  test "POST /inscription avec email déjà enregistré affiche un message rassurant" do
    WaitlistEntry.create!(email: "deja@example.com")

    assert_no_difference "WaitlistEntry.count" do
      post waitlist_subscribe_path, params: { email: "deja@example.com" }
    end

    assert_redirected_to root_path
    # Message rassurant pour un email déjà connu (pas "Email a déjà été pris")
    assert_match "déjà enregistrée", flash[:notice]
  end

  # Cas d'erreur : un email invalide (sans @) affiche un message d'erreur
  test "POST /inscription avec email invalide affiche une alerte" do
    assert_no_difference "WaitlistEntry.count" do
      post waitlist_subscribe_path, params: { email: "pasunemail" }
    end

    assert_redirected_to root_path
    # Flash alert car l'email ne passe pas la validation format
    assert_match "invalide", flash[:alert]
  end

  # Edge case : email vide → même comportement que email invalide
  test "POST /inscription avec email vide affiche une alerte" do
    assert_no_difference "WaitlistEntry.count" do
      post waitlist_subscribe_path, params: { email: "" }
    end

    assert_redirected_to root_path
    assert flash[:alert].present?
  end
end
