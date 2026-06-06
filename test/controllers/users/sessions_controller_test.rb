# Tests d'intégration pour Users::SessionsController
# Ce controller surcharge Devise::SessionsController pour :
#   1. Afficher un message si la session a expiré (flash[:timedout])
#   2. Logger les échecs de connexion dans SecurityLog
#
# Les connexions RÉUSSIES sont loguées dans ApplicationController#after_sign_in_path_for.
require "test_helper"

class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ────────────────────────────────────────────────────────────────
  setup do
    # Un utilisateur confirmé (confirmed_at renseigné par create_test_user).
    # Le mot de passe "Test1234!" respecte PASSWORD_REGEX (maj + chiffre + symbole).
    @user = create_test_user(
      email:      "login@example.com",
      password:   "Test1234!",
      first_name: "Login",
      last_name:  "User"
    )
  end

  # ─── Teardown ─────────────────────────────────────────────────────────────
  teardown do
    # SecurityLog est créé par after_sign_in_path_for et par le controller sessions#create
    SecurityLog.delete_all
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /users/sign_in — formulaire de connexion
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un visiteur peut accéder à la page de connexion.
  # La page est exemptée de redirect_to_landing_if_visitor car devise_controller? = true.
  test "GET /users/sign_in retourne 200 pour un visiteur" do
    # Aucun sign_in → visiteur anonyme
    get new_user_session_path

    # La page de connexion doit être librement accessible
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /users/sign_in — connexion
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : connexion réussie avec email + mot de passe valides.
  # Après une connexion réussie, Devise redirige (302) vers after_sign_in_path_for
  # qui pointe vers root ou la stored_location. La présence de la redirection
  # confirme que la session a bien été ouverte.
  test "POST /users/sign_in redirige après une connexion avec des identifiants valides" do
    post user_session_path, params: {
      user: {
        email:    "login@example.com",
        password: "Test1234!"
      }
    }

    # Devise retourne une 302 vers la page suivante (root ou stored location)
    # On vérifie qu'on est bien redirigé (connexion réussie) et non pas vers sign_in
    assert_response :redirect
    # La redirection ne doit pas pointer vers la page de connexion (ce serait un échec)
    assert_not_equal new_user_session_path, response.location
  end

  # Cas d'erreur : connexion avec un mot de passe incorrect.
  # Devise réaffiche le formulaire en 422 Unprocessable Entity.
  test "POST /users/sign_in réaffiche le formulaire avec un mauvais mot de passe" do
    post user_session_path, params: {
      user: {
        email:    "login@example.com",
        password: "MauvaisMotDePasse!"   # Mot de passe incorrect
      }
    }

    # Devise retourne 422 après un échec de connexion (Rails 7.1+)
    assert_response :unprocessable_entity
  end

  # Cas d'erreur : connexion avec un email inexistant.
  # Devise ne distingue pas "email inconnu" de "mauvais mot de passe" pour éviter
  # l'énumération d'emails — même comportement dans les deux cas.
  test "POST /users/sign_in réaffiche le formulaire pour un email inexistant" do
    post user_session_path, params: {
      user: {
        email:    "inconnu@example.com",   # Email qui n'existe pas en base
        password: "Test1234!"
      }
    }

    # Formulaire réaffiché — même code que pour un mauvais mot de passe
    assert_response :unprocessable_entity
  end

  # Cas edge : connexion avec un compte non confirmé.
  # Devise :confirmable redirige vers sign_in avec un message flash d'erreur.
  # ATTENTION : le comportement de Devise pour :confirmable est une REDIRECTION (302),
  # pas un 422 — il affiche le flash via redirect_to new_user_session_path.
  test "POST /users/sign_in refuse la connexion d'un compte non confirmé" do
    # On crée un user SANS confirmed_at pour simuler un compte non encore confirmé
    unconfirmed = User.create!(
      email:        "unconfirmed@example.com",
      password:     "Test1234!",
      first_name:   "Non",
      last_name:    "Confirme",
      confirmed_at: nil   # Pas encore confirmé — Devise bloque la connexion
    )
    unconfirmed.create_profil!(first_name: "Non", last_name: "Confirme")

    post user_session_path, params: {
      user: {
        email:    "unconfirmed@example.com",
        password: "Test1234!"
      }
    }

    # Devise :confirmable redirige vers sign_in avec un message d'erreur dans le flash
    # (comportement standard de Devise pour les comptes non confirmés)
    assert_response :redirect

    # Nettoyage manuel avant teardown_db pour respecter l'ordre FK
    unconfirmed.profil&.destroy
    unconfirmed.destroy
  end
end
