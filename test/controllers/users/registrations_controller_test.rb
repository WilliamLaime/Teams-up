# Tests d'intégration pour Users::RegistrationsController
# Ce controller surcharge Devise pour créer un Profil et des sports à l'inscription.
#
# IMPORTANT — before_action :verify_captcha_on_signup :
#   hCaptcha utilise la clé secrète "0x0000000000000000000000000000000000000000"
#   en environnement de test, ce qui fait que verify_hcaptcha retourne toujours true.
#   Si ce n'est pas le cas, les tests POST #create afficheront :unprocessable_entity
#   au lieu du comportement attendu.
#
# IMPORTANT — teardown :
#   On ne peut pas utiliser teardown_db seul ici car il ne supprime pas
#   SecurityLog, UserSport, UserAchievement et PushSubscription.
#   On les supprime manuellement avant d'appeler teardown_db.
require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ────────────────────────────────────────────────────────────────
  setup do
    # On crée un sport en base pour pouvoir l'utiliser lors de l'inscription.
    # Le controller exige au moins un sport_id dans sport_ids pour valider.
    @sport = Sport.create!(name: "Football Test", slug: "football-test-reg", icon: "⚽")
  end

  # ─── Teardown ─────────────────────────────────────────────────────────────
  # On supprime dans l'ordre FK pour éviter les PG::ForeignKeyViolation.
  # teardown_db ne couvre pas toutes les tables créées lors de l'inscription
  # (UserSport, SecurityLog, UserAchievement, PushSubscription) — on les ajoute ici.
  teardown do
    # Tables enfants de users non couvertes par teardown_db
    SecurityLog.delete_all
    UserAchievement.delete_all
    PushSubscription.delete_all
    UserSport.delete_all   # Table de jointure users ↔ sports (via has_many :sports)
    # teardown_db couvre : Friendship, Profil, User, Sport... dans le bon ordre FK
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /users/sign_up — formulaire d'inscription
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un visiteur peut accéder à la page d'inscription.
  # La page est exemptée de redirect_to_landing_if_visitor car devise_controller? = true.
  test "GET /users/sign_up retourne 200 pour un visiteur" do
    # Pas de sign_in → visiteur anonyme
    get new_user_registration_path

    # La page d'inscription doit être accessible librement
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /users — création du compte
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : inscription complète et valide.
  # Le controller :
  #   1. Vérifie le captcha (toujours true en test)
  #   2. Valide sport_ids, genre, avatar
  #   3. Crée l'User via super (Devise)
  #   4. Crée le Profil avec first_name/last_name
  #   5. Attache les sports sélectionnés
  # Devise :confirmable → redirige vers email_confirmation_pending_path
  test "POST /users crée le compte et redirige vers la confirmation d'email" do
    user_params = {
      email:                 "nouveau@example.com",
      password:              "Test1234!",       # Respecte PASSWORD_REGEX : maj + chiffre + symbole
      password_confirmation: "Test1234!",
      first_name:            "Alice",
      last_name:             "Nouveau",
      genre:                 "femme",           # Valeur dans User::GENRES
      sport_ids:             [@sport.id.to_s]   # Au moins un sport requis par le controller
    }

    post user_registration_path, params: { user: user_params }

    # Vérifie que l'user a été créé en base
    created_user = User.find_by(email: "nouveau@example.com")
    assert_not_nil created_user, "L'utilisateur doit être créé en base"

    # Vérifie que le Profil a été créé par le controller (pas de callback sur User)
    assert_not_nil created_user.profil, "Le Profil doit être créé avec le compte"
    assert_equal "Alice", created_user.profil.first_name

    # Avec :confirmable actif, l'user n'est pas encore connecté
    # after_inactive_sign_up_path_for redirige vers la page de confirmation
    assert_redirected_to email_confirmation_pending_path
  end

  # Cas d'erreur : mot de passe trop simple.
  # PASSWORD_REGEX exige : au moins 1 majuscule, 1 chiffre, 1 symbole.
  test "POST /users réaffiche le formulaire si le mot de passe est trop simple" do
    user_params = {
      email:                 "faible@example.com",
      password:              "motdepasse",    # Pas de majuscule, chiffre ni symbole → invalide
      password_confirmation: "motdepasse",
      first_name:            "Bob",
      last_name:             "Faible",
      genre:                 "homme",
      sport_ids:             [@sport.id.to_s]
    }

    post user_registration_path, params: { user: user_params }

    # Devise + validation Rails réaffichent le formulaire (422 Unprocessable Entity)
    assert_response :unprocessable_entity

    # L'user ne doit PAS être sauvegardé en base
    assert_nil User.find_by(email: "faible@example.com"), "L'user ne doit pas être créé"
  end

  # Cas d'erreur : email déjà utilisé par un compte existant.
  # Devise valide l'unicité de l'email avant de persister.
  test "POST /users réaffiche le formulaire si l'email est déjà pris" do
    # On crée d'abord un user avec cet email
    create_test_user(email: "pris@example.com", first_name: "Déjà", last_name: "Inscrit")

    user_params = {
      email:                 "pris@example.com",   # Déjà en base → violation d'unicité
      password:              "Test1234!",
      password_confirmation: "Test1234!",
      first_name:            "Doublon",
      last_name:             "User",
      genre:                 "autre",
      sport_ids:             [@sport.id.to_s]
    }

    post user_registration_path, params: { user: user_params }

    # Formulaire réaffiché avec l'erreur d'unicité
    assert_response :unprocessable_entity
  end

  # Cas d'erreur : aucun sport sélectionné.
  # Le controller valide manuellement que sport_ids n'est pas vide.
  test "POST /users réaffiche le formulaire si aucun sport n'est sélectionné" do
    user_params = {
      email:                 "sanssport@example.com",
      password:              "Test1234!",
      password_confirmation: "Test1234!",
      first_name:            "Sans",
      last_name:             "Sport",
      genre:                 "femme",
      sport_ids:             []   # Tableau vide → erreur ajoutée manuellement sur :sports
    }

    post user_registration_path, params: { user: user_params }

    # Le controller appelle render :new, status: :unprocessable_entity
    assert_response :unprocessable_entity

    # L'user ne doit pas être persisté
    assert_nil User.find_by(email: "sanssport@example.com")
  end

  # Cas d'erreur : genre absent ou invalide.
  # Le controller valide manuellement que genre est dans User::GENRES.
  test "POST /users réaffiche le formulaire si le genre est absent" do
    user_params = {
      email:                 "sansgenre@example.com",
      password:              "Test1234!",
      password_confirmation: "Test1234!",
      first_name:            "Sans",
      last_name:             "Genre",
      genre:                 "",    # Vide → erreur ajoutée sur :genre
      sport_ids:             [@sport.id.to_s]
    }

    post user_registration_path, params: { user: user_params }

    assert_response :unprocessable_entity
    assert_nil User.find_by(email: "sansgenre@example.com")
  end
end
