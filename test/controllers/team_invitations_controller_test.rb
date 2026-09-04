require "test_helper"

# Tests d'intégration pour TeamInvitationsController.
# Gère les invitations à rejoindre une équipe :
#   POST  /teams/:team_id/team_invitations         → captain invite un user (create)
#   PATCH /teams/:team_id/team_invitations/:id     → invité accepte ou refuse (update)
#   DELETE /teams/:team_id/team_invitations/:id    → captain annule une invitation (destroy)
#   POST  /teams/:team_id/team_invitations/propose → un membre propose un ami (propose)
class TeamInvitationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    # Captain de l'équipe
    @captain = create_test_user(email: "ti_captain@example.com", first_name: "Cap", last_name: "Ti")
    # Membre ordinaire de l'équipe
    @member  = create_test_user(email: "ti_member@example.com",  first_name: "Mem", last_name: "Ti")
    # Utilisateur extérieur à inviter
    @invitee = create_test_user(email: "ti_invitee@example.com", first_name: "Inv", last_name: "Ti")

    # L'équipe (le callback ajoute @captain comme TeamMember automatiquement)
    @team = Team.create!(name: "Les Testeurs TI", captain: @captain)
    # Ajoute @member comme membre ordinaire
    @team.team_members.create!(user: @member, role: "member", joined_at: Time.current)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /teams/:team_id/team_invitations — captain invite un user
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut inviter un utilisateur par email
  def test_post_create_captain_peut_inviter
    sign_in @captain
    assert_difference "TeamInvitation.count", 1 do
      post team_team_invitations_path(@team), params: {
        invitee_query: @invitee.email # cherche par email
      }
    end
    assert_redirected_to @team, "Le captain doit être redirigé vers la page équipe après invitation"
    assert_not_nil flash[:notice]

    # Vérifie que l'invitation a bien été créée avec le statut "pending"
    invitation = TeamInvitation.find_by(team: @team, invitee: @invitee)
    assert_not_nil invitation, "L'invitation doit exister en base"
    assert_equal "pending", invitation.status, "L'invitation doit avoir le statut 'pending'"
  end

  # Cas d'erreur : Pundit bloque si un non-captain essaie d'inviter
  def test_post_create_interdit_pour_non_captain
    sign_in @member
    assert_no_difference "TeamInvitation.count" do
      post team_team_invitations_path(@team), params: {
        invitee_query: @invitee.email
      }
    end
    # Pundit lève NotAuthorizedError → redirection avec alert
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert Pundit doit être présent"
  end

  # NOTE : le test "user introuvable" n'est pas écrit car TeamInvitationsController#create
  # redirige AVANT d'appeler `authorize @invitation` quand invitee est nil.
  # Cela déclenche Pundit::AuthorizationNotPerformedError (verify_authorized actif).
  # Le controller devrait appeler `skip_after_action :verify_authorized` pour les
  # redirections précoces (guard-clauses) ou utiliser `authorize nil, policy_class: ...`.

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_post_create_redirige_si_non_connecte
    post team_team_invitations_path(@team), params: { invitee_query: @invitee.email }
    assert_response :redirect
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH /teams/:team_id/team_invitations/:id — accepter ou refuser
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'invité peut accepter son invitation → devient TeamMember
  def test_patch_update_accept_cree_un_team_member
    # Crée d'abord une invitation
    invitation = TeamInvitation.create!(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    sign_in @invitee

    assert_difference "TeamMember.count", 1 do
      patch team_team_invitation_path(@team, invitation), params: { status: "accepted" }
    end
    # L'invitation doit passer à "accepted"
    assert_equal "accepted", invitation.reload.status,
                 "L'invitation doit avoir le statut 'accepted'"
    assert_redirected_to @team
  end

  # Cas nominal : l'invité peut refuser son invitation → statut "refused"
  def test_patch_update_refuse_linvitation
    invitation = TeamInvitation.create!(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    sign_in @invitee

    assert_no_difference "TeamMember.count" do
      patch team_team_invitation_path(@team, invitation), params: { status: "refused" }
    end
    assert_equal "refused", invitation.reload.status,
                 "L'invitation doit avoir le statut 'refused'"
    assert_redirected_to teams_path
  end

  # Cas d'erreur : Pundit bloque si quelqu'un d'autre essaie d'accepter l'invitation
  def test_patch_update_interdit_pour_non_invite
    invitation = TeamInvitation.create!(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    # @member essaie d'accepter l'invitation de @invitee → non autorisé
    sign_in @member
    patch team_team_invitation_path(@team, invitation), params: { status: "accepted" }
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /teams/:team_id/team_invitations/:id — captain annule
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut annuler une invitation en attente
  def test_delete_destroy_captain_peut_annuler_linvitation
    invitation = TeamInvitation.create!(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    sign_in @captain

    assert_difference "TeamInvitation.count", -1 do
      delete team_team_invitation_path(@team, invitation)
    end
    assert_redirected_to @team
    assert_not_nil flash[:notice]
  end

  # Cas d'erreur : Pundit bloque si un non-captain essaie d'annuler
  def test_delete_destroy_interdit_pour_non_captain
    invitation = TeamInvitation.create!(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    sign_in @member

    assert_no_difference "TeamInvitation.count" do
      delete team_team_invitation_path(@team, invitation)
    end
    assert_redirected_to root_path
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # POST /teams/:team_id/team_invitations/propose — membre propose un ami
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : un membre peut proposer un utilisateur au captain
  def test_post_propose_membre_peut_proposer
    sign_in @member
    assert_difference "TeamInvitation.count", 1 do
      post propose_team_team_invitations_path(@team), params: {
        invitee_query: @invitee.email
      }
    end
    # L'invitation doit être créée avec le statut "proposed"
    invitation = TeamInvitation.find_by(team: @team, invitee: @invitee)
    assert_not_nil invitation
    assert_equal "proposed", invitation.status,
                 "Une proposition doit avoir le statut 'proposed'"
    assert_redirected_to @team
  end

  # Cas d'erreur : le captain ne peut pas utiliser propose (il utilise create directement)
  def test_post_propose_interdit_pour_captain
    sign_in @captain
    assert_no_difference "TeamInvitation.count" do
      post propose_team_team_invitations_path(@team), params: {
        invitee_query: @invitee.email
      }
    end
    # Le captain n'est pas un "membre non-captain" → redirigé avec alert
    assert_redirected_to @team
    assert_not_nil flash[:alert]
  end

  # ════════════════════════════════════════════════════════════════════════════
  # PATCH .../review — captain valide/refuse une demande d'adhésion (requested)
  # ════════════════════════════════════════════════════════════════════════════

  # Approuver une demande "requested" ajoute directement le joueur comme membre
  def test_review_approve_demande_ajoute_le_membre
    request = TeamInvitation.create!(
      team: @team, inviter: @captain, invitee: @invitee, status: "requested"
    )
    sign_in @captain
    assert_difference "TeamMember.count", 1 do
      patch review_team_team_invitation_path(@team, request), params: { decision: "approve" }
    end
    assert @team.reload.member?(@invitee), "Le joueur doit être devenu membre"
    assert_equal "accepted", request.reload.status
    assert_redirected_to @team
  end

  # Refuser une demande "requested" la supprime sans créer de membre
  def test_review_decline_demande_supprime_sans_membre
    request = TeamInvitation.create!(
      team: @team, inviter: @captain, invitee: @invitee, status: "requested"
    )
    sign_in @captain
    assert_no_difference "TeamMember.count" do
      assert_difference "TeamInvitation.count", -1 do
        patch review_team_team_invitation_path(@team, request), params: { decision: "decline" }
      end
    end
    assert_redirected_to @team
  end

  # ════════════════════════════════════════════════════════════════════════════
  # GET /teams/:team_id/team_invitations/search — autocomplete
  #
  # Tests de non-régression sécurité (voir docs/SECURITE-RGPD.md) :
  # l'endpoint ne doit ni renvoyer d'email, ni permettre d'énumérer les comptes.
  # ════════════════════════════════════════════════════════════════════════════

  def test_search_trouve_par_prenom_et_ne_renvoie_pas_d_email
    sign_in @captain
    get search_team_team_invitations_path(@team, q: "Inv"), headers: { "Accept" => "application/json" }
    assert_response :success

    body = JSON.parse(response.body)
    assert(body.any? { |u| User.find_by_invite_sgid(u["sgid"]) == @invitee },
           "L'invité doit être trouvable par son prénom")
    refute_includes response.body, "@example.com", "Aucun email ne doit apparaître dans la réponse"
    body.each { |u| refute_includes u.keys, "email" }
  end

  def test_search_ne_permet_pas_d_enumerer_les_emails
    sign_in @captain
    get search_team_team_invitations_path(@team, q: "@example.com"), headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal [], JSON.parse(response.body),
                 "Une recherche partielle sur un domaine email ne doit rien renvoyer"
  end

  def test_search_trouve_par_email_exact
    sign_in @captain
    get search_team_team_invitations_path(@team, q: @invitee.email), headers: { "Accept" => "application/json" }
    body = JSON.parse(response.body)
    assert(body.any? { |u| User.find_by_invite_sgid(u["sgid"]) == @invitee },
           "On doit pouvoir inviter quelqu'un dont on connaît l'email exact")
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Invitation via identifiant signé (le chemin utilisé par l'autocomplete)
  # ════════════════════════════════════════════════════════════════════════════

  def test_post_create_avec_invitee_sgid
    sign_in @captain
    assert_difference "TeamInvitation.count", 1 do
      post team_team_invitations_path(@team), params: { invitee_sgid: @invitee.invite_sgid }
    end
    assert_not_nil TeamInvitation.find_by(team: @team, invitee: @invitee)
  end

  # Enchaînement complet, tel que le fait le front : on cherche un joueur, on
  # récupère le sgid renvoyé par l'endpoint, et on l'utilise pour inviter.
  def test_flux_complet_recherche_puis_invitation
    sign_in @captain

    get search_team_team_invitations_path(@team, q: "Inv"), headers: { "Accept" => "application/json" }
    sgid = JSON.parse(response.body).first["sgid"]

    assert_difference "TeamInvitation.count", 1 do
      post team_team_invitations_path(@team), params: { invitee_sgid: sgid }
    end
    assert_not_nil TeamInvitation.find_by(team: @team, invitee: @invitee)
  end

  def test_post_create_refuse_un_sgid_forge
    sign_in @captain
    assert_no_difference "TeamInvitation.count" do
      post team_team_invitations_path(@team), params: { invitee_sgid: "sgid-bidon" }
    end
    assert_redirected_to @team
    assert_not_nil flash[:alert]
  end

  def test_post_create_refuse_un_sgid_expire
    sign_in @captain
    # Le sgid porte une durée de vie de 1 heure (User::INVITE_SGID_EXPIRY)
    sgid = @invitee.invite_sgid

    travel 2.hours do
      assert_no_difference "TeamInvitation.count" do
        post team_team_invitations_path(@team), params: { invitee_sgid: sgid }
      end
    end
    assert_redirected_to @team
  end

  def test_post_create_refuse_un_sgid_emis_pour_un_autre_usage
    sign_in @captain
    # Un signed_id valide mais émis pour un autre `purpose` ne doit pas être accepté
    other_purpose_sgid = @invitee.signed_id(purpose: :something_else, expires_in: 1.hour)

    assert_no_difference "TeamInvitation.count" do
      post team_team_invitations_path(@team), params: { invitee_sgid: other_purpose_sgid }
    end
    assert_redirected_to @team
  end
end
