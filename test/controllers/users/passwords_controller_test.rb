require "test_helper"

# Tests d'intégration pour Users::PasswordsController.
# Ce controller surcharge Devise::PasswordsController pour :
#   1. Vérifier le captcha hCaptcha avant d'envoyer l'email de reset
#   2. Enregistrer un SecurityLog à chaque demande (même si l'email n'existe pas)
#
# Note : en environnement de test, hcaptcha utilise la clé de test
# "0x0000000000000000000000000000000000000000" qui retourne toujours true.
# La vérification captcha passe donc automatiquement sans stubbing.
class Users::PasswordsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown do
    # SecurityLog doit être supprimé avant teardown_db car il a une FK vers users
    SecurityLog.delete_all
    teardown_db
  end

  # ─── Setup ──────────────────────────────────────────────────────────────────

  setup do
    # Utilisateur existant pour tester la demande de reset avec un email connu
    @user = create_test_user(
      email:      "reset_pass@example.com",
      first_name: "Reset",
      last_name:  "Pass"
    )
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /users/password — action create
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une demande de reset valide crée un SecurityLog.
  # La clé de test hcaptcha passe automatiquement.
  test "POST /users/password crée un SecurityLog" do
    assert_difference "SecurityLog.count", 1 do
      post user_password_path, params: {
        user: { email: @user.email }
      }
    end

    # Vérifie que le log est bien du type password_reset_request
    log = SecurityLog.last
    assert_equal "password_reset_request", log.event_type
  end

  # Cas nominal : l'email est normalisé (downcase + strip) avant d'être loggé.
  test "POST /users/password normalise l'email dans le SecurityLog" do
    post user_password_path, params: {
      user: { email: "  RESET_PASS@EXAMPLE.COM  " }
    }

    log = SecurityLog.last
    assert_not_nil log, "Un SecurityLog doit être créé"
    # Le details du log doit contenir l'email normalisé
    assert_equal "reset_pass@example.com", log.details["email"],
                 "L'email dans les details doit être normalisé en minuscules"
  end

  # Cas nominal : une demande avec un email inexistant crée quand même un SecurityLog.
  # C'est voulu : on log toutes les tentatives pour détecter les attaques d'énumération.
  test "POST /users/password crée un SecurityLog même pour un email inexistant" do
    assert_difference "SecurityLog.count", 1 do
      post user_password_path, params: {
        user: { email: "inexistant@example.com" }
      }
    end

    log = SecurityLog.last
    assert_equal "password_reset_request", log.event_type
    assert_equal "inexistant@example.com", log.details["email"]
  end

  # Cas nominal : après une demande valide, Devise redirige vers la page de connexion.
  # (Comportement standard de Devise::PasswordsController#create)
  test "POST /users/password redirige après la demande" do
    post user_password_path, params: {
      user: { email: @user.email }
    }
    # Devise redirige après l'envoi de l'email de reset
    assert_response :redirect
  end
end
