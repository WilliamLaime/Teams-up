# frozen_string_literal: true

# Policy Pundit pour les conversations privées (1-à-1 entre deux utilisateurs).
# Le "record" est une PrivateConversation.
class PrivateConversationPolicy < ApplicationPolicy
  # Tout utilisateur connecté peut initier une conversation privée
  def create?
    true
  end

  # Seuls les participants (sender ou recipient) peuvent voir la conversation
  def show?
    participant?
  end

  # Seuls les participants peuvent masquer la conversation
  def dismiss?
    participant?
  end

  # Seuls les participants peuvent marquer la conversation comme lue
  def mark_read?
    participant?
  end

  private

  # Vérifie que l'utilisateur est l'un des deux participants de la conversation
  def participant?
    [record.sender_id, record.recipient_id].include?(user.id)
  end
end
