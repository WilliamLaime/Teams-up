class TeamMemberPolicy < ApplicationPolicy
  # Seul le captain peut retirer un membre (et pas lui-même)
  def destroy?
    record.team.captain_id == user.id && record.user_id != user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:team).where(teams: { captain_id: user.id })
    end
  end
end
