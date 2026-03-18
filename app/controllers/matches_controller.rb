class MatchesController < ApplicationController
  # Retrouver le match avant les actions qui en ont besoin
  before_action :set_match, only: [:show, :edit, :update, :destroy]

  # GET /matches
  # Deux modes :
  #   - ?mine=1 → historique personnel (matchs en cours + terminés de l'user)
  #   - par défaut → index public (matchs ouverts à l'inscription, ≥ 30 min)
  def index
    if params[:mine].present? && user_signed_in?
      # Historique : TOUS les matchs de l'user (participants ou organisateur), triés du plus récent
      @matches = policy_scope(Match)
        .where(id: current_user.match_users.select(:match_id))
        .order(date: :desc, time: :desc)

      # Filtre statut :
      #   ?status=completed → matchs terminés (> 1h après le début)
      #   par défaut        → matchs "en cours" (pas encore terminés)
      if params[:status] == "completed"
        @matches = @matches.completed
      else
        @matches = @matches.active_for_user
      end
    else
      # Index public : uniquement les matchs ouverts à l'inscription
      @matches = policy_scope(Match).upcoming.order(date: :asc, time: :asc)
      apply_filters
    end
  end

  # GET /matches/:id
  # Affiche le détail d'un match
  def show
    # Récupère les participants du match avec leur profil (évite les N+1 dans la vue)
    @match_users = @match.match_users.includes(user: :profil)
    authorize @match

    # Vérifie si l'utilisateur connecté est déjà inscrit à ce match
    @current_match_user = @match.match_users.find_by(user: current_user)

    # Calcule les avis en attente pour CE match (pour le bouton "Laisser un avis")
    # Conditions : match terminé + connecté + participant approuvé
    if user_signed_in? && @match.completed? && @current_match_user&.approved?
      # Co-joueurs approuvés dans ce match (sauf current_user)
      co_player_ids = @match.match_users
                            .where(status: "approved")
                            .where.not(user_id: current_user.id)
                            .pluck(:user_id)

      # Joueurs déjà notés par current_user dans CE match
      already_reviewed = Avis.where(reviewer_id: current_user.id, match_id: @match.id)
                             .pluck(:reviewed_user_id)

      # Joueurs pas encore notés
      pending_ids    = co_player_ids - already_reviewed
      has_voted      = MatchVote.where(voter_id: current_user.id, match_id: @match.id).exists?
      can_vote_homme = !has_voted && co_player_ids.any?

      # On prépare les données seulement s'il reste quelque chose à faire
      if pending_ids.any? || can_vote_homme
        @match_pending_reviews = [{
          match:          @match,
          users:          User.where(id: pending_ids).includes(:profil),
          all_co_players: User.where(id: co_player_ids).includes(:profil),
          has_voted:      has_voted,
          can_vote_homme: can_vote_homme
        }]
      end
    end
  end

  # GET /matches/new
  # Affiche le formulaire de création avec des valeurs par défaut intelligentes
  def new
    @match = Match.new
    authorize @match

    # Valeurs par défaut explicites
    @match.date            = Date.today        # Date : aujourd'hui
    @match.player_left     = 4                 # Joueurs manquants : 4 par défaut
    @match.validation_mode = "automatic"       # Validation : automatique par défaut
    @match.time            = default_match_time # Heure : +30 min arrondie au quart d'heure
    @match.sport           = current_sport     # Sport : pré-rempli avec le sport actif
  end

  # POST /matches
  # Crée un nouveau match
  def create
    @match = Match.new(match_params)
    @match.user = current_user
    authorize @match

    if @match.save
      # Ajoute automatiquement le créateur comme organisateur approuvé du match
      # status: "approved" car l'organisateur est automatiquement accepté dans son propre match
      @match.match_users.create(user: current_user, role: "organisateur", status: "approved")
      redirect_to @match, notice: "Match créé avec succès !"
    else
      # En cas d'erreur, réaffiche le formulaire
      render :new, status: :unprocessable_entity
    end
  end

  # GET /matches/:id/edit
  # Affiche le formulaire de modification d'un match
  def edit
    authorize @match
  end

  # PATCH/PUT /matches/:id
  # Met à jour un match existant
  def update
    authorize @match
    if @match.update(match_params)
      redirect_to @match, notice: "Match mis à jour avec succès !"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /matches/:id
  # Supprime un match et notifie tous les participants en temps réel
  def destroy
    authorize @match

    # Récupère tous les participants inscrits (hors organisateur) avant destruction.
    # On exclut les "rejected" car ils n'ont plus de place et ne sont plus actifs.
    # IMPORTANT : on broadcast AVANT @match.destroy → le canal ActionCable doit encore exister.
    participants = @match.match_users
      .where.not(role: "organisateur")
      .where(status: ["approved", "pending", "waiting"])
      .includes(:user)

    # Notifie chaque participant en temps réel si il est sur la page du match
    participants.each do |mu|
      broadcast_match_cancelled_to_participant(mu.user)
    end

    @match.destroy
    redirect_to matches_path, notice: "Match supprimé."
  end

  private

  # Envoie la notification d'annulation du match à un participant spécifique.
  # Appelé depuis destroy pour chaque participant avant la suppression du match.
  # Si le joueur est sur la page du match, une modal s'ouvre automatiquement
  # et le redirige vers la liste des matchs.
  def broadcast_match_cancelled_to_participant(participant_user)
    Turbo::StreamsChannel.broadcast_update_to(
      "match_#{@match.id}_participant_#{participant_user.id}", # canal personnel du joueur
      target: "match_cancelled_notification_container",        # conteneur dans show.html.erb
      partial: "matches/match_cancelled_notification",
      locals: { match: @match }
    )
  end

  # Applique tous les filtres optionnels sur @matches selon les params reçus
  def apply_filters
    # Recherche full-text — titre, ville, description ou prénom/nom du créateur
    @matches = @matches.search_by_title_place_and_creator(params[:query]) if params[:query].present?

    # Filtre par niveau — accepte plusieurs valeurs (WHERE level IN ('...', '...'))
    @matches = @matches.where(level: params[:levels]) if params[:levels].present?

    # Filtre par ville — ILIKE = insensible à la casse (PostgreSQL)
    @matches = @matches.where("place ILIKE ?", "%#{params[:place]}%") if params[:place].present?

    # Filtre par date exacte (format YYYY-MM-DD)
    @matches = @matches.where(date: params[:date]) if params[:date].present?

    # Filtre par heure minimum (ex: matchs à partir de 18h)
    @matches = @matches.where("time >= ?", params[:time_from]) if params[:time_from].present?

    # Filtre par nombre de places disponibles minimum
    @matches = @matches.where("player_left >= ?", params[:player_left].to_i) if params[:player_left].present?

    # Filtre par sport :
    # - Si des sports sont sélectionnés dans les filtres (multi-select) → filtrer par ces sports
    # - Sinon, pré-filtrer automatiquement par le sport actif de l'utilisateur
    if params[:sport_ids].present?
      @matches = @matches.where(sport_id: params[:sport_ids])
    elsif current_sport.present?
      @matches = @matches.where(sport_id: current_sport.id)
    end
  end

  # Calcule l'heure par défaut : maintenant + 30 min, arrondie au prochain quart d'heure
  def default_match_time
    future = Time.current + 30.minutes
    rounded_minutes = (future.min / 15.0).ceil * 15

    if rounded_minutes >= 60
      future.change(hour: future.hour + 1, min: 0, sec: 0)
    else
      future.change(min: rounded_minutes, sec: 0)
    end
  end

  # Retrouve le match par son id dans les paramètres de l'URL
  def set_match
    @match = Match.find(params[:id])
  end

  # Liste blanche des paramètres autorisés pour créer/modifier un match
  def match_params
    params.require(:match).permit(:title, :description, :date, :time, :place, :venue_id, :level, :player_left, :validation_mode, :price_per_player, :sport_id, :format, :banner_image)
  end
end
