class TournamentsController < ApplicationController
  include Pagy::Backend

  # Liste et détail accessibles aux visiteurs non connectés (comme les matchs).
  # coming_soon : page d'attente publique (la feature tournoi n'est pas encore lancée).
  skip_before_action :authenticate_user!, only: %i[index show coming_soon]

  before_action :set_tournament, only: %i[show start]

  # Tant que la feature tournoi est en chantier, on empêche son indexation par les
  # moteurs de recherche (cf. layout application.html.erb + robots.txt). Les devs
  # accèdent aux pages via l'URL directe ; seul le header pointe vers coming_soon.
  before_action :mark_noindex

  # GET /tournois
  # Trois sections (cf. docs/TOURNOI.md) :
  #   1. Mes tournois en cours   → inscrit + non terminé
  #   2. Tournois à rejoindre     → inscriptions ouvertes, non inscrit
  #   3. Tournois en cours publics → lancés, non inscrit (lecture seule)
  def index
    # Base : tournois visibles (policy_scope) + eager loading pour éviter les N+1
    # sur les cartes (sport, avatars des participants, organisateur).
    scope = policy_scope(Tournament)
            .includes(:sport,
                      { user: { profil: { avatar_attachment: :blob } } },
                      { tournament_users: { user: { profil: { avatar_attachment: :blob } } } })

    # Filtre par sport (slug) et recherche full-text (barre de recherche).
    scope = scope.where(sport: Sport.find_by(slug: params[:sport])) if params[:sport].present?
    scope = scope.search_by_name(params[:query]) if params[:query].present?

    # IDs des tournois où l'utilisateur courant est inscrit (1 requête, réutilisée).
    my_ids = user_signed_in? ? current_user.tournament_users.pluck(:tournament_id) : []

    # 1. Mes tournois en cours (masqué si déconnecté)
    @my_tournaments = user_signed_in? ? scope.not_completed.where(id: my_ids).order(date: :asc) : []

    # 2. Tournois à rejoindre : inscriptions ouvertes, non inscrit
    @tournaments_to_join = scope.open_for_registration
                                .where.not(id: my_ids)
                                .order(date: :asc)
                                .reject(&:full?) # complet → plus "à rejoindre"

    # 3. Tournois en cours publics (non inscrit) → visualisation seule
    @ongoing_tournaments = scope.in_progress.where.not(id: my_ids).order(date: :asc)

    # Liste des sports pour les filtres pill de la barre.
    @sports = Sport.order(:name)
  end

  # GET /tournois/bientot
  # Page d'attente publique affichée depuis le header tant que la feature tournoi
  # n'est pas officiellement lancée. Les vraies pages (/tournois) restent
  # accessibles par URL directe pour permettre aux développeurs de travailler.
  def coming_soon
    authorize Tournament, :coming_soon?
  end

  # GET /tournois/:id
  # Affiche le tableau : rondes suisses + tableau final (Lot 3).
  def show
    authorize @tournament
  end

  # POST /tournois/:id/start
  # Lance le tournoi : passe en "in_progress" et génère la première ronde suisse.
  # Réservé à l'organisateur (admin ou co-organisateur).
  def start
    authorize @tournament, :start?

    unless @tournament.startable?
      redirect_to tournament_path(@tournament),
                  alert: "Impossible de lancer : il faut au moins #{Tournament::MIN_PLAYERS_TO_START} joueurs inscrits et des inscriptions ouvertes."
      return
    end

    ActiveRecord::Base.transaction do
      @tournament.update!(status: "in_progress")
      # Aiguillage selon le format (ronde suisse / championnat / poules).
      TournamentEngine.for(@tournament).next_round!
    end

    respond_to do |format|
      format.turbo_stream # start.turbo_stream.erb : remplace le board + déclenche le tirage
      format.html { redirect_to tournament_path(@tournament), notice: "Tournoi lancé, le tirage est fait !" }
    end
  end

  # GET /tournois/new
  # Formulaire de création (sport → format → paramètres → récapitulatif).
  def new
    @tournament = Tournament.new(
      date: Date.current,
      sport: current_sport || Sport.order(:name).first
    )
    authorize @tournament
  end

  # POST /tournois
  # Le créateur devient l'admin (tournament.user) mais n'est PAS inscrit comme
  # joueur, sauf s'il l'a explicitement demandé (toggle self_register).
  def create
    @tournament = Tournament.new(tournament_params)
    @tournament.user   = current_user
    @tournament.status = "open"
    authorize @tournament

    assign_registration_deadline

    if @tournament.save
      add_co_organizer
      register_creator_if_requested
      redirect_to tournament_path(@tournament), notice: "Tournoi créé."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /tournois/search?q=...
  # Autocomplete JSON pour désigner un co-organisateur (même pattern que
  # TeamInvitationsController#search).
  def search
    authorize Tournament, :search?

    q = params[:q].to_s.strip
    return render json: [] if q.length < 3

    users = User.joins(:profil)
                .where("profils.first_name ILIKE ? OR users.email ILIKE ?", "%#{q}%", "%#{q}%")
                .where.not(id: current_user.id)
                .includes(:profil)
                .limit(8)

    render json: users.map { |u|
      { email: u.email, first_name: u.profil&.first_name, last_name: u.profil&.last_name }
    }
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:id])
  end

  # Marque la page comme non-indexable (voir <meta robots> dans le layout).
  def mark_noindex
    @noindex = true
  end

  def tournament_params
    params.require(:tournament).permit(
      :name, :description, :sport_id, :format, :max_players,
      :date, :time, :place, :venue_id, :banner_image
    )
  end

  # La deadline (datetime) est saisie via un date-picker + deux time-pickers
  # (heure / minute) → params virtuels combinés ici. On évite ainsi le
  # multiparameter datetime de Rails. Sans heure choisie → fin de journée (23:59).
  def assign_registration_deadline
    date = params[:deadline_date].to_s.strip
    return if date.blank?

    hour = params[:deadline_hour].presence || "23"
    min  = params[:deadline_min].presence  || "59"
    @tournament.registration_deadline = Time.zone.parse("#{date} #{hour}:#{min}")
  rescue ArgumentError
    # Date/heure invalide → on laisse la deadline nulle plutôt que de planter.
    @tournament.registration_deadline = nil
  end

  # Désigne un co-organisateur si un email valide a été choisi dans l'autocomplete.
  def add_co_organizer
    email = params[:co_organizer_email].to_s.strip
    return if email.blank?

    co_org = User.find_by(email: email)
    return if co_org.nil? || co_org == current_user

    @tournament.tournament_users.create(user: co_org, role: "co_organisateur", status: "approved")
  end

  # Inscrit le créateur comme joueur uniquement s'il a coché le toggle dédié.
  def register_creator_if_requested
    return unless ActiveModel::Type::Boolean.new.cast(params[:self_register])

    @tournament.tournament_users.create(user: current_user, role: "joueur", status: "approved")
  end
end
