require "test_helper"

# Tests d'intégration pour TeamMembersController.
# Gère le retrait de membres d'une équipe :
#   DELETE /teams/:team_id/team_members/:id → retirer un membre (captain seulement)
class TeamMembersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  teardown { teardown_db }

  setup do
    @captain  = create_test_user(email: "tm_captain@example.com", first_name: "Cap", last_name: "Tm")
    @member   = create_test_user(email: "tm_member@example.com",  first_name: "Mem", last_name: "Tm")
    @outsider = create_test_user(email: "tm_out@example.com",     first_name: "Out", last_name: "Tm")

    # Crée l'équipe — le callback ajoute @captain comme TeamMember
    @team        = Team.create!(name: "Les Testeurs TM", captain: @captain)
    # Ajoute @member comme membre ordinaire
    @team_member = @team.team_members.create!(user: @member, role: "member", joined_at: Time.current)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # DELETE /teams/:team_id/team_members/:id — retirer un membre
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut retirer un membre ordinaire de l'équipe
  def test_delete_captain_peut_retirer_un_membre
    sign_in @captain
    assert_difference "TeamMember.count", -1 do
      delete team_team_member_path(@team, @team_member)
    end
    # Le membre retiré ne doit plus exister en base
    assert_nil TeamMember.find_by(id: @team_member.id),
               "Le TeamMember doit avoir été supprimé"
    assert_redirected_to @team
    assert_not_nil flash[:notice]
  end

  # Cas d'erreur : Pundit bloque si un membre ordinaire essaie d'en retirer un autre
  def test_delete_interdit_pour_un_non_captain
    # Crée un deuxième membre que @member va essayer de retirer
    other_member_user = create_test_user(email: "tm_other@example.com", first_name: "Other", last_name: "Tm")
    other_tm = @team.team_members.create!(user: other_member_user, role: "member", joined_at: Time.current)

    sign_in @member
    assert_no_difference "TeamMember.count" do
      delete team_team_member_path(@team, other_tm)
    end
    # Pundit lève NotAuthorizedError → redirection avec alert
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert Pundit doit être présent"
  end

  # Cas d'erreur : Pundit bloque si le captain essaie de se retirer lui-même
  # (un captain ne peut pas se retirer de sa propre équipe — il doit transférer d'abord)
  def test_delete_captain_ne_peut_pas_se_retirer_lui_meme
    # Le TeamMember du captain (créé par le callback)
    captain_tm = TeamMember.find_by(team: @team, user: @captain)
    sign_in @captain
    assert_no_difference "TeamMember.count" do
      delete team_team_member_path(@team, captain_tm)
    end
    # TeamMemberPolicy#destroy? vérifie record.user_id != user.id → false pour le captain
    assert_redirected_to root_path
    assert_not_nil flash[:alert], "Un alert doit être présent si le captain essaie de se retirer"
  end

  # Cas d'erreur : un visiteur non connecté est redirigé
  def test_delete_redirige_si_non_connecte
    assert_no_difference "TeamMember.count" do
      delete team_team_member_path(@team, @team_member)
    end
    assert_response :redirect
  end
end
