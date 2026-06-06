# Tests d'intégration pour Admin::WaitlistEntriesController
# Ce controller liste les emails inscrits en waitlist avant le lancement.
# Il hérite de Admin::BaseController — accès réservé aux admins.
require "test_helper"

class Admin::WaitlistEntriesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ────────────────────────────────────────────────────────────────
  setup do
    # Admin : on force le flag admin à true après création
    @admin = create_test_user(email: "admin@example.com", first_name: "Admin", last_name: "User")
    @admin.update_column(:admin, true)

    # Non-admin
    @user = create_test_user(email: "user@example.com", first_name: "Normal", last_name: "User")

    # On crée une entrée de waitlist pour que le controller ait des données
    # WaitlistEntry valide uniquement l'email (format) — pas de DNS lookup
    WaitlistEntry.create!(email: "visiteur@example.com")
  end

  # ─── Teardown ─────────────────────────────────────────────────────────────
  teardown do
    WaitlistEntry.delete_all
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/waitlist_entries — cas nominal (admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un admin peut consulter la liste des emails de la waitlist
  test "GET /admin/waitlist_entries retourne 200 pour un admin" do
    sign_in @admin

    get admin_waitlist_entries_path

    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/waitlist_entries — cas d'erreur (non-admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un utilisateur sans droits admin est redirigé vers root
  test "GET /admin/waitlist_entries redirige un non-admin" do
    sign_in @user

    get admin_waitlist_entries_path

    # require_admin! bloque et redirige vers root_path avec alerte
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/waitlist_entries — cas edge (visiteur non connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un visiteur anonyme est redirigé vers la landing page
  test "GET /admin/waitlist_entries redirige un visiteur non connecté" do
    get admin_waitlist_entries_path
    assert_redirected_to new_user_session_path
  end
end
