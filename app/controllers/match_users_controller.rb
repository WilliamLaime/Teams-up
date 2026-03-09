class MatchUsersController < ApplicationController
  # Retrouver le match parent avant chaque action
  before_action :set_match
  # Retrouver l'inscription spécifique pour approve, reject et destroy
  before_action :set_match_user, only: [:destroy, :approve, :reject]

  # POST /matches/:match_id/match_users
  # Rejoindre un match
  def create
    # Vérifie si l'utilisateur est déjà inscrit à ce match
    if @match.match_users.exists?(user: current_user)
      redirect_to @match, alert: "Tu es déjà inscrit à ce match."
      return
    end

    @match_user = @match.match_users.new(user: current_user, role: "joueur")

    if @match.manual_validation?
      # Mode manuel : le joueur est en attente de validation par l'organisateur
      @match_user.status = "pending"
      @match_user.save

      # Notifie l'organisateur qu'un joueur veut rejoindre
      notify_organizer("#{current_user.email} veut rejoindre votre match \"#{@match.title}\"")

      redirect_to @match, notice: "Ta demande a été envoyée à l'organisateur !"
    else
      # Mode automatique : le joueur est accepté immédiatement
      @match_user.status = "approved"
      if @match_user.save
        # Décrémente le nombre de places disponibles
        @match.decrement!(:player_left)

        # Notifie l'organisateur qu'un joueur a rejoint
        notify_organizer("#{current_user.email} a rejoint votre match \"#{@match.title}\"")

        redirect_to @match, notice: "Tu as rejoint le match !"
      else
        redirect_to @match, alert: "Impossible de rejoindre le match."
      end
    end
  end

  # DELETE /matches/:match_id/match_users/:id
  # Quitter un match
  def destroy
    # Vérifie que l'utilisateur peut seulement quitter sa propre inscription
    unless @match_user.user == current_user
      redirect_to @match, alert: "Action non autorisée."
      return
    end

    # Si le joueur était approuvé, on lui restitue sa place
    if @match_user.approved?
      @match.increment!(:player_left)
    end

    @match_user.destroy
    redirect_to @match, notice: "Tu as quitté le match."
  end

  # PATCH /matches/:match_id/match_users/:id/approve
  # Approuver un joueur (réservé à l'organisateur)
  def approve
    unless current_user_is_organizer?
      redirect_to @match, alert: "Seul l'organisateur peut approuver des joueurs."
      return
    end

    @match_user.update(status: "approved")
    @match.decrement!(:player_left)

    # Notifie le joueur que sa demande a été acceptée
    notify_player(@match_user.user, "✅ Ta demande pour \"#{@match.title}\" a été acceptée !")

    redirect_to @match, notice: "#{@match_user.user.email} a été approuvé !"
  end

  # PATCH /matches/:match_id/match_users/:id/reject
  # Rejeter un joueur (réservé à l'organisateur)
  def reject
    unless current_user_is_organizer?
      redirect_to @match, alert: "Seul l'organisateur peut rejeter des joueurs."
      return
    end

    @match_user.update(status: "rejected")

    # Notifie le joueur que sa demande a été refusée
    notify_player(@match_user.user, "❌ Ta demande pour \"#{@match.title}\" a été refusée.")

    redirect_to @match, notice: "#{@match_user.user.email} a été refusé."
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

  # Vérifie si l'utilisateur connecté est l'organisateur du match
  def current_user_is_organizer?
    @match.match_users.exists?(user: current_user, role: "organisateur")
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
