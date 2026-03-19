class NotificationPolicy < ApplicationPolicy
  # Marquer une notification comme lue : seulement si elle appartient à l'utilisateur
  def mark_read?
    record.user == user
  end

  # Supprimer une notification : seulement si elle appartient à l'utilisateur
  def destroy?
    record.user == user
  end

  # Marquer toutes les notifications comme lues : tout utilisateur connecté
  def mark_all_read?
    true
  end

  class Scope < ApplicationPolicy::Scope
    # L'utilisateur ne voit que ses propres notifications
    def resolve
      scope.where(user: user)
    end
  end
end
