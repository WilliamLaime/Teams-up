class TeamInvitationPolicy < ApplicationPolicy
  # Seul le captain de l'équipe peut envoyer une invitation
  def create?
    record.team.captain_id == user.id
  end

  # Seul l'invité peut accepter ou refuser son invitation
  def update?
    record.invitee_id == user.id
  end

  # Seul le captain peut annuler une invitation en attente
  def destroy?
    record.team.captain_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(invitee: user)
    end
  end
end
