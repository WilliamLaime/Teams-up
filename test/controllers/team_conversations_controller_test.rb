require "test_helper"

# Tests d'intégration pour TeamConversationsController.
# Ce controller affiche le chat d'une équipe (GET /teams/:id/conversation).
#
# Règles de sécurité :
#   - Visiteur non connecté → redirigé
#   - Membre de l'équipe → 200 OK
#   - Non-membre → 403 Forbidden
#   - Équipe inexistante → rendu inline d'un message d'erreur (pas de crash)
class TeamConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  # ─── Setup ──────────────────────────────────────────────────────────────────

  setup do
    # Capitaine de l'équipe
    @captain = create_test_user(email: "captain_tc@example.com", first_name: "Cap", last_name: "Tain")

    # Autre utilisateur qui sera membre de l'équipe
    @member = create_test_user(email: "member_tc@example.com", first_name: "Mem", last_name: "Ber")

    # Utilisateur qui n'est PAS membre de l'équipe
    @outsider = create_test_user(email: "outsider_tc@example.com", first_name: "Out", last_name: "Side")

    # Équipe créée par le capitaine (Team n'a pas de colonne sport)
    @team = Team.create!(
      name:    "Team Chat Test",
      captain: @captain
    )

    # Note : le capitaine est DÉJÀ ajouté comme membre par le callback after_create
    # de Team#add_captain_as_member — ne pas le recréer (uniqueness violation).
    # On ajoute uniquement @member.
    TeamMember.create!(team: @team, user: @member, role: "member")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /teams/:id/conversation — show
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un membre de l'équipe peut voir le chat → 200 OK.
  test "GET team_conversation retourne 200 pour un membre" do
    sign_in @member
    get team_conversation_path(@team)
    assert_response :success, "Un membre doit voir le chat de l'équipe (200)"
  end

  # Cas nominal : le capitaine peut voir le chat de sa propre équipe → 200 OK.
  test "GET team_conversation retourne 200 pour le capitaine" do
    sign_in @captain
    get team_conversation_path(@team)
    assert_response :success, "Le capitaine doit voir le chat de l'équipe (200)"
  end

  # Cas d'erreur : un utilisateur non membre est redirigé par Pundit.
  # Pundit lève NotAuthorizedError → ApplicationController redirige avec flash alert.
  test "GET team_conversation redirige un non-membre" do
    sign_in @outsider
    get team_conversation_path(@team)
    assert_response :redirect, "Un non-membre doit être redirigé par Pundit"
    assert_equal "Vous n'êtes pas autorisé à effectuer cette action.", flash[:alert]
  end

  # Cas d'erreur : un visiteur non connecté est redirigé.
  test "GET team_conversation redirige un visiteur non connecté" do
    get team_conversation_path(@team)
    assert_response :redirect, "Un visiteur non connecté doit être redirigé"
  end

  # Cas limite : l'équipe n'existe pas → le controller rend un message inline
  # (pas de 404 classique — il rend une turbo-frame avec un message d'erreur).
  test "GET team_conversation avec un ID inexistant rend un message inline" do
    sign_in @member
    get team_conversation_path(id: 999999)
    # Le controller répond 200 avec un rendu inline (pas de raise RecordNotFound)
    assert_response :success, "Un ID inexistant doit rendre un message inline (pas un crash)"
    # Le corps doit contenir le message d'erreur
    # Note : l'apostrophe est échappée par le controller (n\'existe) car la
    # chaîne est construite avec une simple quote. On cherche "existe plus".
    assert_match "existe plus", response.body
  end
end
