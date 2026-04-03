class Message < ApplicationRecord
  # Un message appartient à un utilisateur (l'expéditeur)
  belongs_to :user

  # Un message appartient soit à un match (groupe), soit à une conversation privée, soit à une équipe
  # Les trois sont optionnels pour permettre l'un ou l'autre
  belongs_to :match, optional: true
  belongs_to :private_conversation, optional: true
  belongs_to :team, optional: true

  # Validation : le contenu est obligatoire et limité à 1000 caractères
  validates :content, presence: true, length: { maximum: 1000 }

  # Validation : un message doit appartenir à un match, une conversation privée OU une équipe
  validate :belongs_to_match_or_private_conversation_or_team

  # Après la création d'un message, on le diffuse en temps réel via Turbo Streams
  after_create_commit :broadcast_message, :broadcast_unread_notifications

  # Callback uniquement pour les messages de match (réactive si dismissé)
  after_create_commit :reactivate_dismissed_conversations, if: :match_id?

  # Callback pour les messages privés (réactive la conversation si elle était masquée)
  after_create_commit :reactivate_dismissed_private_conversation, if: :private_conversation_id?

  private

  # ── Validation : match_id OU private_conversation_id OU team_id doit être présent ────
  def belongs_to_match_or_private_conversation_or_team
    if match_id.blank? && private_conversation_id.blank? && team_id.blank?
      errors.add(:base, "Un message doit appartenir à un match, une conversation privée ou une équipe")
    end
  end

  # ── Diffuse les badges non-lus dans la sidebar ────────────────────────────
  def broadcast_unread_notifications
    if team_id?
      # Message d'équipe : déplace la conv en tête de sidebar pour tous les membres SAUF l'expéditeur
      team.team_members.where.not(user_id: user_id).each do |tm|
        # 1. Supprime l'item de sa position actuelle
        Turbo::StreamsChannel.broadcast_remove_to(
          "user_conversations_#{tm.user_id}",
          target: "sticky-team-convo-#{team_id}"
        )
        # 2. Insère en tête de liste (avec badge non-lu car tm n'est pas l'expéditeur)
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_conversations_#{tm.user_id}",
          target: "sticky-chat-sidebar-list",
          partial: "shared/team_convo_item",
          locals: { team: team, team_member: tm }
        )
      end
    elsif match_id?
      # Message de match : déplace la conv en tête de sidebar pour tous les participants SAUF l'expéditeur
      match.match_users.where.not(user_id: user_id).each do |mu|
        # 1. Supprime l'item de sa position actuelle
        Turbo::StreamsChannel.broadcast_remove_to(
          "user_conversations_#{mu.user_id}",
          target: "sticky-convo-#{match_id}"
        )
        # 2. Insère en tête de liste (avec badge non-lu car mu n'est pas l'expéditeur)
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_conversations_#{mu.user_id}",
          target: "sticky-chat-sidebar-list",
          partial: "shared/sticky_convo_item",
          locals: { match: match, match_user: mu }
        )
      end
    elsif private_conversation_id?
      recipient = private_conversation.other_user(user)

      # ── Met à jour uniquement la sidebar du DESTINATAIRE ──────────────────
      # L'expéditeur est géré dans MessagesController APRÈS mark_read_for!

      # IMPORTANT : on utilise Message.where(...).count et NON private_conversation.messages.count
      # car dans after_create_commit, private_conversation est le même objet Ruby que @conversation
      # dans le controller (défini via messages.build). Son association messages est en cache
      # avec seulement le nouveau message → count retournerait toujours 1 par erreur.
      total_messages = Message.where(private_conversation_id: private_conversation_id).count

      # Vérifie si le destinataire avait masqué la conversation AVANT la réactivation
      recipient_dismissed = private_conversation.dismissed_for?(recipient)

      if total_messages == 1 || recipient_dismissed
        # Premier message OU conversation réactivée : l'item n'existe pas encore → prepend direct
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_conversations_#{recipient.id}",
          target: "private-chat-sidebar-list",
          partial: "shared/private_convo_item",
          locals: { conversation: private_conversation, current_user: recipient }
        )
      else
        # Conversation existante : supprime de sa position puis insère en tête
        Turbo::StreamsChannel.broadcast_remove_to(
          "user_conversations_#{recipient.id}",
          target: "private-convo-#{private_conversation_id}"
        )
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_conversations_#{recipient.id}",
          target: "private-chat-sidebar-list",
          partial: "shared/private_convo_item",
          locals: { conversation: private_conversation, current_user: recipient }
        )
      end
    end
  end

  # ── Réactive les conversations de match dismissées ────────────────────────
  def reactivate_dismissed_conversations
    match.match_users.where.not(chat_dismissed_at: nil).update_all(chat_dismissed_at: nil)
  end

  # ── Réactive la conversation privée dismissée (nouveau message reçu) ───────
  # On réactive UNIQUEMENT pour le destinataire du message
  # L'expéditeur garde le contrôle de son propre masquage :
  # s'il a masqué la conversation et envoie un nouveau message (via la page profil),
  # on ne réaffiche pas la conv dans SA sidebar sans qu'il le demande
  def reactivate_dismissed_private_conversation
    recipient = private_conversation.other_user(user)

    # Détermine quelle colonne effacer selon le rôle du destinataire
    if recipient.id == private_conversation.sender_id
      private_conversation.update_column(:sender_dismissed_at, nil)
    else
      private_conversation.update_column(:recipient_dismissed_at, nil)
    end
  end

  # ── Diffuse le message en temps réel dans la zone de chat ─────────────────
  def broadcast_message
    if team_id?
      broadcast_team_message
    elsif match_id?
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

  # ── Broadcast pour les messages d'équipe ──────────────────────────────────
  def broadcast_team_message
    # 1. Sticky chat — reçu par tous les membres abonnés à ce stream
    broadcast_append_to(
      "team_chat_sticky_#{team_id}",
      target: "sticky-chat-messages",
      partial: "messages/message",
      locals: { message: self }
    )

    # 2. Page show de l'équipe (modale) — stream séparé pour éviter les doublons
    broadcast_append_to(
      "team_chat_page_#{team_id}",
      target: "team-chat-messages",
      partial: "messages/message",
      locals: { message: self }
    )

    # 3. Preview du dernier message sur la carte de la page show (hors modale)
    #    Met à jour le texte affiché directement sur la page sans ouvrir la modale
    broadcast_replace_to(
      "team_chat_page_#{team_id}",
      target: "team-page-last-message-#{team_id}",
      partial: "teams/chat_page_preview",
      locals: { team: team }
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
