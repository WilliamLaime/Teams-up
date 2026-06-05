require "test_helper"

# Tests de TeamMemberPolicy.
# Règles :
#   destroy? → seul le captain peut retirer un membre, ET pas lui-même
#
# On instancie directement la policy :
#   TeamMemberPolicy.new(user, team_member).destroy?
class TeamMemberPolicyTest < ActiveSupport::TestCase
  teardown { teardown_db }

  setup do
    @captain  = create_test_user(email: "tmp_captain@example.com", first_name: "Cap", last_name: "Tmp")
    @member   = create_test_user(email: "tmp_member@example.com",  first_name: "Mem", last_name: "Tmp")
    @outsider = create_test_user(email: "tmp_out@example.com",     first_name: "Out", last_name: "Tmp")

    # Crée l'équipe — le callback ajoute @captain comme TeamMember
    @team = Team.create!(name: "Les Politique TMP", captain: @captain)

    # TeamMember du captain (créé par le callback)
    @captain_tm = TeamMember.find_by(team: @team, user: @captain)

    # Ajoute @member comme membre ordinaire
    @member_tm = @team.team_members.create!(user: @member, role: "member", joined_at: Time.current)
  end

  # ════════════════════════════════════════════════════════════════════════════
  # destroy? — seul le captain peut retirer, et pas lui-même
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut retirer un membre ordinaire
  def test_destroy_autorise_pour_le_captain_retirant_un_membre
    assert TeamMemberPolicy.new(@captain, @member_tm).destroy?,
           "Le captain doit pouvoir retirer un membre ordinaire de l'équipe"
  end

  # Cas d'erreur : le captain ne peut pas se retirer lui-même
  # (la policy vérifie record.user_id != user.id)
  def test_destroy_interdit_pour_le_captain_se_retirant_lui_meme
    refute TeamMemberPolicy.new(@captain, @captain_tm).destroy?,
           "Le captain ne doit pas pouvoir se retirer lui-même (utiliser transfer_captain d'abord)"
  end

  # Cas d'erreur : un membre ordinaire ne peut pas retirer un autre membre
  def test_destroy_interdit_pour_un_membre_ordinaire
    refute TeamMemberPolicy.new(@member, @member_tm).destroy?,
           "Un membre ordinaire ne doit pas pouvoir retirer un autre membre"
  end

  # Cas d'erreur : un utilisateur extérieur à l'équipe ne peut pas retirer un membre
  def test_destroy_interdit_pour_un_outsider
    refute TeamMemberPolicy.new(@outsider, @member_tm).destroy?,
           "Un utilisateur extérieur à l'équipe ne doit pas pouvoir retirer un membre"
  end

  # Edge case : un user nil n'est pas géré par TeamMemberPolicy#destroy?
  # La policy accède directement à user.id sans nil-check → NoMethodError pour nil.
  # Ce comportement est normal car Pundit et Devise garantissent que current_user
  # est toujours présent (authenticate_user! redirige les visiteurs non connectés).
  # On vérifie juste que la policy lève bien une erreur pour un user nil.
  def test_destroy_leve_erreur_pour_user_nil
    assert_raises(NoMethodError) do
      TeamMemberPolicy.new(nil, @member_tm).destroy?
    end
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Scope#resolve — filtre les membres visibles par le captain
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le scope retourne les membres des équipes dont l'user est captain
  def test_scope_retourne_les_membres_des_equipes_du_captain
    resolved = TeamMemberPolicy::Scope.new(@captain, TeamMember.all).resolve
    # Le captain est captain de @team → @member_tm doit apparaître
    assert_includes resolved, @member_tm,
                    "Le scope doit inclure les membres des équipes dont l'user est captain"
  end

  # Cas d'erreur : un membre ordinaire ne voit pas les membres via ce scope
  def test_scope_vide_pour_un_membre_ordinaire
    # @member n'est captain d'aucune équipe → le scope doit être vide
    resolved = TeamMemberPolicy::Scope.new(@member, TeamMember.all).resolve
    assert_equal 0, resolved.count,
                 "Le scope doit être vide pour un utilisateur qui n'est captain d'aucune équipe"
  end
end
