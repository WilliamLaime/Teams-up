class TeamInvitationPolicy < ApplicationPolicy
  # Seul le captain de l'équipe peut envoyer une invitation
  def create?
    record.team.captain_id == user.id
  end

  # Seul l'invité peut accepter ou refuser son invitation
  def update?
    record.invitee_id == user.id
  end

  # Le captain peut annuler une invitation en attente ;
  # un joueur peut annuler sa propre demande d'adhésion (statut "requested").
  def destroy?
    record.team.captain_id == user.id ||
      (record.requested? && record.invitee_id == user.id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(invitee: user)
    end
  end
end
