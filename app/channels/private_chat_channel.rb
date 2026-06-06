class PrivateChatChannel < ApplicationCable::Channel
  # L'utilisateur s'abonne en passant l'ID de la conversation privée
  # Ex : consumer.subscriptions.create({ channel: "PrivateChatChannel", conversation_id: 12 })
  def subscribed
    @conversation = PrivateConversation.find_by(id: params[:conversation_id])

    # Vérifie que la conversation existe et que l'utilisateur en est un participant
    if @conversation && participant?
      stream_from "private_chat_typing_#{@conversation.id}"
    else
      reject
    end
  end

  def unsubscribed
    # Rien à faire — ActionCable gère le nettoyage automatiquement
  end

  # Appelé quand l'utilisateur envoie un signal "typing" depuis le JS
  # Diffuse le nom de l'expéditeur UNIQUEMENT à l'autre participant
  def typing(_data)
    return unless @conversation && current_user

    ActionCable.server.broadcast(
      "private_chat_typing_#{@conversation.id}",
      {
        user_name: current_user.display_name,
        user_id: current_user.id
      }
    )
  end

  private

  # Vérifie que current_user est bien sender ou recipient de la conversation
  def participant?
    @conversation.sender_id == current_user.id ||
      @conversation.recipient_id == current_user.id
  end
end
