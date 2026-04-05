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
    redirect_to user_profil_simple_path(@other_user, open_chat: @conversation.id)
  end

  # ── DELETE /private_conversations/:id/dismiss ────────────────────────────
  # Masque la conversation pour l'utilisateur connecté (comme la poubelle des chats match)
  # La conversation réapparaît si un nouveau message est reçu
  def dismiss
    skip_authorization

    @conversation = PrivateConversation.find(params[:id])

    unless [@conversation.sender_id, @conversation.recipient_id].include?(current_user.id)
      head :forbidden
      return
    end

    # Marque comme dismissée pour cet utilisateur uniquement
    @conversation.dismiss_for!(current_user)

    # Supprime l'item de la sidebar ET vide le panneau chat de droite via Turbo Stream
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # Retire l'item de la sidebar gauche
          turbo_stream.remove("private-convo-#{@conversation.id}"),
          # Remet le placeholder "Sélectionne une conversation" dans le panneau droit
          # pour que l'utilisateur ne voie plus les messages de la conv supprimée
          turbo_stream.update("sticky-chat-frame",
            html: '<div class="sticky-chat-no-selection">'\
                  '<div style="font-size: 1.8rem;">💬</div>'\
                  '<p>Sélectionne une conversation</p>'\
                  "</div>"
          )
        ]
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  # ── PATCH /private_conversations/:id/mark_read ───────────────────────────
  # Marque la conversation comme lue pour current_user et retire le badge non-lu
  # Appelé via fetch() depuis chat_controller.js quand un message arrive
  # pendant que l'utilisateur a déjà la conversation ouverte
  def mark_read
    skip_authorization

    @conversation = PrivateConversation.find(params[:id])

    # Sécurité : seuls les participants peuvent marquer comme lu
    unless [@conversation.sender_id, @conversation.recipient_id].include?(current_user.id)
      head :forbidden
      return
    end

    # Met à jour le timestamp de dernière lecture
    @conversation.mark_read_for!(current_user)

    # Broadcast pour retirer le badge non-lu dans la sidebar de l'utilisateur
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_conversations_#{current_user.id}",
      target: "private-convo-#{@conversation.id}",
      partial: "shared/private_convo_item",
      locals: { conversation: @conversation, current_user: current_user }
    )

    # Réponse minimale — le JS n'a pas besoin du contenu, juste de la confirmation
    head :ok
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
