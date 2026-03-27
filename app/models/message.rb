class Message < ApplicationRecord
  # Un message appartient à un utilisateur (l'expéditeur)
  belongs_to :user

  # Un message appartient soit à un match (groupe), soit à une conversation privée
  # Les deux sont optionnels pour permettre l'un ou l'autre
  belongs_to :match, optional: true
  belongs_to :private_conversation, optional: true

  # Validation : le contenu est obligatoire et limité à 1000 caractères
  validates :content, presence: true, length: { maximum: 1000 }

  # Validation : un message doit appartenir à un match OU une conversation privée
  validate :belongs_to_match_or_private_conversation

  # Après la création d'un message, on le diffuse en temps réel via Turbo Streams
  after_create_commit :broadcast_message, :broadcast_unread_notifications

  # Callback uniquement pour les messages de match (réactive si dismissé)
  after_create_commit :reactivate_dismissed_conversations, if: :match_id?

  private

  # ── Validation : match_id OU private_conversation_id doit être présent ────
  def belongs_to_match_or_private_conversation
    if match_id.blank? && private_conversation_id.blank?
      errors.add(:base, "Un message doit appartenir à un match ou une conversation privée")
    end
  end

  # ── Diffuse les badges non-lus dans la sidebar ────────────────────────────
  def broadcast_unread_notifications
    if match_id?
      # Message de match : notifie tous les participants SAUF l'expéditeur
      match.match_users.where.not(user_id: user_id).each do |mu|
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_conversations_#{mu.user_id}",   # stream personnel du destinataire
          target: "sticky-convo-#{match_id}",   # l'item à remplacer dans sa sidebar
          partial: "shared/sticky_convo_item",
          locals: { match: match, match_user: mu }
        )
      end
    elsif private_conversation_id?
      # Message privé : notifie uniquement le destinataire (pas l'expéditeur)
      recipient = private_conversation.other_user(user)
      Turbo::StreamsChannel.broadcast_replace_to(
        "user_conversations_#{recipient.id}",        # stream personnel du destinataire
        target: "private-convo-#{private_conversation_id}", # l'item à remplacer dans sa sidebar
        partial: "shared/private_convo_item",
        locals: { conversation: private_conversation, current_user: recipient }
      )
    end
  end

  # ── Réactive les conversations de match dismissées ────────────────────────
  def reactivate_dismissed_conversations
    match.match_users.where.not(chat_dismissed_at: nil).update_all(chat_dismissed_at: nil)
  end

  # ── Diffuse le message en temps réel dans la zone de chat ─────────────────
  def broadcast_message
    if match_id?
      broadcast_match_message
    elsif private_conversation_id?
      broadcast_private_message
    end
  end

  # ── Broadcast pour les messages de match ──────────────────────────────────
  def broadcast_match_message
    # 1. Cible la modal du chat sur la page show du match
    broadcast_append_to(
      "match_chat_#{match_id}",
      target: "chat-messages",
      partial: "messages/message",
      locals: { message: self }
    )

    # 2. Met à jour la preview card des 2 derniers messages
    broadcast_update_to(
      "match_chat_#{match_id}",
      target: "chat-preview-list-#{match_id}",
      partial: "matches/chat_preview_list",
      locals: { match: match }
    )

    # 3. Cible le chat sticky (stream différent pour éviter les doublons)
    broadcast_append_to(
      "match_chat_sticky_#{match_id}",
      target: "sticky-chat-messages",
      partial: "messages/message",
      locals: { message: self }
    )
  end

  # ── Broadcast pour les messages privés ────────────────────────────────────
  def broadcast_private_message
    # Ajoute le message dans la zone de chat des DEUX participants
    broadcast_append_to(
      "private_chat_#{private_conversation_id}",  # stream unique par conversation
      target: "sticky-chat-messages",             # même id que le chat match
      partial: "messages/message",
      locals: { message: self }
    )
  end
end
