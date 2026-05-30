require "test_helper"

# Tests de TeamInvitationPolicy.
# Règles :
#   create?  → seul le captain de l'équipe peut envoyer une invitation
#   update?  → seul l'invité peut accepter ou refuser son invitation
#   destroy? → seul le captain peut annuler une invitation en attente
#
# On instancie directement la policy sans passer par le controller :
#   TeamInvitationPolicy.new(user, invitation).create?
class TeamInvitationPolicyTest < ActiveSupport::TestCase
  teardown { teardown_db }

  setup do
    # Captain de l'équipe
    @captain = create_test_user(email: "tip_captain@example.com", first_name: "Cap", last_name: "Tip")
    # Invité (reçoit l'invitation)
    @invitee = create_test_user(email: "tip_invitee@example.com", first_name: "Inv", last_name: "Tip")
    # Un tiers sans lien avec l'équipe ni l'invitation
    @stranger = create_test_user(email: "tip_stranger@example.com", first_name: "Str", last_name: "Tip")

    # Crée l'équipe — le callback ajoute @captain comme TeamMember
    @team = Team.create!(name: "Les Politique TIP", captain: @captain)

    # Invitation en attente (pending)
    @invitation = TeamInvitation.new(
      team:    @team,
      inviter: @captain,
      invitee: @invitee,
      status:  "pending"
    )
    # On n'utilise pas create! ici pour éviter la contrainte d'unicité dans certains tests
  end

  # ════════════════════════════════════════════════════════════════════════════
  # create? — seul le captain peut inviter
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut créer une invitation
  def test_create_autorise_pour_le_captain
    assert TeamInvitationPolicy.new(@captain, @invitation).create?,
           "Le captain doit pouvoir créer une invitation"
  end

  # Cas d'erreur : un non-captain ne peut pas créer une invitation
  def test_create_interdit_pour_un_tiers
    refute TeamInvitationPolicy.new(@stranger, @invitation).create?,
           "Un tiers non-captain ne doit pas pouvoir créer une invitation"
  end

  # Cas d'erreur : l'invité lui-même ne peut pas créer son propre invitation
  def test_create_interdit_pour_linvite
    refute TeamInvitationPolicy.new(@invitee, @invitation).create?,
           "L'invité ne doit pas pouvoir créer sa propre invitation (seul le captain peut)"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # update? — seul l'invité peut accepter/refuser
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : l'invité peut accepter ou refuser son invitation
  def test_update_autorise_pour_linvite
    assert TeamInvitationPolicy.new(@invitee, @invitation).update?,
           "L'invité doit pouvoir accepter ou refuser son invitation"
  end

  # Cas d'erreur : le captain ne peut pas accepter l'invitation à la place de l'invité
  def test_update_interdit_pour_le_captain
    refute TeamInvitationPolicy.new(@captain, @invitation).update?,
           "Le captain ne doit pas pouvoir accepter l'invitation à la place de l'invité"
  end

  # Cas d'erreur : un tiers ne peut pas modifier l'invitation
  def test_update_interdit_pour_un_tiers
    refute TeamInvitationPolicy.new(@stranger, @invitation).update?,
           "Un tiers ne doit pas pouvoir modifier l'invitation"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # destroy? — seul le captain peut annuler
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le captain peut annuler une invitation
  def test_destroy_autorise_pour_le_captain
    assert TeamInvitationPolicy.new(@captain, @invitation).destroy?,
           "Le captain doit pouvoir annuler une invitation"
  end

  # Cas d'erreur : l'invité ne peut pas annuler l'invitation (seul le captain peut)
  def test_destroy_interdit_pour_linvite
    refute TeamInvitationPolicy.new(@invitee, @invitation).destroy?,
           "L'invité ne doit pas pouvoir annuler l'invitation (seul le captain peut)"
  end

  # Cas d'erreur : un tiers ne peut pas annuler l'invitation
  def test_destroy_interdit_pour_un_tiers
    refute TeamInvitationPolicy.new(@stranger, @invitation).destroy?,
           "Un tiers ne doit pas pouvoir annuler l'invitation"
  end

  # ════════════════════════════════════════════════════════════════════════════
  # Scope#resolve — filtre les invitations visibles par l'utilisateur
  # ════════════════════════════════════════════════════════════════════════════

  # Cas nominal : le scope retourne uniquement les invitations reçues par l'user
  def test_scope_retourne_les_invitations_de_linvite
    # Persiste l'invitation pour pouvoir la retrouver via le scope
    @invitation.save!
    resolved = TeamInvitationPolicy::Scope.new(@invitee, TeamInvitation.all).resolve
    assert_includes resolved, @invitation,
                    "Le scope doit inclure les invitations reçues par l'invité"
  end

  # Cas d'erreur : le captain ne voit pas ses propres invitations via ce scope
  # (le scope est centré sur l'invité, pas l'inviteur)
  def test_scope_ne_retourne_pas_les_invitations_envoyees
    @invitation.save!
    resolved = TeamInvitationPolicy::Scope.new(@captain, TeamInvitation.all).resolve
    # Le captain est inviteur, pas invitee → ne doit pas apparaître dans ce scope
    assert_not_includes resolved, @invitation,
                        "Le scope ne doit pas retourner les invitations envoyées (seulement reçues)"
  end
end
