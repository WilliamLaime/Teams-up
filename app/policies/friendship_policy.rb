class FriendshipPolicy < ApplicationPolicy
  # Envoyer une demande d'ami : il faut être connecté
  def create?
    user.present?
  end

  # Annuler une demande (supprimer l'amitié) : uniquement celui qui a initié
  def destroy?
    user.present? && record.user == user
  end

  # Accepter une demande : uniquement le destinataire (friend)
  def accept?
    user.present? && record.friend == user
  end

  # Refuser une demande : uniquement le destinataire (friend)
  def decline?
    user.present? && record.friend == user
  end
end
