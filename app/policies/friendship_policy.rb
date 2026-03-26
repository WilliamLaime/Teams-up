class FriendshipPolicy < ApplicationPolicy
  # Envoyer une demande d'ami : il faut être connecté
  def create?
    user.present?
  end

  # Annuler/retirer une amitié :
  # - Celui qui a initié la demande peut toujours supprimer (pending ou accepted)
  # - Celui qui a accepté peut aussi retirer (uniquement si accepted)
  def destroy?
    user.present? && (record.user == user || (record.friend == user && record.accepted?))
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
