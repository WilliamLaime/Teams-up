class NotificationPolicy < ApplicationPolicy
  # Marquer une notification comme lue : seulement si elle appartient à l'utilisateur
  def mark_read?
    owner?
  end

  # Supprimer une notification : seulement si elle appartient à l'utilisateur
  def destroy?
    owner?
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

  private

  # Vérifie que la notification appartient à l'utilisateur connecté
  def owner?
    record.user == user
  end
end
