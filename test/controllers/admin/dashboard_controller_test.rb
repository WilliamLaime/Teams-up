# Tests d'intégration pour Admin::DashboardController
# Ce controller affiche le tableau de bord admin avec tous les KPIs.
# Il hérite de Admin::BaseController qui vérifie que l'utilisateur est admin.
# Seul l'accès (200 / redirect) est testé ici — pas le contenu des KPIs.
require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  # Devise::Test::IntegrationHelpers fournit sign_in pour simuler une session connectée
  include Devise::Test::IntegrationHelpers

  # ─── Setup : création des utilisateurs nécessaires ────────────────────────
  setup do
    # Utilisateur admin : on crée un user classique puis on force le flag admin à true
    # update_column contourne les callbacks et validations — on veut juste le flag
    @admin = create_test_user(email: "admin@example.com", first_name: "Admin", last_name: "User")
    @admin.update_column(:admin, true)

    # Utilisateur normal (non admin)
    @user = create_test_user(email: "user@example.com", first_name: "Normal", last_name: "User")
  end

  # ─── Teardown : nettoyage dans l'ordre FK ─────────────────────────────────
  teardown { teardown_db }

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin — cas nominal (admin connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un admin connecté peut accéder au dashboard et reçoit un 200
  test "GET /admin retourne 200 pour un admin connecté" do
    # On connecte l'admin via Devise
    sign_in @admin

    # La route admin root pointe vers dashboard#show (voir routes.rb)
    get admin_root_path

    # Le dashboard doit être accessible sans erreur
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin — cas d'erreur (user non-admin connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un utilisateur connecté mais NON admin est redirigé vers root
  # La protection vient de Admin::BaseController#require_admin!
  test "GET /admin redirige vers root pour un utilisateur non admin" do
    # On connecte un user ordinaire (admin? = false)
    sign_in @user

    get admin_root_path

    # require_admin! appelle redirect_to root_path si current_user.admin? est faux
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin — cas edge (visiteur non connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un visiteur non connecté est redirigé vers root
  # ApplicationController#redirect_to_landing_if_visitor intercepte AVANT Devise
  test "GET /admin redirige vers login pour un visiteur non connecté" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Traçabilité RGPD — un accès admin doit être journalisé (Admin::BaseController)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un accès admin réussi crée bien un SecurityLog "admin_access"
  # contenant l'admin concerné et la section consultée.
  test "un accès admin crée un log admin_access horodaté avec l'admin et la section" do
    sign_in @admin

    assert_difference -> { SecurityLog.where(event_type: "admin_access").count }, 1 do
      get admin_root_path
    end

    log = SecurityLog.where(event_type: "admin_access").order(created_at: :desc).first
    assert_equal @admin, log.user
    assert_equal "dashboard", log.details["section"]
    assert_equal "show", log.details["action"]
  end

  # Vérifie qu'un accès refusé (non-admin) ne crée AUCUN log admin_access :
  # le before_action require_admin! interrompt la chaîne avant l'after_action.
  test "un accès refusé ne crée pas de log admin_access" do
    sign_in @user

    assert_no_difference -> { SecurityLog.where(event_type: "admin_access").count } do
      get admin_root_path
    end
  end
end
