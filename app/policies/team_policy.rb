class TeamPolicy < ApplicationPolicy
  # Tout le monde peut voir la liste (filtrée par le Scope)
  def index?
    true
  end

  def show?
    true
  end

  # Tout utilisateur connecté peut créer une équipe
  def create?
    true
  end

  # Seul le captain peut modifier l'équipe
  def update?
    captain?
  end

  # Seul le captain peut supprimer l'équipe
  def destroy?
    captain?
  end

  # Seul le captain peut transférer son rôle
  def transfer_captain?
    captain?
  end

  # Tout membre non-captain peut quitter l'équipe
  def leave?
    member? && !captain?
  end

  class Scope < ApplicationPolicy::Scope
    # Retourne toutes les équipes dont l'user est membre
    # (ou toutes si non connecté — liste publique)
    def resolve
      if user
        scope.joins(:team_members).where(team_members: { user_id: user.id })
      else
        scope.none
      end
    end
  end

  private

  def captain?
    record.captain_id == user.id
  end

  def member?
    record.members.include?(user)
  end
end
