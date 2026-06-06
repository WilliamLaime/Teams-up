# Tests d'intégration pour Admin::ImageModerationsController
# Ce controller affiche le tableau de bord de modération d'images IA.
# Il hérite de Admin::BaseController — accès réservé aux admins.
require "test_helper"

class Admin::ImageModerationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ────────────────────────────────────────────────────────────────
  setup do
    # Admin
    @admin = create_test_user(email: "admin@example.com", first_name: "Admin", last_name: "User")
    @admin.update_column(:admin, true)

    # Non-admin
    @user = create_test_user(email: "user@example.com", first_name: "Normal", last_name: "User")

    # On crée une ImageModeration pour que le controller ait des données à afficher.
    # L'association polymorphique pointe vers le Profil de @admin (moderatable).
    # On utilise insert! pour contourner les contraintes éventuelles de l'objet en test.
    ImageModeration.insert!({
      moderatable_type: "Profil",
      moderatable_id:   @admin.profil.id,
      attachment_name:  "avatar",
      status:           "pending",
      provider:         "sightengine",
      created_at:       Time.current,
      updated_at:       Time.current
    })
  end

  # ─── Teardown ─────────────────────────────────────────────────────────────
  teardown do
    ImageModeration.delete_all
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/image_moderations — cas nominal (admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un admin peut accéder à la page de modération d'images
  test "GET /admin/image_moderations retourne 200 pour un admin" do
    sign_in @admin

    get admin_image_moderations_path

    # La page doit se charger avec succès (tous les KPIs et le tableau)
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/image_moderations — cas d'erreur (non-admin)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un utilisateur non-admin est redirigé
  test "GET /admin/image_moderations redirige un non-admin" do
    sign_in @user

    get admin_image_moderations_path

    # require_admin! dans BaseController bloque et redirige vers root
    assert_redirected_to root_path
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /admin/image_moderations — cas edge (visiteur non connecté)
  # ════════════════════════════════════════════════════════════════════════════

  # Vérifie qu'un visiteur anonyme est redirigé vers la landing
  test "GET /admin/image_moderations redirige un visiteur non connecté" do
    get admin_image_moderations_path
    assert_redirected_to new_user_session_path
  end
end
