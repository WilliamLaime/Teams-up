require "test_helper"

# Tests d'intégration pour ProfilsController.
# Ce controller gère le profil de l'utilisateur connecté (show, edit, update)
# et le profil public d'autres utilisateurs (show_user_simple).
# Actions testées :
#   GET  /profil                → show_simple (profil propre, connecté)
#   GET  /users/:id/profil      → show_user_simple (profil public, accessible à tous)
#   GET  /profil/edit           → formulaire d'édition (connecté)
#   PATCH /profil               → mise à jour du profil
#   POST  /profil/dismiss_onboarding → marque la modale d'onboarding comme vue
#   PATCH /profil/update_theme  → bascule le thème clair/sombre, répond JSON
class ProfilsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Nettoyage complet en respectant l'ordre des FK
  teardown { teardown_db }

  setup do
    # Utilisateur connecté — possède son profil
    @user = create_test_user(email: "profil_user@example.com", first_name: "Alice", last_name: "Test")
    # Autre utilisateur pour tester les profils publics
    @other = create_test_user(email: "other_profil@example.com", first_name: "Bob", last_name: "Other")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /profil — show_simple (profil de l'utilisateur connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur connecté peut voir son propre profil (200 OK)
  def test_get_profil_retourne_200_si_connecte
    sign_in @user
    get profil_path
    assert_response :success, "GET /profil doit retourner 200 pour un utilisateur connecté"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé vers la landing (avant authenticate_user!)
  def test_get_profil_redirige_si_non_connecte
    get profil_path
    # redirect_to_landing_if_visitor → root_path d'abord (avant Devise)
    assert_response :redirect, "GET /profil doit rediriger un visiteur non connecté"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /users/:id/profil — show_user_simple (profil public)
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur connecté peut voir le profil public d'un autre
  def test_get_user_profil_retourne_200_si_connecte
    sign_in @user
    get user_profil_path(@other)
    assert_response :success, "GET /users/:id/profil doit retourner 200 pour un utilisateur connecté"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé (landing before_action)
  def test_get_user_profil_redirige_si_non_connecte
    get user_profil_path(@other)
    assert_response :redirect, "GET /users/:id/profil doit rediriger un visiteur non connecté"
  end

  # Non-régression : le bouton « Retour » d'un profil doit revenir à la page
  # précédente, pas à l'accueil. Il passait `url: root_path` (lien codé en dur) ;
  # il passe désormais `fallback:`, donc porte le contrôleur back-link — l'accueil
  # n'étant plus qu'un secours si l'on est arrivé directement sur la page.
  def test_get_user_profil_bouton_retour_revient_en_arriere
    sign_in @user
    get user_profil_path(@other)
    assert_select "a.nav-button--back[data-controller=?]", "back-link"
    assert_select "a.nav-button--back[data-back-link-fallback-value=?]", root_path
  end

  # Non-régression sécurité : le profil public d'un joueur ne doit jamais contenir
  # son email, même pour un capitaine d'équipe (le formulaire « Inviter dans mon
  # équipe » transporte un identifiant signé). Voir docs/SECURITE-RGPD.md.
  def test_get_user_profil_ne_contient_pas_l_email
    Team.create!(name: "Les Inviteurs", captain: @user)
    sign_in @user
    get user_profil_path(@other)
    assert_response :success
    assert_no_match(/#{Regexp.escape(@other.email)}/, response.body,
                    "L'email du joueur consulté ne doit pas apparaître dans le HTML")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /profil/edit — formulaire d'édition
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un utilisateur connecté peut accéder à son formulaire d'édition
  def test_get_profil_edit_retourne_200_si_connecte
    sign_in @user
    get edit_profil_path
    assert_response :success, "GET /profil/edit doit retourner 200 pour un utilisateur connecté"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_get_profil_edit_redirige_si_non_connecte
    get edit_profil_path
    assert_response :redirect, "GET /profil/edit doit rediriger un visiteur non connecté"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /profil — mise à jour du profil
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : une mise à jour valide redirige vers le profil avec un flash notice
  def test_patch_profil_met_a_jour_et_redirige
    sign_in @user
    patch profil_path, params: {
      profil: { description: "Ma nouvelle description" }
    }
    # Après une mise à jour réussie, on est redirigé vers /profil
    assert_redirected_to profil_path, "PATCH /profil doit rediriger vers /profil après succès"
    # Vérifie que la description a bien été modifiée en base
    assert_equal "Ma nouvelle description", @user.profil.reload.description,
                 "La description du profil doit être mise à jour en base"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /profil/dismiss_onboarding — fermer la modale d'onboarding
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : marque onboarding_shown_at et redirige vers root_path
  def test_post_dismiss_onboarding_marque_le_profil_et_redirige
    sign_in @user
    # Le profil ne doit pas encore avoir onboarding_shown_at
    assert_nil @user.profil.onboarding_shown_at, "onboarding_shown_at doit être nil avant dismiss"

    post dismiss_onboarding_profil_path
    # Après dismiss, le profil doit avoir onboarding_shown_at renseigné
    assert_not_nil @user.profil.reload.onboarding_shown_at,
                   "onboarding_shown_at doit être renseigné après dismiss"
    # Redirigé vers root_path car params[:redirect_to] n'est pas fourni
    assert_redirected_to root_path
  end

  # Sécurité : les URLs externes dans redirect_to sont ignorées (open redirect)
  def test_post_dismiss_onboarding_ignore_les_redirections_externes
    sign_in @user
    # Un attaquant pourrait fournir une URL externe → doit être ignorée
    post dismiss_onboarding_profil_path, params: { redirect_to: "https://evil.com" }
    # L'URL externe ne commence pas par "/" → redirigé vers root_path
    assert_redirected_to root_path,
                         "Une URL externe dans redirect_to doit être ignorée (open redirect)"
  end

  # Les chemins locaux (commençant par /) sont acceptés
  def test_post_dismiss_onboarding_accepte_un_chemin_local
    sign_in @user
    post dismiss_onboarding_profil_path, params: { redirect_to: edit_profil_path }
    # edit_profil_path commence par "/" → accepté
    assert_redirected_to edit_profil_path,
                         "Un chemin local valide (commençant par /) doit être utilisé pour la redirection"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /profil/update_theme — basculer le thème
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : répond en JSON avec le nouveau thème
  def test_patch_update_theme_repond_json
    sign_in @user
    # On envoie la requête en format JSON (comme le fait le Stimulus controller)
    patch update_theme_profil_path, as: :json
    # La réponse doit être du JSON avec une clé "theme"
    assert_response :success, "PATCH /profil/update_theme doit retourner 200"
    json = JSON.parse(response.body)
    assert json.key?("theme"), "La réponse JSON doit contenir une clé 'theme'"
    # La valeur doit être "light" ou "dark" selon la méthode theme du profil
    assert_includes ["light", "dark"], json["theme"],
                    "La valeur de 'theme' doit être 'light' ou 'dark'"
  end
end
