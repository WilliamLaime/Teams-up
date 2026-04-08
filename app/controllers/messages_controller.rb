class MessagesController < ApplicationController
  # authenticate_user! est déjà appliqué globalement dans ApplicationController

  # Charge le contexte (match ou conversation privée) et vérifie les droits
  before_action :set_context_and_check_access

  def create
    skip_authorization

    if @team
      # ── Message d'équipe ──────────────────────────────────────────────────
      @message = @team.messages.build(
        content: message_params[:content],
        user: current_user
      )

      if @message.save
        # Met à jour le timestamp de lecture de l'expéditeur
        now = Time.current
        @team_member.update_column(:chat_last_read_at, now)
        # Met à jour l'objet en mémoire pour que le partial voie la bonne valeur
        @team_member.chat_last_read_at = now

        # Le broadcast des messages aux autres membres est géré par after_create_commit
        # dans le modèle Message. La mise à jour de la sidebar de l'EXPÉDITEUR est incluse
        # directement dans la réponse HTTP Turbo Stream pour garantir la fiabilité.
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              # 1. Déplace la conversation d'équipe en tête de la sidebar
              turbo_stream.remove("sticky-team-convo-#{@team.id}"),
              turbo_stream.prepend("sticky-chat-sidebar-list",
                partial: "shared/team_convo_item",
                locals: { team: @team, team_member: @team_member }
              ),
              # 2. Réinitialise le formulaire du sticky chat
              turbo_stream.update("sticky-chat-form",
                partial: "messages/form",
                locals: { team: @team, message: Message.new }
              ),
              # 3. Réinitialise le formulaire de la page équipe (si ouvert)
              turbo_stream.update("team-chat-form",
                partial: "messages/form",
                locals: { team: @team, message: Message.new }
              )
            ]
          end
          format.html { redirect_to @team }
        end
      else
        redirect_to @team, alert: "Impossible d'envoyer le message."
      end

    elsif @match
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
        if sender_mu
          now = Time.current
          sender_mu.update_column(:last_read_at, now)
          # Met à jour l'objet en mémoire pour que le partial voie la bonne valeur
          sender_mu.last_read_at = now
        end

        # Le broadcast des messages aux autres participants est géré par after_create_commit
        # dans le modèle Message. La mise à jour de la sidebar de l'EXPÉDITEUR est incluse
        # directement dans la réponse HTTP Turbo Stream (ci-dessous) pour garantir la fiabilité :
        # un broadcast ActionCable asynchrone pouvait parfois arriver en décalé, causant
        # la disparition temporaire du chat dans la sidebar.
        respond_to do |format|
          format.turbo_stream do
            streams = [
              # 1. Réinitialise le formulaire de la page match (si ouvert)
              turbo_stream.update("chat-form",
                partial: "messages/form",
                locals: { match: @match, message: Message.new }
              ),
              # 2. Réinitialise le formulaire du sticky chat
              turbo_stream.update("sticky-chat-form",
                partial: "messages/form",
                locals: { match: @match, message: Message.new }
              )
            ]

            # 3. Déplace la conversation en tête de la sidebar pour l'expéditeur
            #    (supprime de sa position actuelle puis insère en premier)
            if sender_mu
              streams.unshift(
                turbo_stream.remove("sticky-convo-#{@match.id}"),
                turbo_stream.prepend("sticky-chat-sidebar-list",
                  partial: "shared/sticky_convo_item",
                  locals: { match: @match, match_user: sender_mu }
                )
              )
            end

            render turbo_stream: streams
          end
          format.html { redirect_to @match }
        end
      else
        redirect_to @match, alert: "Impossible d'envoyer le message."
      end

    elsif @conversation
      # ── Message privé ────────────────────────────────────────────────────

      # Capture l'état AVANT le save : on en a besoin après pour choisir prepend vs remove+prepend
      # - Premier message : l'item n'est pas encore dans la sidebar de l'expéditeur
      # - Expéditeur avait masqué la conv : l'item a été retiré du DOM
      # Dans les deux cas → prepend seul. Sinon → remove puis prepend.
      is_first_message    = !Message.exists?(private_conversation_id: @conversation.id)
      sender_was_dismissed = @conversation.dismissed_for?(current_user)

      @message = @conversation.messages.build(
        content: message_params[:content],
        user: current_user
      )

      if @message.save
        # Met à jour le timestamp de lecture de l'expéditeur
        # pour ne pas voir son propre message comme non-lu
        @conversation.mark_read_for!(current_user)

        # Si l'expéditeur avait masqué la conversation et ré-envoie un message (via page profil),
        # on réactive son propre dismissed_at pour que la conv réapparaisse dans sa sidebar
        if sender_was_dismissed
          col = @conversation.sender_id == current_user.id ? :sender_dismissed_at : :recipient_dismissed_at
          @conversation.update_column(col, nil)
        end

        # La mise à jour de la sidebar de l'expéditeur est incluse directement dans la réponse
        # HTTP Turbo Stream pour garantir la fiabilité (pas de broadcast ActionCable asynchrone).
        # Le broadcast aux DESTINATAIRES reste géré par after_create_commit dans le modèle.
        respond_to do |format|
          format.turbo_stream do
            streams = []

            # 1. Déplace la conversation privée en tête de la sidebar de l'expéditeur
            if is_first_message || sender_was_dismissed
              # Item absent du DOM (premier message ou conv masquée) → insère en haut
              streams << turbo_stream.prepend("private-chat-sidebar-list",
                partial: "shared/private_convo_item",
                locals:  { conversation: @conversation, current_user: current_user }
              )
            else
              # Item déjà présent → supprime de sa position puis insère en tête
              streams << turbo_stream.remove("private-convo-#{@conversation.id}")
              streams << turbo_stream.prepend("private-chat-sidebar-list",
                partial: "shared/private_convo_item",
                locals:  { conversation: @conversation, current_user: current_user }
              )
            end

            # 2. Réinitialise le formulaire du sticky chat
            streams << turbo_stream.update("sticky-chat-form",
              partial: "messages/form",
              locals: {
                match: nil,
                message: Message.new,
                private_conversation: @conversation
              }
            )

            render turbo_stream: streams
          end
          format.html { redirect_to private_conversation_path(@conversation) }
        end
      else
        redirect_to root_path, alert: "Impossible d'envoyer le message."
      end
    end
  end

  private

  # ── Charge le contexte : équipe, match ou conversation privée ────────────
  def set_context_and_check_access
    if params[:team_id]
      # Message d'équipe — vérifie que l'utilisateur est membre
      @team = Team.find(params[:team_id])
      @team_member = @team.team_members.find_by(user: current_user)

      return if @team_member

      redirect_to @team, alert: "Tu dois être membre de l'équipe pour écrire dans le chat."

    elsif params[:match_id]
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
