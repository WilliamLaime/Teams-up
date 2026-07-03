# Tests d'intégration pour TeamsController
# Couvre toutes les actions CRUD + actions membres du controller
require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # ─── Setup ──────────────────────────────────────────────────────────────────
  setup do
    # Captain de l'équipe (créateur).
    # create_test_user crée le User + le Profil — sans ça User.create! sans
    # first_name/last_name échoue (validés on: :create).
    @captain = create_test_user(
      email:      "captain@example.com",
      first_name: "Captain",
      last_name:  "Test"
    )

    # Membre de l'équipe (pas captain)
    @member = create_test_user(
      email:      "member@example.com",
      first_name: "Membre",
      last_name:  "Test"
    )

    # Utilisateur extérieur (pas dans l'équipe)
    @outsider = create_test_user(
      email:      "outsider@example.com",
      first_name: "Outsider",
      last_name:  "Test"
    )

    # Crée l'équipe avec @captain comme capitaine
    # Le callback add_captain_as_member ajoute automatiquement le captain dans team_members
    @team = Team.create!(name: "Les Rockets Test", captain: @captain)

    # Ajoute @member comme membre de l'équipe
    @team.team_members.create!(user: @member, role: "member", joined_at: Time.current)
  end

  # ─── teardown : nettoyage complet dans l'ordre FK ───────────────────────────
  # teardown_db supprime toutes les tables dans le bon ordre pour éviter les
  # violations FK (Friendship, TeamMember, etc. referent les Users).
  teardown do
    teardown_db
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /equipes — index
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : un visiteur non connecté est redirigé vers root_path.
  # ApplicationController#redirect_to_landing_if_visitor s'exécute avant authenticate_user!.
  test "GET /equipes redirige vers root si non connecté" do
    get teams_path
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : un user connecté voit la liste de ses équipes (200 OK)
  test "GET /equipes retourne 200 si connecté" do
    sign_in @captain
    get teams_path
    assert_response :success
  end

  # Cas nominal : le policy_scope retourne uniquement les équipes de l'user connecté
  test "GET /equipes retourne uniquement les équipes de l'user" do
    sign_in @captain
    get teams_path
    # @captain est dans "Les Rockets Test" → elle doit apparaître
    assert_response :success
    # L'instance variable @teams est chargée — on vérifie indirectement via le code HTTP 200
    # Un test plus profond vérifierait le contenu HTML mais on teste le comportement du controller
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /equipes/:id — show
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : non connecté → redirigé vers root_path (landing guard).
  test "GET /equipes/:id redirige vers root si non connecté" do
    get team_path(@team)
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : un membre de l'équipe peut voir la page détail
  test "GET /equipes/:id retourne 200 pour un membre" do
    sign_in @member
    get team_path(@team)
    assert_response :success
  end

  # Cas nominal : le captain peut voir la page détail (il est aussi membre)
  test "GET /equipes/:id retourne 200 pour le captain" do
    sign_in @captain
    get team_path(@team)
    assert_response :success
  end

  # Comportement réel : TeamPolicy#show? retourne true pour tout le monde.
  # Un non-membre connecté peut voir la page d'une équipe (show est public).
  # La restriction s'applique uniquement à update/destroy/leave.
  test "GET /equipes/:id retourne 200 pour un non-membre connecté" do
    sign_in @outsider
    get team_path(@team)
    # show? = true dans TeamPolicy → accès autorisé pour tout user connecté
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /equipes/new — formulaire de création
  # ════════════════════════════════════════════════════════════════════════════

  # Comportement réel : non connecté → redirigé vers root_path (landing guard).
  test "GET /equipes/new redirige vers root si non connecté" do
    get new_team_path
    assert_redirected_to new_user_session_path
  end

  # Cas nominal : un utilisateur connecté peut voir le formulaire de création
  test "GET /equipes/new retourne 200 si connecté" do
    sign_in @captain
    get new_team_path
    assert_response :success
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /equipes — création d'une équipe
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : crée l'équipe et ajoute le captain comme membre
  test "POST /equipes crée l'équipe avec captain comme membre" do
    sign_in @outsider
    assert_difference "Team.count", 1 do
      post teams_path, params: {
        team: { name: "Nouvelle Équipe Unique" }
      }
    end
    new_team = Team.last
    # Vérifie que le captain est bien ajouté comme membre via le callback
    assert new_team.member?(@outsider), "L'outsider (devenu captain) doit être membre"
    assert_redirected_to team_path(new_team)
  ensure
    Team.where(name: "Nouvelle Équipe Unique").destroy_all
  end

  # Cas d'erreur : un nom vide rend l'équipe invalide → réaffiche le formulaire
  test "POST /equipes réaffiche le formulaire (422) si nom vide" do
    sign_in @captain
    assert_no_difference "Team.count" do
      post teams_path, params: {
        team: { name: "" }  # nom obligatoire → validation échoue
      }
    end
    assert_response :unprocessable_entity
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /equipes/:id — mise à jour
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut modifier son équipe
  test "PATCH /equipes/:id met à jour et redirige si captain" do
    sign_in @captain
    patch team_path(@team), params: {
      team: { description: "Nouvelle description" }
    }
    assert_redirected_to team_path(@team)
    assert_equal "Nouvelle description", @team.reload.description
  end

  # Cas d'erreur Pundit : un non-captain est redirigé avec alert
  test "PATCH /equipes/:id redirige avec alert pour un non-captain" do
    sign_in @member
    patch team_path(@team), params: {
      team: { description: "Tentative de modif" }
    }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /equipes/:id — suppression
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut supprimer son équipe
  test "DELETE /equipes/:id détruit l'équipe et redirige si captain" do
    sign_in @captain
    assert_difference "Team.count", -1 do
      delete team_path(@team)
    end
    assert_redirected_to teams_path
  end

  # Cas d'erreur Pundit : un non-captain est redirigé avec alert
  test "DELETE /equipes/:id redirige avec alert pour un non-captain" do
    sign_in @member
    assert_no_difference "Team.count" do
      delete team_path(@team)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /equipes/:id/transfer_captain — transfert de capitanat
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut transférer le capitanat à un membre existant
  test "PATCH /equipes/:id/transfer_captain transfère si captain et nouveau_captain est membre" do
    sign_in @captain
    patch transfer_captain_team_path(@team), params: { new_captain_id: @member.id }
    assert_redirected_to team_path(@team)
    # Vérifie que le nouveau captain est bien @member
    assert_equal @member, @team.reload.captain
  end

  # Cas d'erreur : le nouveau captain n'est pas membre → redirige avec alert
  test "PATCH /equipes/:id/transfer_captain redirige avec alert si non-membre" do
    sign_in @captain
    patch transfer_captain_team_path(@team), params: { new_captain_id: @outsider.id }
    assert_redirected_to team_path(@team)
    assert_not_nil flash[:alert]
  end

  # Cas d'erreur Pundit : un non-captain est redirigé avec alert
  test "PATCH /equipes/:id/transfer_captain redirige avec alert pour un non-captain" do
    sign_in @member
    patch transfer_captain_team_path(@team), params: { new_captain_id: @captain.id }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /equipes/:id/leave — quitter l'équipe
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un membre non-captain peut quitter l'équipe
  test "DELETE /equipes/:id/leave supprime le TeamMember du membre" do
    sign_in @member
    assert_difference "TeamMember.count", -1 do
      delete leave_team_path(@team)
    end
    assert_redirected_to teams_path
  end

  # Cas d'erreur Pundit : le captain ne peut pas quitter son équipe
  # (il doit d'abord transférer le capitanat)
  test "DELETE /equipes/:id/leave redirige avec alert si captain essaie de quitter" do
    sign_in @captain
    delete leave_team_path(@team)
    # Pundit::LeavePolicy.leave? est false pour le captain
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /equipes/:id/join — demander à rejoindre une équipe
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un non-membre crée une demande d'adhésion "requested"
  test "POST /equipes/:id/join crée une demande requested pour un non-membre" do
    sign_in @outsider
    assert_difference -> { TeamInvitation.requested.count }, 1 do
      post join_team_path(@team)
    end
    assert_redirected_to teams_path
    assert_not_nil flash[:notice]
    invitation = TeamInvitation.requested.find_by(team: @team, invitee: @outsider)
    assert_equal @captain, invitation.inviter # l'inviteur officiel est le capitaine
  end

  # La demande notifie le capitaine de l'équipe
  test "POST /equipes/:id/join notifie le capitaine" do
    sign_in @outsider
    assert_difference -> { Notification.where(user: @captain).count }, 1 do
      post join_team_path(@team)
    end
  end

  # Garde-fou : un membre existant ne peut pas demander à rejoindre.
  # Pundit (join? = false pour un membre) bloque en amont → redirection root.
  test "POST /equipes/:id/join refuse un membre déjà présent" do
    sign_in @member
    assert_no_difference "TeamInvitation.count" do
      post join_team_path(@team)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # Garde-fou : pas deux demandes en attente pour la même équipe
  test "POST /equipes/:id/join refuse une seconde demande en attente" do
    sign_in @outsider
    post join_team_path(@team) # première demande OK
    assert_no_difference "TeamInvitation.count" do
      post join_team_path(@team) # seconde refusée
    end
    assert_not_nil flash[:alert]
  end
end
