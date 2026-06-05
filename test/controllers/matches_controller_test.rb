# Tests d'intégration pour MatchesController
# On utilise ActionDispatch::IntegrationTest (test HTTP complet, pas de test unitaire controller)
# Devise::Test::IntegrationHelpers fournit sign_in pour simuler un utilisateur connecté
require "test_helper"

class MatchesControllerTest < ActionDispatch::IntegrationTest
  # On inclut les helpers Devise pour pouvoir appeler sign_in dans les tests
  include Devise::Test::IntegrationHelpers

  # ─── Setup : données communes à tous les tests ──────────────────────────────
  # On crée les données directement en base (pas via fixtures) pour contrôler
  # exactement l'état de départ de chaque test.
  setup do
    # Utilisateur propriétaire du match (organisateur).
    # create_test_user crée le User + le Profil en une seule opération.
    # Sans le Profil, certaines vues Rails planteraient sur user.profil.first_name.
    @user = create_test_user(email: "owner@example.com", first_name: "Alice", last_name: "Test")

    # Deuxième utilisateur (joueur lambda, pas organisateur)
    @other_user = create_test_user(email: "other@example.com", first_name: "Bob", last_name: "Test")

    # Sport nécessaire pour créer un match
    @sport = Sport.create!(name: "Football Test", slug: "football-test", icon: "⚽")

    # Match public dans le futur (cas nominal)
    @match = Match.create!(
      title: "Match test",
      date: Date.tomorrow,
      time: Time.current.change(hour: 18, min: 0),
      player_left: 4,
      level: "Débutant",
      visibility: "public",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @user,
      sport: @sport
    )

    # Ajoute @user comme organisateur du match
    @match.match_users.create!(user: @user, role: "organisateur", status: "approved")
  end

  # ─── teardown : nettoyage complet dans l'ordre FK ───────────────────────────
  # On utilise teardown_db (défini dans test_helper.rb) qui supprime toutes les
  # tables dans le bon ordre pour éviter les violations de contrainte FK.
  # C'est nécessaire car les fixtures (users :one, :two) ont des friendships/teams
  # qui référencent les users — PostgreSQL refuse de les supprimer si des FK pointent dessus.
  teardown do
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches — action index
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root_path.
  # ApplicationController#redirect_to_landing_if_visitor redirige TOUS les visiteurs
  # vers la landing page, même pour les actions sans authenticate_user!.
  # skip_before_action :authenticate_user! ne skip pas ce before_action global.
  test "GET /matches redirige vers root pour un visiteur non connecté" do
    get matches_path
    # L'app est en mode pré-lancement → tout visiteur non connecté va vers root
    assert_redirected_to root_path
  end

  # Cas nominal : un utilisateur connecté peut aussi voir la liste des matchs
  test "GET /matches retourne 200 pour un user connecté" do
    sign_in @user
    get matches_path
    assert_response :success
  end

  # Cas ?mine=1 : filtre "mes matchs" — ne montre que les matchs de l'user connecté
  test "GET /matches?mine=1 retourne 200 pour un user connecté" do
    sign_in @user
    get matches_path, params: { mine: "1" }
    assert_response :success
  end

  # Cas ?mine=1&status=completed : matchs terminés de l'user connecté
  test "GET /matches?mine=1&status=completed retourne 200" do
    sign_in @user
    get matches_path, params: { mine: "1", status: "completed" }
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/:id — action show
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root, même pour
  # un match public — la landing guard s'active avant la logique du controller.
  # Un user connecté peut voir le match.
  test "GET /matches/:id retourne 200 pour un match public si connecté" do
    sign_in @user
    get match_path(@match)
    assert_response :success
  end

  # Cas d'erreur : un visiteur non connecté sur un match public est redirigé vers root
  test "GET /matches/:id redirige vers root pour un visiteur non connecté" do
    get match_path(@match)
    assert_redirected_to root_path
  end

  # Cas d'erreur : un user connecté sur un match privé sans token → redirigé vers root
  # La guard MatchesController#show vérifie le token pour les non-organisateurs.
  test "GET /matches/:id redirige vers root pour un match privé sans token (connecté)" do
    # On crée un match privé appartenant à @other_user
    private_match = Match.create!(
      title: "Match privé",
      date: Date.tomorrow,
      time: Time.current.change(hour: 19, min: 0),
      player_left: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @other_user,
      sport: @sport,
      private_token: SecureRandom.hex(8)
    )

    # @user est connecté mais n'est pas l'organisateur et n'a pas le token
    sign_in @user
    get match_path(private_match)
    assert_redirected_to root_path
  ensure
    private_match&.destroy
  end

  # Cas nominal : un user connecté peut accéder à un match privé avec le bon token.
  # ATTENTION : le before_create :generate_private_token écrase toujours private_token,
  # même si on en passe un à la création. Il faut donc lire le token APRÈS creation.
  test "GET /matches/:id retourne 200 pour un match privé avec le bon token (connecté)" do
    private_match = Match.create!(
      title: "Match privé avec token",
      date: Date.tomorrow,
      time: Time.current.change(hour: 20, min: 0),
      player_left: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @other_user,
      sport: @sport
    )
    # Le callback before_create a généré un token aléatoire — on le lit après création
    generated_token = private_match.private_token

    sign_in @user
    # On utilise le token réellement généré
    get match_path(private_match), params: { token: generated_token }
    assert_response :success
  ensure
    private_match&.destroy
  end

  # Cas nominal : l'organisateur peut toujours accéder à son match privé
  test "GET /matches/:id retourne 200 pour l'organisateur d'un match privé" do
    private_match = Match.create!(
      title: "Match privé organisateur",
      date: Date.tomorrow,
      time: Time.current.change(hour: 21, min: 0),
      player_left: 2,
      level: "Débutant",
      visibility: "private",
      validation_mode: "automatic",
      genre_restriction: "tous",
      user: @user,       # @user est l'organisateur
      sport: @sport,
      private_token: "secrettoken"
    )

    sign_in @user
    # L'organisateur accède sans token — il a toujours accès
    get match_path(private_match)
    assert_response :success
  ensure
    private_match&.destroy
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/new — formulaire de création
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root_path.
  # redirect_to_landing_if_visitor s'exécute avant authenticate_user! (Devise),
  # donc on atterrit sur root et non sur la page de login Devise.
  test "GET /matches/new redirige vers root si non connecté" do
    get new_match_path
    assert_redirected_to root_path
  end

  # Cas nominal : un utilisateur connecté peut voir le formulaire
  test "GET /matches/new retourne 200 si connecté" do
    sign_in @user
    get new_match_path
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /matches — création d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root_path.
  # redirect_to_landing_if_visitor s'exécute avant authenticate_user! (Devise).
  test "POST /matches redirige vers root si non connecté" do
    post matches_path, params: {
      match: { title: "Test", date: Date.tomorrow, time: "18:00",
               level: "Débutant", player_left: 4, sport_id: @sport.id,
               visibility: "public", validation_mode: "automatic",
               genre_restriction: "tous" }
    }
    assert_redirected_to root_path
  end

  # Cas nominal : un match valide est créé et on est redirigé vers sa page
  test "POST /matches crée le match et redirige si params valides" do
    sign_in @user
    assert_difference "Match.count", 1 do
      post matches_path, params: {
        match: {
          title: "Nouveau match",
          date: Date.tomorrow,
          time: "18:00",
          level: "Débutant",
          player_left: 4,
          sport_id: @sport.id,
          visibility: "public",
          validation_mode: "automatic",
          genre_restriction: "tous"
        }
      }
    end
    # Après création réussie, on redirige vers la page du match
    assert_redirected_to match_path(Match.last)
  end

  # Cas d'erreur : des params invalides (level manquant) réaffichent le formulaire
  test "POST /matches réaffiche le formulaire (422) si params invalides" do
    sign_in @user
    assert_no_difference "Match.count" do
      post matches_path, params: {
        match: {
          title: "",         # titre vide → invalide
          date: Date.tomorrow,
          time: "18:00",
          level: "",         # level manquant → invalide
          player_left: 0,    # 0 = invalide
          sport_id: @sport.id
        }
      }
    end
    # 422 Unprocessable Entity = formulaire réaffiché avec erreurs
    assert_response :unprocessable_entity
  end

  # Cas sécurité : un homme ne peut pas créer un match "feminin"
  # Le controller force genre_restriction à "tous" pour les non-femmes
  test "POST /matches force genre_restriction à 'tous' pour un non-femme" do
    sign_in @user # @user n'a pas de genre = pas femme
    post matches_path, params: {
      match: {
        title: "Match masculin",
        date: Date.tomorrow,
        time: "18:00",
        level: "Débutant",
        player_left: 4,
        sport_id: @sport.id,
        visibility: "public",
        validation_mode: "automatic",
        genre_restriction: "feminin"  # Valeur qu'on tente d'envoyer frauduleusement
      }
    }
    # Le match a été créé
    assert_redirected_to match_path(Match.last)
    # Mais genre_restriction a été forcé à "tous"
    assert_equal "tous", Match.last.genre_restriction
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /matches/:id/edit — formulaire de modification
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : non connecté → redirigé vers root_path (landing guard).
  # redirect_to_landing_if_visitor s'exécute avant authenticate_user! (Devise).
  test "GET /matches/:id/edit redirige vers root si non connecté" do
    get edit_match_path(@match)
    assert_redirected_to root_path
  end

  # Cas nominal : l'organisateur peut voir le formulaire d'édition
  test "GET /matches/:id/edit retourne 200 pour l'organisateur" do
    sign_in @user
    get edit_match_path(@match)
    assert_response :success
  end

  # Cas d'erreur Pundit : un autre utilisateur est redirigé avec alert
  test "GET /matches/:id/edit redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    get edit_match_path(@match)
    # Pundit lève NotAuthorizedError → ApplicationController redirige avec flash[:alert]
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:id — mise à jour d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut mettre à jour son match
  test "PATCH /matches/:id met à jour et redirige si organisateur et params valides" do
    sign_in @user
    patch match_path(@match), params: {
      match: { title: "Titre mis à jour" }
    }
    assert_redirected_to match_path(@match)
    # Vérifie que le titre a bien été modifié en base
    assert_equal "Titre mis à jour", @match.reload.title
  end

  # Cas d'erreur : params invalides → réaffiche le formulaire
  test "PATCH /matches/:id réaffiche le formulaire (422) si params invalides" do
    sign_in @user
    patch match_path(@match), params: {
      match: { player_left: -5 }  # valeur négative = invalide
    }
    assert_response :unprocessable_entity
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "PATCH /matches/:id redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    patch match_path(@match), params: { match: { title: "Tentative de modification" } }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /matches/:id — suppression d'un match
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut supprimer son match
  test "DELETE /matches/:id détruit le match et redirige si organisateur" do
    sign_in @user
    assert_difference "Match.count", -1 do
      delete match_path(@match)
    end
    assert_redirected_to matches_path
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "DELETE /matches/:id redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    assert_no_difference "Match.count" do
      delete match_path(@match)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /matches/:id/make_public — passer un match privé en public
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'organisateur peut rendre son match public
  test "PATCH /matches/:id/make_public passe le match en public si organisateur" do
    sign_in @user
    # On rend le match privé avant le test
    @match.update!(visibility: "private", private_token: "testtoken")

    patch make_public_match_path(@match)
    assert_redirected_to match_path(@match)
    assert_equal "public", @match.reload.visibility
  end

  # Cas d'erreur Pundit : un non-organisateur est redirigé avec alert
  test "PATCH /matches/:id/make_public redirige avec alert pour un non-organisateur" do
    sign_in @other_user
    @match.update!(visibility: "private", private_token: "testtoken2")

    patch make_public_match_path(@match)
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end
end
