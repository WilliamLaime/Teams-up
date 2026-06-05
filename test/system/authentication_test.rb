require_relative "application_system_test_case"

# Tests système pour l'authentification (inscription et connexion)
# Driver : rack_test → pas de JavaScript
#
# NOTE : On utilise le helper sign_in_as (défini dans ApplicationSystemTestCase)
# qui soumet le vrai formulaire POST /users/sign_in. Warden::Test::Helpers#login_as
# ne fonctionne pas avec Capybara rack_test (sessions Rack séparées).
class AuthenticationTest < ApplicationSystemTestCase
  parallelize(workers: 1)

  teardown { teardown_db }

  # ── CAS NOMINAL : ACCÈS À LA LANDING PAGE ────────────────────────────────

  # Un visiteur non connecté peut accéder à la landing page.
  test "un visiteur peut acceder a la landing page" do
    visit root_path

    assert_current_path root_path
    assert_no_text "Erreur"
  end

  # ── CAS NOMINAL : ACCÈS AU FORMULAIRE D'INSCRIPTION ──────────────────────

  # La page d'inscription Devise est accessible aux visiteurs.
  # On ne teste pas la soumission (hCaptcha bloquant + sports requis en prod).
  test "un visiteur peut acceder a la page d inscription" do
    visit new_user_registration_path

    assert_current_path new_user_registration_path
    assert_selector "form"
    assert_selector "input[type='email']", minimum: 1
  end

  # ── CAS NOMINAL : ACCÈS AU FORMULAIRE DE CONNEXION ───────────────────────

  # La page de connexion est accessible aux visiteurs.
  test "un visiteur peut acceder a la page de connexion" do
    visit new_user_session_path

    assert_current_path new_user_session_path
    assert_selector "form"
    assert_selector "input[type='email']",    minimum: 1
    assert_selector "input[type='password']", minimum: 1
  end

  # ── CAS NOMINAL : CONNEXION VIA LE FORMULAIRE ────────────────────────────

  # Un user existant peut se connecter via le formulaire.
  # On crée le user directement en base (confirmé) pour éviter l'email de confirmation.
  test "un user peut se connecter avec ses identifiants" do
    user = create_test_user(
      email:      "login@auth.com",
      password:   "Test1234!",
      first_name: "Login",
      last_name:  "Test"
    )

    sign_in_as(user)

    # Après connexion réussie, Devise redirige — l'user quitte la page sign_in
    assert_no_current_path new_user_session_path
  end

  # ── CAS D'ERREUR : MAUVAIS MOT DE PASSE ──────────────────────────────────

  # La connexion échoue et affiche un message d'erreur si le mdp est incorrect.
  test "la connexion echoue avec un mauvais mot de passe" do
    create_test_user(
      email:      "fail@auth.com",
      password:   "Test1234!",
      first_name: "Fail",
      last_name:  "Test"
    )

    visit new_user_session_path
    fill_in "user[email]",    with: "fail@auth.com"
    fill_in "user[password]", with: "MauvaisMotDePasse99!"
    first("input[type='submit'], button[type='submit']").click

    # En cas d'échec, Devise réaffiche la page de connexion → pas redirigé vers matches
    assert_no_current_path matches_path
  end

  # ── CAS NOMINAL : DÉCONNEXION ─────────────────────────────────────────────

  # Un user connecté peut se déconnecter via DELETE /users/sign_out.
  # En system test rack_test, on utilise page.driver.submit pour les requêtes DELETE.
  test "un user connecte peut se deconnecter" do
    user = create_test_user(
      email:      "logout@auth.com",
      first_name: "Logout",
      last_name:  "Test"
    )

    sign_in_as(user)

    # Vérifie qu'on est bien connecté (redirigé vers une page de l'app)
    assert_no_current_path new_user_session_path

    # Simule DELETE /users/sign_out via le driver rack_test
    page.driver.submit :delete, destroy_user_session_path, {}

    # Après déconnexion, l'user est redirigé vers root (plus accès aux pages protégées)
    assert_no_current_path matches_path
  end
end
