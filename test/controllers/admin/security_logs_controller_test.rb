# Tests d'intégration pour Admin::SecurityLogsController
# Ce controller liste les logs de sécurité (connexions, échecs, inscriptions...).
# Il hérite de Admin::BaseController — accès réservé aux admins.
require "test_helper"

class Admin::SecurityLogsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup : création des utilisateurs et données de test ─────────────────
  setup do
    # Admin : flag admin forcé via update_column (bypass callbacks)
    @admin = create_test_user(email: "admin@example.com", first_name: "Admin", last_name: "User")
    @admin.update_column(:admin, true)

    # Utilisateur normal
    @user = create_test_user(email: "user@example.com", first_name: "Normal", last_name: "User")

    # On crée un SecurityLog pour s'assurer que le controller peut le charger
    # SecurityLog.create! nécessite event_type (dans EVENT_TYPES), ip_address, user_agent
    SecurityLog.create!(
      event_type:  "login_success",
      user:        @admin,
      ip_address:  "127.0.0.1",
      user_agent:  "TestAgent/1.0",
      details:     {}
    )
  end

  # ─── Teardown : nettoyage complet ─────────────────────────────────────────
  teardown do
    # SecurityLog doit être supprimé manuellement (pas dans teardown_db par défaut)
    SecurityLog.delete_all
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/security_logs — cas nominal (admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un admin peut accéder à la liste des logs de sécurité
  test "GET /admin/security_logs retourne 200 pour un admin" do
    sign_in @admin

    get admin_security_logs_path

    # La page doit se charger sans erreur
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/security_logs — cas d'erreur (non-admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un utilisateur sans droits admin est redirigé vers root
  test "GET /admin/security_logs redirige vers root pour un non-admin" do
    sign_in @user

    get admin_security_logs_path

    # require_admin! bloque et redirige
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/security_logs — cas edge (visiteur non connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un visiteur non connecté ne peut pas voir les logs
  test "GET /admin/security_logs redirige vers login pour un visiteur" do
    get admin_security_logs_path
    assert_redirected_to new_user_session_path
  end
end
