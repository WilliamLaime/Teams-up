class MessagesController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  # Charge le contexte (match ou conversation privée) et vérifie les droits
  before_action :set_context_and_check_access

  def create
    skip_authorization

    if @match
      # ── Message de match ──────────────────────────────────────────────────
      @message = @match.messages.build(
        content: message_params[:content],
        user: current_user
      )

      if @message.save
        # Vérifier les achievements liés aux messages envoyés
        AchievementService.new(current_user).check(:message_sent)

        # Met à jour last_read_at de l'expéditeur pour éviter le badge non-lu sur soi-même
        sender_mu = @match.match_users.find_by(user: current_user)
        sender_mu&.update_column(:last_read_at, Time.current)

        # Le broadcast est géré par after_create_commit dans le modèle
        # On réinitialise les formulaires via Turbo Stream (vide le champ texte)
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("chat-form",
                partial: "messages/form",
                locals: { match: @match, message: Message.new }
              ),
              turbo_stream.update("sticky-chat-form",
                partial: "messages/form",
                locals: { match: @match, message: Message.new }
              )
            ]
          end
          format.html { redirect_to @match }
        end
      else
        redirect_to @match, alert: "Impossible d'envoyer le message."
      end

    elsif @conversation
      # ── Message privé ────────────────────────────────────────────────────
      @message = @conversation.messages.build(
        content: message_params[:content],
        user: current_user
      )

      if @message.save
        # Met à jour le timestamp de lecture de l'expéditeur
        # pour ne pas voir son propre message comme non-lu
        @conversation.mark_read_for!(current_user)

        # Réinitialise le formulaire via Turbo Stream
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "sticky-chat-form",
              partial: "messages/form",
              locals: {
                match: nil,
                message: Message.new,
                private_conversation: @conversation
              }
            )
          end
          format.html { redirect_to private_conversation_path(@conversation) }
        end
      else
        redirect_to root_path, alert: "Impossible d'envoyer le message."
      end
    end
  end

  private

  # ── Charge le contexte : match ou conversation privée ─────────────────────
  def set_context_and_check_access
    if params[:match_id]
      # Message de match — comportement existant
      @match = Match.find(params[:match_id])
      match_user = @match.match_users.find_by(user: current_user)

      # Seuls les participants approuvés et organisateurs peuvent écrire
      return if match_user && (match_user.approved? || match_user.role == "organisateur")

      redirect_to @match, alert: "Tu dois être participant du match pour écrire dans le chat."

    elsif params[:private_conversation_id]
      # Message privé — vérifie que current_user est sender ou recipient
      @conversation = PrivateConversation.find(params[:private_conversation_id])

      unless [@conversation.sender_id, @conversation.recipient_id].include?(current_user.id)
        redirect_to root_path, alert: "Accès refusé."
      end
    end
  end

  # Filtre les paramètres autorisés pour un message
  def message_params
    params.require(:message).permit(:content)
  end
end
