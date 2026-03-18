class MatchUsersController < ApplicationController
  # Retrouver le match parent avant chaque action
  before_action :set_match
  # Retrouver l'inscription spécifique pour approve, reject et destroy
  before_action :set_match_user, only: [:destroy, :approve, :reject]

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

    # On récupère l'organisateur une seule fois pour les notifications
    organizer = @match.organizer_match_user&.user

    # Redirige vers le bon cas selon l'état du match
    if @match.full?
      join_waiting_list(organizer)
    elsif @match.manual_validation?
      join_with_manual_validation(organizer)
    else
      join_automatically(organizer)
    end
  end

  # DELETE /matches/:match_id/match_users/:id
  # Quitter un match — si quelqu'un est en file d'attente, il est promu automatiquement
  def destroy
    authorize @match_user

    # Si le joueur avait une place approuvée, on gère la file d'attente
    promote_next_in_line if @match_user.approved?

    @match_user.destroy
    redirect_to @match, notice: "Tu as quitté le match."
  end

  # PATCH /matches/:match_id/match_users/:id/approve
  # Approuver un joueur (réservé à l'organisateur via Pundit)
  def approve
    authorize @match_user
    @match_user.update(status: "approved")
    @match.decrement!(:player_left)
    notify(@match_user.user, "✅ Ta demande pour \"#{@match.title}\" a été acceptée !")
    redirect_to @match, notice: "#{@match_user.user.display_name} a été approuvé !"
  end

  # PATCH /matches/:match_id/match_users/:id/reject
  # Rejeter un joueur (réservé à l'organisateur via Pundit)
  def reject
    authorize @match_user
    @match_user.update(status: "rejected")
    notify(@match_user.user, "❌ Ta demande pour \"#{@match.title}\" a été refusée.")
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

  # Envoie une notification à un utilisateur donné
  # Si user est nil (ex: organisateur introuvable), on ne fait rien
  def notify(user, message)
    return unless user

    Notification.create(user: user, message: message, link: match_path(@match))
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
    else
      # Personne en attente : on rend la place disponible
      @match.increment!(:player_left)
    end
  end

  # Cas 1 : Le match est complet → mise en file d'attente
  def join_waiting_list(organizer)
    @match_user.status = "waiting"
    if @match_user.save
      notify(organizer, "#{current_user.display_name} s'est inscrit en file d'attente pour \"#{@match.title}\"")
      redirect_to @match, notice: "Le match est complet. Tu as été ajouté à la file d'attente !"
    else
      redirect_to @match, alert: "Impossible de rejoindre la file d'attente."
    end
  end

  # Cas 2 : Validation manuelle → en attente de l'organisateur
  def join_with_manual_validation(organizer)
    @match_user.status = "pending"
    @match_user.save
    notify(organizer, "#{current_user.display_name} veut rejoindre votre match \"#{@match.title}\"")
    redirect_to @match, notice: "Ta demande a été envoyée à l'organisateur !"
  end

  # Cas 3 : Validation automatique → accepté immédiatement
  def join_automatically(organizer)
    @match_user.status = "approved"
    if @match_user.save
      @match.decrement!(:player_left)
      notify(organizer, "#{current_user.display_name} a rejoint votre match \"#{@match.title}\"")
      # flash[:show_calendar_modal] déclenche la modale "Demande acceptée" dans show.html.erb
      flash[:show_calendar_modal] = true
      redirect_to @match
    else
      redirect_to @match, alert: "Impossible de rejoindre le match."
    end
  end
end
