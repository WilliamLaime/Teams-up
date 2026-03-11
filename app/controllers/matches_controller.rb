class MatchesController < ApplicationController
  # Retrouver le match avant les actions qui en ont besoin
  before_action :set_match, only: [:show, :edit, :update, :destroy]

  # GET /matches
  # Affiche uniquement les matchs à venir (passés exclus), triés par date puis heure
  # Accepte des paramètres de filtre : level, place, date, time, player_left, mine
  def index
    @matches = policy_scope(Match)
      .where("(date + time) > ?", Time.current)
      .order(date: :asc, time: :asc)

    # Recherche full-text — titre, ville, description ou email du créateur
    @matches = @matches.search_by_title_place_and_creator(params[:query]) if params[:query].present?
    # Filtre "Mes matchs" — seulement les matchs créés par l'utilisateur connecté
    @matches = @matches.where(user: current_user) if params[:mine].present? && user_signed_in?

    # Filtre par niveau (ex: "Débutant", "Intermédiaire", "Avancé")
    @matches = @matches.where(level: params[:level]) if params[:level].present?

    # Filtre par ville — recherche insensible à la casse (ILIKE = like sans casse en PostgreSQL)
    @matches = @matches.where("place ILIKE ?", "%#{params[:place]}%") if params[:place].present?

    # Filtre par date exacte (format attendu : YYYY-MM-DD)
    @matches = @matches.where(date: params[:date]) if params[:date].present?

    # Filtre par heure de début minimum (ex: afficher seulement les matchs à partir de 18h)
    @matches = @matches.where("time >= ?", params[:time_from]) if params[:time_from].present?

    # Filtre par nombre de places disponibles minimum
    @matches = @matches.where("player_left >= ?", params[:player_left].to_i) if params[:player_left].present?
  end

  # GET /matches/:id
  # Affiche le détail d'un match
  def show
    # Récupère les participants du match
    @match_users = @match.match_users.includes(:user)
    authorize @match

    # Vérifie si l'utilisateur connecté est déjà inscrit à ce match
    @current_match_user = @match.match_users.find_by(user: current_user)
  end

  # GET /matches/new
  # Affiche le formulaire de création avec des valeurs par défaut intelligentes
  def new
    @match = Match.new
    authorize @match

    # Date par défaut : aujourd'hui
    @match.date = Date.today

    # Heure par défaut : maintenant + 30 min, arrondie au prochain quart d'heure (00/15/30/45)
    future = Time.current + 30.minutes
    rounded_minutes = (future.min / 15.0).ceil * 15

    if rounded_minutes >= 60
      # Si le résultat dépasse 59 min, on passe à l'heure suivante
      @match.time = future.change(hour: future.hour + 1, min: 0, sec: 0)
    else
      @match.time = future.change(min: rounded_minutes, sec: 0)
    end
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
  # Supprime un match
  def destroy
    authorize @match
    @match.destroy
    redirect_to matches_path, notice: "Match supprimé."
  end

  private

  # Retrouve le match par son id dans les paramètres de l'URL
  def set_match
    @match = Match.find(params[:id])
  end

  # Liste blanche des paramètres autorisés pour créer/modifier un match
  def match_params
    params.require(:match).permit(:title, :description, :date, :time, :place, :level, :player_left, :validation_mode)
  end
end
