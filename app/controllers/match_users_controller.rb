class MatchUsersController < ApplicationController
  # Retrouver le match parent avant chaque action
  before_action :set_match
  # Retrouver l'inscription spécifique pour approve, reject et destroy
  before_action :set_match_user, only: [:destroy, :approve, :reject]

  # POST /matches/:match_id/match_users
  # Rejoindre un match (ou rejoindre la file d'attente si le match est complet)
  def create
    @match_user = @match.match_users.new(user: current_user, role: "joueur")
    authorize @match_user

    # Vérifie si l'utilisateur est déjà inscrit (peu importe le statut)
    if @match.match_users.exists?(user: current_user)
      redirect_to @match, alert: "Tu es déjà inscrit à ce match."
      return
    end

    # Si le match est complet, on met l'utilisateur en file d'attente
    if @match.full?
      @match_user.status = "waiting"
      if @match_user.save
        notify_organizer("#{current_user.display_name} s'est inscrit en file d'attente pour \"#{@match.title}\"")
        redirect_to @match, notice: "Le match est complet. Tu as été ajouté à la file d'attente !"
      else
        redirect_to @match, alert: "Impossible de rejoindre la file d'attente."
      end
      return
    end

    if @match.manual_validation?
      # Mode manuel : en attente de validation par l'organisateur
      @match_user.status = "pending"
      @match_user.save
      notify_organizer("#{current_user.display_name} veut rejoindre votre match \"#{@match.title}\"")
      redirect_to @match, notice: "Ta demande a été envoyée à l'organisateur !"
    else
      # Mode automatique : accepté immédiatement
      @match_user.status = "approved"
      if @match_user.save
        @match.decrement!(:player_left)
        notify_organizer("#{current_user.display_name} a rejoint votre match \"#{@match.title}\"")
        redirect_to @match, notice: "Tu as rejoint le match !"
      else
        redirect_to @match, alert: "Impossible de rejoindre le match."
      end
    end
  end

  # DELETE /matches/:match_id/match_users/:id
  # Quitter un match — si quelqu'un est en file d'attente, il est promu automatiquement
  def destroy
    authorize @match_user

    if @match_user.approved?
      # Cherche le premier joueur en file d'attente (le plus ancien en premier)
      next_in_line = @match.match_users.where(status: "waiting").order(created_at: :asc).first

      if next_in_line
        # Promeut automatiquement le joueur en file d'attente
        next_in_line.update(status: "approved")
        notify_player(next_in_line.user, "🎉 Une place s'est libérée ! Tu as été automatiquement inscrit au match \"#{@match.title}\".")
        # player_left reste à 0 car la place est immédiatement reprise
      else
        # Personne en attente : on rend la place disponible
        @match.increment!(:player_left)
      end
    end

    @match_user.destroy
    redirect_to @match, notice: "Tu as quitté le match."
  end

  # PATCH /matches/:match_id/match_users/:id/approve
  # Approuver un joueur (réservé à l'organisateur)
  def approve
    # Pundit vérifie que seul l'organisateur peut approuver
    authorize @match_user

    @match_user.update(status: "approved")
    @match.decrement!(:player_left)

    # Notifie le joueur que sa demande a été acceptée
    notify_player(@match_user.user, "✅ Ta demande pour \"#{@match.title}\" a été acceptée !")

    redirect_to @match, notice: "#{@match_user.user.display_name} a été approuvé !"
  end

  # PATCH /matches/:match_id/match_users/:id/reject
  # Rejeter un joueur (réservé à l'organisateur)
  def reject
    # Pundit vérifie que seul l'organisateur peut rejeter
    authorize @match_user

    @match_user.update(status: "rejected")

    # Notifie le joueur que sa demande a été refusée
    notify_player(@match_user.user, "❌ Ta demande pour \"#{@match.title}\" a été refusée.")

    redirect_to @match, notice: "#{@match_user.user.display_name} a été refusé."
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

  # Envoie une notification à l'organisateur du match
  def notify_organizer(message)
    organizer_match_user = @match.organizer_match_user
    return unless organizer_match_user

    Notification.create(
      user: organizer_match_user.user,
      message: message,
      link: match_path(@match)
    )
  end

  # Envoie une notification à un joueur spécifique
  def notify_player(player, message)
    Notification.create(
      user: player,
      message: message,
      link: match_path(@match)
    )
  end
end
