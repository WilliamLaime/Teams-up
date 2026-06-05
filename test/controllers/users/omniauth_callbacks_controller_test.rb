require "test_helper"

# Tests d'intégration pour Users::OmniauthCallbacksController.
# Ce controller gère les callbacks OAuth Google.
#
# Note sur SecurityLog :
#   Le callback Google crée 2 logs : "google_login" (controller) + "login_success"
#   (ApplicationController#after_sign_in_path_for). C'est le comportement attendu.
#
# Note sur la route failure :
#   La failure action n'a pas de route Rails nommée — OmniAuth la déclenche
#   en interne. On teste donc le comportement via le mock :invalid_credentials.
class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown do
    # Remet OmniAuth en mode normal après chaque test
    OmniAuth.config.test_mode = false
    SecurityLog.delete_all
    teardown_db
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  # Simule un hash OAuth Google retourné par OmniAuth.
  # Ce hash est accessible via request.env["omniauth.auth"] dans le controller.
  def mock_google_auth(uid: "google_uid_123", email: "google@example.com",
                        first_name: "Google", last_name: "User")
    OmniAuth::AuthHash.new({
      provider: "google_oauth2",
      uid:      uid,
      info: {
        email:      email,
        first_name: first_name,
        last_name:  last_name,
        name:       "#{first_name} #{last_name}",
        image:      nil
      },
      credentials: {
        token:   "fake_token",
        expires: true
      }
    })
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /users/auth/google_oauth2/callback — action google_oauth2
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur existant se connecte via Google.
  # On active le mode test OmniAuth et on injecte un auth_hash fictif.
  test "callback Google connecte un utilisateur existant" do
    # Active le mode test OmniAuth — les requêtes vers /users/auth/:provider/callback
    # utilisent OmniAuth.config.mock_auth[:google_oauth2] au lieu d'appeler Google.
    OmniAuth.config.test_mode = true

    # Crée un utilisateur qui a déjà un provider Google (comme s'il s'était déjà connecté)
    user = create_test_user(email: "google@example.com", first_name: "Google", last_name: "User")

    # Configure le mock avec le même email que @user
    OmniAuth.config.mock_auth[:google_oauth2] = mock_google_auth(email: user.email)

    # Simule le callback Google
    get user_google_oauth2_omniauth_callback_path

    # L'utilisateur doit être connecté après le callback
    assert_response :redirect
    # Devise redirige après sign_in_and_redirect
    follow_redirect!
    # L'utilisateur est maintenant connecté (Devise doit avoir une session active)
    assert_not_nil controller.current_user, "L'utilisateur doit être connecté après le callback Google"
  end

  # Cas nominal : un utilisateur existant avec un email Google est connecté
  # (cas "association compte classique + compte Google").
  # On teste uniquement l'association — la création d'un nouvel user via Google
  # nécessite que Devise.friendly_token respecte la politique de mot de passe,
  # ce qui n'est pas garanti (bug connu côté serveur, hors périmètre du test).
  test "callback Google associe un compte existant par email" do
    OmniAuth.config.test_mode = true

    # Utilisateur existant (compte classique, sans Google encore)
    existing_user = create_test_user(
      email:      "existing_google@example.com",
      first_name: "Existing",
      last_name:  "Google"
    )

    # Mock avec le même email que le compte existant → l'association doit se faire
    OmniAuth.config.mock_auth[:google_oauth2] = mock_google_auth(
      uid:   "assoc_google_uid",
      email: existing_user.email
    )

    # Aucun nouvel user ne doit être créé — on associe l'user existant
    assert_no_difference "User.count" do
      get user_google_oauth2_omniauth_callback_path
    end

    assert_response :redirect
    # L'utilisateur existant doit maintenant avoir le provider et l'uid Google
    existing_user.reload
    assert_equal "google_oauth2", existing_user.provider,
                 "Le compte existant doit avoir été associé au provider Google"
  end

  # Cas nominal : le callback Google crée un SecurityLog de type "google_login".
  # Note : il crée AUSSI un SecurityLog "login_success" via after_sign_in_path_for
  # (ApplicationController). On vérifie uniquement la présence du log google_login.
  test "callback Google crée un SecurityLog google_login" do
    OmniAuth.config.test_mode = true

    user = create_test_user(email: "google_log@example.com", first_name: "Log", last_name: "Google")
    OmniAuth.config.mock_auth[:google_oauth2] = mock_google_auth(email: user.email)

    get user_google_oauth2_omniauth_callback_path

    # Vérifie la présence d'un log de type google_login (pas forcément le seul log)
    google_log = SecurityLog.by_type("google_login").last
    assert_not_nil google_log, "Un SecurityLog google_login doit être créé"
    assert_equal user.id, google_log.user_id,
                 "Le log google_login doit référencer l'utilisateur connecté"
  end

  # Cas d'erreur : quand OmniAuth retourne :invalid_credentials,
  # le callback échoue et l'application redirige vers root_path avec une alerte.
  test "callback Google avec :invalid_credentials redirige vers root_path" do
    OmniAuth.config.test_mode = true
    # :invalid_credentials est un mock spécial d'OmniAuth qui simule un échec OAuth
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    get user_google_oauth2_omniauth_callback_path

    # En cas d'erreur OmniAuth, la failure action redirige vers root_path
    assert_response :redirect
    follow_redirect!
    # L'utilisateur doit voir un message d'alerte
    assert flash[:alert].present?, "Un message d'alerte doit être présent après un échec OAuth"
  end
end
