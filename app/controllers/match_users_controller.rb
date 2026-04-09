class MatchUsersController < ApplicationController
  # Retrouver le match parent avant chaque action
  before_action :set_match
  # Retrouver l'inscription spécifique pour approve, reject, destroy et confirm
  before_action :set_match_user, only: %i[destroy approve reject confirm]

  # POST /matches/:match_id/match_users
  # Rejoindre un match (ou rejoindre la file d'attente si le match est complet)
  def create
    # On crée l'inscription avec le message optionnel du joueur
    @match_user = @match.match_users.new(user: current_user, role: "joueur", message: params[:message].presence)
    authorize @match_user

    # Vérifie si l'utilisateur est déjà inscrit (peu importe le statut)
    if @match.match_users.exists?(user: current_user)
      redirect_to @match, alert: "Tu es déjà inscrit à ce match."
      return
    end

    # ── Vérification de la restriction de genre ───────────────────────────────
    # Si le match est réservé aux femmes ET que l'utilisateur n'est pas une femme,
    # on bloque l'inscription avec un message explicatif.
    # current_user.genre != "femme" inclut aussi les utilisateurs sans genre déclaré (nil).
    if @match.genre_restriction == "feminin" && current_user.genre != "femme"
      redirect_to match_path(@match, **match_redirect_options),
                  alert: "Ce match est réservé aux joueuses. Seules les femmes peuvent s'inscrire."
      return
    end
    # ── Fin vérification genre ────────────────────────────────────────────────

    # On récupère l'organisateur une seule fois pour les notifications
    organizer = @match.organizer_match_user&.user

    # Redirige vers le bon cas selon l'état du match
    if @match.full?
      join_waiting_list(organizer)
    elsif @match.manual_validation?
      join_with_manual_validation(organizer)
    else
      # Mode automatique : accepté immédiatement
      join_automatically(organizer)
    end
  end

  # DELETE /matches/:match_id/match_users/:id
  # Quitter un match — si quelqu'un est en file d'attente, il est promu automatiquement
  def destroy
    authorize @match_user

    # Sauvegarde l'utilisateur et son statut avant destruction
    # (après @match_user.destroy, ces infos ne sont plus accessibles)
    leaving_user = @match_user.user
    was_approved = @match_user.approved?

    # Si le joueur avait une place approuvée, on gère la file d'attente
    promote_next_in_line if was_approved

    @match_user.destroy

    # Notifie l'organisateur en temps réel si un joueur approuvé a quitté
    # (pas de notif si pending/waiting/rejected — ces cas ne libèrent pas de place)
    if was_approved
      broadcast_player_left_to_organizer(leaving_user)
      # Email transactionnel : informe l'organisateur du départ et de la place libérée
      UserMailer.match_player_left(@match, leaving_user).deliver_later
    end

    # Match privé → retour à l'index (le joueur n'a plus accès sans token)
    # Match public → retour à la show du match
    if @match.private?
      redirect_to matches_path, notice: "Tu as quitté le match."
    else
      redirect_to @match, notice: "Tu as quitté le match."
    end
  end

  # PATCH /matches/:match_id/match_users/:id/approve
  # Approuver un joueur (réservé à l'organisateur via Pundit)
  def approve
    authorize @match_user

    # Garde idempotente : si le joueur n'est plus en attente (déjà traité),
    # on ne fait rien pour éviter de décrémenter player_left plusieurs fois.
    # Cela arrive quand l'organisateur clique plusieurs fois car la modal
    # de notification (newRequestModal) ne se met pas à jour visuellement.
    return redirect_to @match unless @match_user.pending?

    # Si le match est complet, on place le joueur en liste d'attente plutôt que de l'approuver
    if @match.full?
      @match_user.update(status: "waiting")
      flash_msg = "#{@match_user.user.display_name} a été placé en liste d'attente (match complet)."
    else
      # Place normale disponible : on approuve et on décrémente le compteur
      @match_user.update(status: "approved")
      @match.decrement!(:player_left)
      notify(@match_user.user, "✅ Ta demande pour \"#{@match.title}\" a été acceptée !")
      # Email transactionnel : informe le joueur de l'acceptation
      UserMailer.match_status_changed(@match_user, accepted: true).deliver_later
      # Broadcast en temps réel vers le joueur s'il est sur la page du match.
      broadcast_decision_to_participant(accepted: true)
      flash_msg = "#{@match_user.user.display_name} a été approuvé !"
    end

    # Recharge les demandes encore en attente pour mettre à jour la modal
    # On charge aussi avatar_attachment et blob pour éviter des URLs cassées
    pending_users = @match.match_users.where(status: "pending").includes(user: { profil: { avatar_attachment: :blob } })

    respond_to do |format|
      format.turbo_stream do
        # Si l'action vient de la modal de notification (#newRequestModal),
        # on redirige vers la page du match pour donner un retour visuel immédiat.
        # Sinon (depuis #pendingModal sur la show page), on met à jour la liste en place.
        if params[:from_notification].present?
          redirect_to @match, notice: flash_msg
        else
          # Réponse Turbo Stream : met à jour #pending_modal_inner sans fermer la modal
          render turbo_stream: turbo_stream.update(
            "pending_modal_inner",
            partial: "match_users/pending_modal_content",
            locals: { match: @match, pending_users: pending_users }
          )
        end
      end
      # Fallback HTML classique (si Turbo n'est pas actif)
      format.html { redirect_to @match, notice: flash_msg }
    end
  end

  # PATCH /matches/:match_id/match_users/:id/reject
  # Rejeter un joueur (réservé à l'organisateur via Pundit)
  def reject
    authorize @match_user

    # Garde idempotente : si le joueur n'est plus en attente (déjà traité), on ne fait rien.
    return redirect_to @match unless @match_user.pending?

    @match_user.update(status: "rejected")
    notify(@match_user.user, "❌ Ta demande pour \"#{@match.title}\" a été refusée.")
    # Email transactionnel : informe le joueur du refus
    UserMailer.match_status_changed(@match_user, accepted: false).deliver_later
    # Broadcast en temps réel vers le joueur s'il est sur la page du match.
    broadcast_decision_to_participant(accepted: false)
    flash_msg = "#{@match_user.user.display_name} a été refusé."

    # Recharge les demandes encore en attente pour mettre à jour la modal
    # On charge aussi avatar_attachment et blob pour éviter des URLs cassées
    pending_users = @match.match_users.where(status: "pending").includes(user: { profil: { avatar_attachment: :blob } })

    respond_to do |format|
      format.turbo_stream do
        # Si l'action vient de la modal de notification, on redirige vers la show page.
        if params[:from_notification].present?
          redirect_to @match, notice: flash_msg
        else
          # Réponse Turbo Stream : met à jour #pending_modal_inner sans fermer la modal
          render turbo_stream: turbo_stream.update(
            "pending_modal_inner",
            partial: "match_users/pending_modal_content",
            locals: { match: @match, pending_users: pending_users }
          )
        end
      end
      # Fallback HTML classique
      format.html { redirect_to @match, notice: flash_msg }
    end
  end

  # PATCH /matches/:match_id/match_users/:id/confirm
  # Le membre de l'équipe confirme lui-même sa participation au match d'équipe
  # Réservé à l'utilisateur concerné (pas à l'organisateur)
  def confirm
    authorize @match_user

    # Le match doit être un match d'équipe
    unless @match.team_id.present?
      return redirect_to @match, alert: "Ce match n'est pas un match d'équipe."
    end

    # Garde idempotente : seul un statut "pending" peut être confirmé
    return redirect_to @match unless @match_user.pending?

    @match_user.update(status: "approved")
    notify(@match.user, "✅ #{current_user.display_name} a confirmé sa participation à \"#{@match.title}\".")
    redirect_to @match, notice: "Tu es inscrit au match !"
  end

  private

  # Retrouve le match parent via l'id dans l'URL
  def set_match
    @match = Match.find(params[:match_id])
  end

  # Retrouve l'inscription spécifique via l'id dans l'URL
  def set_match_user
    @match_user = @match.match_users.find(params[:id])
  end

  # Envoie une notification in-app à un utilisateur donné.
  # Si user est nil (ex: organisateur introuvable), on ne fait rien.
  def notify(user, message)
    return unless user

    Notification.create(user: user, message: message, link: match_path(@match))
  end

  # Notifie l'organisateur en temps réel qu'une nouvelle demande manuelle est arrivée.
  # Deux broadcasts :
  #   1. Met à jour la liste #pending_modal_inner sur la show page (silencieux)
  #   2. Envoie une modal de notification sur le canal personnel de l'organisateur
  def broadcast_pending_modal_to_organizer
    orga = organizer_user
    return unless orga

    # Recharge les demandes en attente depuis la base (inclut la nouvelle demande)
    # On charge aussi avatar_attachment et blob pour éviter des URLs cassées
    pending_users = @match.match_users.where(status: "pending").includes(user: { profil: { avatar_attachment: :blob } })

    # Broadcast 1 : met à jour silencieusement la liste sur la show page
    # (si l'orga est sur la show, il voit la liste à jour sans rechargement)
    Turbo::StreamsChannel.broadcast_update_to(
      "match_#{@match.id}_organizer",
      target: "pending_modal_inner",
      partial: "match_users/pending_modal_content",
      locals: { match: @match, pending_users: pending_users }
    )

    # Broadcast 2 : notification globale via le canal personnel de l'organisateur
    # → affiche directement la liste avec boutons accepter/refuser, peu importe la page
    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{orga.id}_notifications",
      target: "global_notification_container",
      partial: "match_users/new_request_notification",
      locals: { match: @match, pending_users: pending_users }
    )
  end

  # Notifie l'organisateur en temps réel qu'un joueur approuvé a quitté le match.
  # Appelé depuis destroy (uniquement si was_approved).
  def broadcast_player_left_to_organizer(leaving_user)
    orga = organizer_user
    return unless orga

    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{orga.id}_notifications",
      target: "global_notification_container",
      partial: "match_users/player_left_notification",
      locals: { match: @match, leaving_user: leaving_user }
    )
  end

  # Notifie l'organisateur en temps réel qu'un joueur a rejoint automatiquement.
  # Appelé depuis join_automatically après le save et le decrement.
  def broadcast_auto_join_to_organizer
    orga = organizer_user
    return unless orga

    # On recharge le match pour avoir le player_left à jour (après decrement!)
    @match.reload
    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{orga.id}_notifications",
      target: "global_notification_container",
      partial: "match_users/auto_join_notification",
      locals: { match: @match, joining_user: current_user, match_user: @match_user }
    )
  end

  # Envoie la notification de décision (accepté/refusé) au joueur concerné.
  # Appelé depuis approve et reject.
  def broadcast_decision_to_participant(accepted:)
    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{@match_user.user_id}_notifications",
      target: "global_notification_container",
      partial: "match_users/decision_notification",
      locals: { accepted: accepted, match: @match }
    )
  end

  # Retourne l'user organisateur du match
  # Utilisé par plusieurs méthodes de broadcast pour cibler le canal personnel de l'orga
  def organizer_user
    @match.organizer_match_user&.user
  end

  # Gère la promotion du prochain joueur en file d'attente quand une place se libère
  def promote_next_in_line
    # Cherche le premier joueur en file d'attente (le plus ancien en premier)
    next_in_line = @match.match_users.where(status: "waiting").order(created_at: :asc).first

    if next_in_line
      # Promeut automatiquement le joueur — player_left reste à 0 car la place est reprise
      next_in_line.update(status: "approved")
      message = "🎉 Une place s'est libérée ! Tu as été automatiquement inscrit au match \"#{@match.title}\"."
      notify(next_in_line.user, message)
      # Email transactionnel : informe le joueur de sa promotion depuis la file d'attente
      UserMailer.match_status_changed(next_in_line, accepted: true).deliver_later
    else
      # Personne en attente : on rend la place disponible
      @match.increment!(:player_left)
    end
  end

  # Retourne les options de redirect pour le match — inclut le token si match privé
  def match_redirect_options
    @match.private? ? { token: @match.private_token } : {}
  end

  # Cas 1 : Le match est complet → mise en file d'attente
  def join_waiting_list(organizer)
    @match_user.status = "waiting"
    if @match_user.save
      notify(organizer, "#{current_user.display_name} s'est inscrit en file d'attente pour \"#{@match.title}\"")
      # Email transactionnel : informe l'organisateur qu'un joueur est en file d'attente
      UserMailer.match_joined(@match, current_user, status: "waiting").deliver_later
      redirect_to match_path(@match, **match_redirect_options),
                  notice: "Le match est complet. Tu as été ajouté à la file d'attente !"
    else
      redirect_to match_path(@match, **match_redirect_options), alert: "Impossible de rejoindre la file d'attente."
    end
  end

  # Cas 2 : Validation manuelle → en attente de l'organisateur
  def join_with_manual_validation(organizer)
    @match_user.status = "pending"
    @match_user.save
    notify(organizer, "#{current_user.display_name} veut rejoindre votre match \"#{@match.title}\"")
    # Email transactionnel : informe l'organisateur d'une nouvelle demande à traiter
    UserMailer.match_joined(@match, current_user, status: "pending").deliver_later

    # Broadcast en temps réel vers l'organisateur s'il est sur la page du match.
    # Met à jour le contenu de #pending_modal_inner et ouvre la modal automatiquement.
    broadcast_pending_modal_to_organizer

    redirect_to match_path(@match, **match_redirect_options), notice: "Ta demande a été envoyée à l'organisateur !"
  end

  # Cas 3 : Validation automatique → accepté immédiatement
  def join_automatically(organizer)
    @match_user.status = "approved"
    if @match_user.save
      @match.decrement!(:player_left)
      notify(organizer, "#{current_user.display_name} a rejoint votre match \"#{@match.title}\"")
      # Email transactionnel : informe l'organisateur qu'un joueur a rejoint automatiquement
      UserMailer.match_joined(@match, current_user, status: "approved").deliver_later

      # Notifie l'organisateur en temps réel s'il est sur la page du match.
      # Injecte la modal #autoJoinModal dans son navigateur et l'ouvre automatiquement.
      # Doit être appelé AVANT redirect_to (le redirect stoppe l'exécution côté client).
      broadcast_auto_join_to_organizer

      # flash[:show_calendar_modal] déclenche la modale "Demande acceptée" dans show.html.erb
      flash[:show_calendar_modal] = true
      redirect_to match_path(@match, **match_redirect_options), notice: "Tu as rejoint le match !"
    else
      redirect_to match_path(@match, **match_redirect_options), alert: "Impossible de rejoindre le match."
    end
  end
end
