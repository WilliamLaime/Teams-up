class PrivateConversationsController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  # ── POST /private_conversations ──────────────────────────────────────────
  # Crée ou retrouve la conversation entre current_user et le destinataire
  # Utilisé depuis le bouton "Envoyer un message" sur le profil d'un autre user
  def create
    skip_authorization

    # Trouve l'autre utilisateur via le paramètre recipient_id
    @other_user = User.find(params[:recipient_id])

    # find_or_create : si la conversation existe déjà, on la retrouve
    @conversation = PrivateConversation.between(current_user, @other_user)

    # Répond en redirigeant vers le show dans la page (data-turbo: false donc redirect normal)
    # La page profil se recharge avec un paramètre pour indiquer d'ouvrir la modale
    redirect_to user_profil_path(@other_user, open_chat: @conversation.id)
  end

  # ── GET /private_conversations/:id ───────────────────────────────────────
  # Charge le chat d'une conversation privée dans le turbo frame de la modale
  def show
    skip_authorization

    # Trouve la conversation par son id
    @conversation = PrivateConversation.find(params[:id])

    # Vérifie que l'utilisateur connecté est bien sender ou recipient
    unless [@conversation.sender_id, @conversation.recipient_id].include?(current_user.id)
      head :forbidden
      return
    end

    # Charge les messages avec les infos des expéditeurs (profil + avatar)
    @messages = @conversation.messages.includes(user: :profil).order(:created_at)
    @message = Message.new

    # Marque la conversation comme lue → retire le badge non-lu dans la sidebar
    @conversation.mark_read_for!(current_user)

    # Broadcast pour mettre à jour l'item dans la sidebar (retire le badge non-lu)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_conversations_#{current_user.id}",
      target: "private-convo-#{@conversation.id}",
      partial: "shared/private_convo_item",
      locals: { conversation: @conversation, current_user: current_user }
    )
  end
end
