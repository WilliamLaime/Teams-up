class TournamentsController < ApplicationController
  include Pagy::Backend

  # Liste et détail accessibles aux visiteurs non connectés (comme les matchs).
  # coming_soon : page d'attente publique (la feature tournoi n'est pas encore lancée).
  skip_before_action :authenticate_user!, only: %i[index show coming_soon]

  before_action :set_tournament, only: %i[show start edit update toggle_registrations finish]

  # Associations préchargées pour les cards (sport, avatars des participants,
  # organisateur) — appliquées uniquement à l'onglet actif (cf. #index), jamais
  # aux requêtes de comptage.
  CARD_INCLUDES = [
    :sport,
    { user: { profil: { avatar_attachment: :blob } } },
    { tournament_users: { user: { profil: { avatar_attachment: :blob } } } }
  ].freeze

  # Onglets de la page liste (cf. docs/TOURNOI.md).
  TABS = %i[mine join ongoing completed].freeze

  # Tant que la feature tournoi est en chantier, on empêche son indexation par les
  # moteurs de recherche (cf. layout application.html.erb + robots.txt). Les devs
  # accèdent aux pages via l'URL directe ; seul le header pointe vers coming_soon.
  before_action :mark_noindex

  # GET /tournois
  # Un seul onglet affiché à la fois (cf. TABS), paginé — cf. docs/TOURNOI.md :
  #   mine      → inscrit + non terminé
  #   join      → inscriptions ouvertes, non inscrit, non complet
  #   ongoing   → lancés, non inscrit (lecture seule)
  #   completed → clôturés, tous (lecture seule)
  def index
    filtered    = filtered_tournaments
    my_ids      = my_tournament_ids
    @tab_counts = tab_counts(filtered, my_ids)
    @active_tab = resolve_active_tab(@tab_counts)
    @pagy, @tournaments = pagy(
      tab_scope(filtered, @active_tab, my_ids).includes(CARD_INCLUDES),
      limit: 9
    )

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
      # Vrai tirage au sort : mélange l'ordre des joueurs une fois pour toutes, AVANT
      # de générer la première ronde/journée — sinon SwissPairing/LeagueBuilder/
      # PoolBuilder retombent sur l'ordre d'inscription (id) et le premier tour est
      # toujours "J1 vs J2, J3 vs J4…".
      assign_draw_order!
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

    # Destinations Slack pour le partage optionnel (vide si le compte n'est pas lié)
    @slack_destinations = slack_destinations_for(current_user)
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

      # Partage Slack : uniquement si l'organisateur a coché la case dans le formulaire.
      if params[:post_to_slack].present? && current_user.slack_linked?
        SlackNotifyJob.perform_later("Tournament", @tournament.id, current_user.id,
                                     params[:slack_channel_id].presence,
                                     params[:slack_workspace_id].presence)
      end

      redirect_to tournament_path(@tournament), notice: "Tournoi créé."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /tournois/:id/edit
  # Réutilise le même formulaire que la création (_form.html.erb). Ouvert à
  # l'organisateur ET aux co-organisateurs (cf. TournamentPolicy#update?).
  def edit
    authorize @tournament
  end

  # PATCH /tournois/:id
  # Les champs structurels (format, nb de joueurs, sport) sont verrouillés une
  # fois le tournoi lancé, pour ne pas corrompre le tirage/tableau en cours.
  def update
    authorize @tournament

    assign_registration_deadline

    if @tournament.update(tournament_params)
      redirect_to tournament_path(@tournament), notice: "Tournoi mis à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # PATCH /tournois/:id/toggle_registrations
  # Clôture ou rouvre les inscriptions manuellement, avant le lancement.
  def toggle_registrations
    authorize @tournament, :toggle_registrations?

    case @tournament.status
    when "open"
      @tournament.update!(status: "closed")
      redirect_to tournament_path(@tournament), notice: "Inscriptions closes."
    when "closed"
      @tournament.update!(status: "open")
      redirect_to tournament_path(@tournament), notice: "Inscriptions rouvertes."
    else
      redirect_to tournament_path(@tournament), alert: "Impossible de changer les inscriptions à ce stade."
    end
  end

  # PATCH /tournois/:id/finish
  # Termine le tournoi manuellement (abandon ou fin anticipée), en plus de la
  # fin automatique posée par BracketBuilder en fin de tableau.
  def finish
    authorize @tournament, :finish?

    if @tournament.completed?
      redirect_to tournament_path(@tournament), alert: "Ce tournoi est déjà terminé."
    else
      @tournament.update!(status: "completed")
      redirect_to tournament_path(@tournament), notice: "Tournoi terminé."
    end
  end

  # GET /tournois/search?q=...
  # Autocomplete JSON pour désigner un co-organisateur (même pattern que
  # TeamInvitationsController#search).
  def search
    authorize Tournament, :search?

    q = params[:q].to_s.strip
    return render json: [] if q.length < 3

    users = User.search_for_invite(q)
                .where.not(id: current_user.id)
                .limit(8)

    render json: users.map { |u|
      { sgid: u.invite_sgid, first_name: u.profil&.first_name, last_name: u.profil&.last_name }
    }
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:id])
  end

  # Tirage au sort : fige un ordre aléatoire (draw_order) sur les joueurs inscrits,
  # une seule fois, au moment du lancement. Cet ordre remplace ensuite l'id
  # (ordre d'inscription) partout où SwissPairing/LeagueBuilder/PoolBuilder/
  # Tournament#rank_key avaient besoin d'un départage neutre.
  def assign_draw_order!
    @tournament.tournament_users.players.approved.to_a.shuffle.each_with_index do |tu, index|
      tu.update_column(:draw_order, index)
    end
  end

  # Base filtrée (policy_scope + sport + recherche), SANS eager loading : sert à
  # la fois aux comptages légers (#tab_counts) et à la requête finale paginée.
  def filtered_tournaments
    scope = policy_scope(Tournament)
    scope = scope.where(sport: Sport.find_by(slug: params[:sport])) if params[:sport].present?
    scope = scope.search_by_name(params[:query]) if params[:query].present?
    scope
  end

  # IDs des tournois où l'utilisateur courant est inscrit (1 requête, réutilisée).
  def my_tournament_ids
    return [] unless user_signed_in?

    current_user.tournament_users.pluck(:tournament_id)
  end

  # Compteurs légers par onglet (COUNT seul, pas d'eager loading) — servent aux
  # badges de la barre d'onglets et à déterminer l'onglet par défaut.
  def tab_counts(scope, my_ids)
    {
      mine: user_signed_in? ? scope.not_completed.where(id: my_ids).count : 0,
      join: scope.open_for_registration.where.not(id: my_ids).not_full.count,
      ongoing: scope.in_progress.where.not(id: my_ids).count,
      completed: scope.completed.count
    }
  end

  # Un ?tab= explicite (même vide) est toujours honoré tel quel, pour qu'un lien
  # direct/partagé vers un onglet vide affiche le bon état vide. Sans paramètre,
  # on prend le premier onglet non vide (mine en priorité si connecté).
  def resolve_active_tab(counts)
    requested = params[:tab].to_s.to_sym
    return requested if TABS.include?(requested) && (requested != :mine || user_signed_in?)

    TABS.find { |t| (t != :mine || user_signed_in?) && counts[t].positive? } ||
      (user_signed_in? ? :mine : :join)
  end

  def tab_scope(scope, tab, my_ids)
    case tab
    when :mine      then scope.not_completed.where(id: my_ids).order(date: :asc)
    when :join      then scope.open_for_registration.where.not(id: my_ids).not_full.order(date: :asc)
    when :ongoing   then scope.in_progress.where.not(id: my_ids).order(date: :asc)
    when :completed then scope.completed.order(date: :desc)
    end
  end

  # Marque la page comme non-indexable (voir <meta robots> dans le layout).
  def mark_noindex
    @noindex = true
  end

  # Verrouille format/nb de joueurs/sport/playoffs et les réglages de structure
  # (Lot 7) une fois le tournoi lancé : ces champs pilotent le moteur de jeu
  # (TournamentEngine) et casseraient un tirage/tableau déjà en cours s'ils
  # changeaient sous le pied de la mécanique.
  STRUCTURAL_FIELDS = %i[
    sport_id format max_players playoffs
    players_per_pool bracket_size swiss_wins_to_qualify swiss_losses_to_eliminate
  ].freeze

  def tournament_params
    permitted = %i[name description date time place venue_id banner_image] + STRUCTURAL_FIELDS
    permitted -= STRUCTURAL_FIELDS if @tournament&.persisted? && (@tournament.in_progress? || @tournament.completed?)

    params.require(:tournament).permit(*permitted)
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

  # Désigne un co-organisateur si un joueur a été choisi dans l'autocomplete.
  # On reçoit un identifiant signé (voir User#invite_sgid) et non un email : aucune
  # adresse ne circule dans le formulaire de création de tournoi.
  def add_co_organizer
    co_org = User.find_by_invite_sgid(params[:co_organizer_sgid])
    return if co_org.nil? || co_org == current_user

    @tournament.tournament_users.create(user: co_org, role: "co_organisateur", status: "approved")
  end

  # Inscrit le créateur comme joueur uniquement s'il a coché le toggle dédié.
  def register_creator_if_requested
    return unless ActiveModel::Type::Boolean.new.cast(params[:self_register])

    @tournament.tournament_users.create(user: current_user, role: "joueur", status: "approved")
  end
end
