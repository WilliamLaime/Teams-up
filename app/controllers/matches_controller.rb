class MatchesController < ApplicationController
  # Permet aux visiteurs non connectés de voir la liste et le détail d'un match.
  # Les autres actions (créer, rejoindre, etc.) restent protégées par authenticate_user!
  skip_before_action :authenticate_user!, only: %i[index show]

  # Retrouver le match avant les actions qui en ont besoin
  before_action :set_match, only: %i[show edit update destroy calendar make_public]

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
      # Index public : uniquement les matchs ouverts à l'inscription et publics
      # visible_for_genre filtre les matchs "féminin" pour ne les montrer qu'aux femmes
      # includes évite les N+1 sur user/profil/sport chargés dans _match_card
      @matches = policy_scope(Match)
                 .includes(:sport, user: :profil)
                 .upcoming
                 .publicly_visible
                 .visible_for_genre(current_user)
                 .order(date: :asc, time: :asc)

      # 🔑 Appliquer les PRÉ-FILTRES ou les FILTRES MANUELS
      # Si l'user n'a modifié aucun filtre → utiliser ses préférences de profil
      # Sinon → appliquer les filtres qu'il a choisis
      if should_apply_prefilters?
        # Mémorise le total avant préfiltres pour afficher "X sur Y" dans le banner
        @total_matches_count = @matches.count
        apply_prefilters
        @filtered_matches_count = @matches.count
      else
        apply_filters
      end
    end

    # Meta tags pour la liste des matchs — description adaptée au sport actif si filtré
    sport_name = current_sport&.name
    set_meta_tags(
      title:       sport_name ? "Matchs de #{sport_name}" : "Trouver un match",
      description: sport_name \
        ? "Trouve et rejoins un match de #{sport_name} près de chez toi. Tous niveaux, toutes villes — inscris-toi en quelques secondes sur Teams-up." \
        : "Trouve et rejoins un match de sport amateur près de chez toi. Football, basket, tennis et plus — Teams-up."
    )
  end

  # GET /matches/:id
  # Affiche le détail d'un match
  def show
    # ── Contrôle d'accès pour les matchs privés ──────────────────────────────
    # Un match privé n'est accessible que :
    #   - Par l'organisateur (toujours)
    #   - Par quelqu'un ayant le bon token dans l'URL (?token=xxx)
    if @match.private?
      is_organizer    = user_signed_in? && @match.user == current_user
      has_valid_token = params[:token].present? && params[:token] == @match.private_token
      # Un participant déjà inscrit (peu importe le statut) peut toujours accéder au match
      is_participant  = user_signed_in? && @match.match_users.exists?(user: current_user)
      unless is_organizer || has_valid_token || is_participant
        skip_authorization
        redirect_to root_path, alert: "Ce match est privé. Vous avez besoin du lien d'invitation pour y accéder."
        return
      end
    end

    # Récupère les participants du match avec leur profil (évite les N+1 dans la vue)
    @match_users = @match.match_users.includes(user: :profil)
    authorize @match

    # Meta tags dynamiques — chaque match a son propre titre dans Google
    # Ex: "Match de Football — Partie du dimanche à Paris | Teams-up"
    sport_label = @match.sport&.name || "Sport"
    place_label = @match.place.present? ? " à #{@match.place}" : ""
    set_meta_tags(
      title:       "Match de #{sport_label} — #{@match.title}",
      description: "Rejoins ce match de #{sport_label}#{place_label} sur Teams-up. " \
                   "#{@match.title} — Niveau #{@match.level}. Inscris-toi en quelques secondes.",
      # noindex pour les matchs privés — ils ne doivent pas apparaître dans Google
      noindex:     @match.private?
    )

    # Si l'utilisateur n'est pas connecté, on mémorise l'URL du match.
    # Devise s'en servira pour rediriger automatiquement ici après la connexion.
    store_location_for(:user, match_path(@match)) unless user_signed_in?

    # Vérifie si l'utilisateur connecté est déjà inscrit à ce match
    @current_match_user = @match.match_users.find_by(user: current_user)

    # Vérifie si current_user est ami avec l'organisateur (pour afficher l'icône ami)
    if user_signed_in?
      organizer_user = @match_users.find { |mu| mu.role == "organisateur" }&.user
      @organizer_friend_status = organizer_user.present? &&
                                 current_user != organizer_user &&
                                 current_user.friends_with?(organizer_user)
    end

    # Calcule les avis en attente pour CE match (pour le bouton "Laisser un avis")
    # Conditions : match terminé + connecté + participant approuvé
    return unless user_signed_in? && @match.completed? && @current_match_user&.approved?

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
    return unless pending_ids.any? || can_vote_homme

    @match_pending_reviews = [{
      match: @match,
      users: User.where(id: pending_ids).includes(:profil),
      all_co_players: User.where(id: co_player_ids).includes(:profil),
      has_voted: has_voted,
      can_vote_homme: can_vote_homme
    }]
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
    @match.sport           = current_sport # Sport : pré-rempli avec le sport actif

    # Si on vient depuis une page équipe (?team_id=X), pré-associer l'équipe
    if params[:team_id].present?
      @match.team = Team.find_by(id: params[:team_id])
      # Un match d'équipe est privé par défaut
      @match.visibility = "private" if @match.team
    end

    # Équipes dont l'user est capitaine (pour le select dans le formulaire)
    @my_captained_teams = current_user.captained_teams.order(:name)
  end

  # POST /matches
  # Crée un nouveau match
  def create
    @match = Match.new(match_params)
    @match.user = current_user
    # Sécurité : seules les femmes peuvent créer un match "femme uniquement"
    # Si un non-femme envoie cette valeur (ex: via requête HTTP directe), on la remet à "tous"
    @match.genre_restriction = "tous" unless current_user.genre == "femme"

    # Si une équipe est associée, on force la visibilité à "private"
    if @match.team_id.present?
      # Vérifie que l'user est bien captain de cette équipe
      @match.team = Team.find_by(id: @match.team_id)
      unless @match.team&.captain?(current_user)
        @match.team = nil
        @match.team_id = nil
      end
      @match.visibility = "private" if @match.team
    end

    authorize @match

    if @match.save
      # Ajoute automatiquement le créateur comme organisateur approuvé du match
      @match.match_users.create(user: current_user, role: "organisateur", status: "approved")

      # Si c'est un match d'équipe, on pré-inscrit les autres membres en "pending"
      # Ils devront confirmer leur participation depuis la page du match
      invite_team_members if @match.team

      # 🎮 Vérifier les achievements liés à la création de match
      AchievementService.new(current_user).check(:match_created)

      # Email de confirmation avec récapitulatif du match pour l'organisateur
      UserMailer.match_created(@match).deliver_later

      # Planifie le rappel 24h avant le match pour tous les participants approuvés.
      # On vérifie qu'il reste plus de 24h avant le match pour éviter un job inutile
      # (ex: match créé à J-2h → le rappel serait déjà passé).
      reminder_time = @match.build_datetime - 24.hours
      MatchReminderJob.set(wait_until: reminder_time).perform_later(@match.id) if reminder_time > Time.current

      redirect_to @match, notice: "Match créé avec succès !"
    else
      @my_captained_teams = current_user.captained_teams.order(:name)
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
    # Sécurité : seules les femmes peuvent modifier un match en "femme uniquement"
    params[:match][:genre_restriction] = "tous" if params.dig(:match, :genre_restriction) == "feminin" && current_user.genre != "femme"
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

    # Notifie chaque participant en temps réel si il est sur la page du match,
    # et envoie un email transactionnel pour les utilisateurs absents.
    # IMPORTANT : on utilise deliver_now (pas deliver_later) car le match est
    # détruit juste après. Avec deliver_later, SolidQueue tente de désérialiser
    # le Match via GlobalID mais il n'existe plus en base → DeserializationError.
    participants.each do |mu|
      broadcast_match_cancelled_to_participant(mu.user)
      UserMailer.match_cancelled(@match, mu.user).deliver_now
    end

    @match.destroy
    redirect_to matches_path, notice: "Match supprimé."
  end

  # PATCH /matches/:id/make_public
  # Passe un match privé en public — réservé à l'organisateur
  def make_public
    authorize @match
    @match.update!(visibility: "public")
    redirect_to @match, notice: "Le match est maintenant ouvert au public !"
  end

  # GET /matches/:id/calendar
  # Génère et télécharge un fichier .ics pour ajouter le match à un calendrier externe
  # Compatible avec Google Calendar, Apple Calendar et Outlook
  def calendar
    authorize @match, :show?

    # Construit le datetime de début en combinant date + heure du match
    start_dt = Time.zone.local(
      @match.date.year, @match.date.month, @match.date.day,
      @match.time.hour, @match.time.min, 0
    )
    # Durée par défaut : 1h30
    end_dt = start_dt + 90.minutes

    # Lieu : venue ou adresse libre
    location = @match.place.presence || ""

    # Description enrichie pour le calendrier
    description = "Match #{@match.title} - Niveau : #{@match.level}"

    # Contenu du fichier ICS (format standard iCalendar)
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Teams-Up//Teams-Up//FR
      BEGIN:VEVENT
      UID:match-#{@match.id}@teamup
      DTSTART:#{start_dt.utc.strftime('%Y%m%dT%H%M%SZ')}
      DTEND:#{end_dt.utc.strftime('%Y%m%dT%H%M%SZ')}
      SUMMARY:#{@match.title}
      LOCATION:#{location}
      DESCRIPTION:#{description}
      END:VEVENT
      END:VCALENDAR
    ICS

    # Envoie le fichier au navigateur comme téléchargement
    send_data ics_content.strip,
              type: "text/calendar; charset=utf-8",
              disposition: "attachment",
              filename: "match-#{@match.id}.ics"
  end

  private

  # Envoie la notification d'annulation du match à un participant spécifique.
  # Appelé depuis destroy pour chaque participant avant la suppression du match.
  # La modal s'ouvre automatiquement peu importe la page où se trouve le joueur.
  def broadcast_match_cancelled_to_participant(participant_user)
    Turbo::StreamsChannel.broadcast_update_to(
      "user_#{participant_user.id}_notifications", # canal personnel du joueur
      target: "global_notification_container", # conteneur dans application.html.erb
      partial: "matches/match_cancelled_notification",
      locals: { match: @match }
    )
  end

  # Applique tous les filtres optionnels sur @matches selon les params reçus
  def apply_filters
    # Recherche full-text — titre, ville, description ou prénom/nom du créateur
    @matches = @matches.search_by_title_place_and_creator(params[:query]) if params[:query].present?

    # Filtre par sport :
    # - sport sélectionné dans l'URL → filtrer par ce sport
    # - Aucun param sport dans l'URL → fallback sur le sport actif de l'utilisateur
    sport_ids = params[:sport_ids]&.reject(&:blank?) || []
    if sport_ids.any?
      @matches = @matches.where(sport_id: sport_ids)
    elsif current_sport.present?
      @matches = @matches.where(sport_id: current_sport.id)
    end

    # Filtre par niveau
    @matches = @matches.where(level: params[:levels]) if params[:levels].present?

    # Filtre par ville — ILIKE = insensible à la casse (PostgreSQL)
    @matches = @matches.where("place ILIKE ?", "%#{params[:place]}%") if params[:place].present?

    # Filtre par date exacte (format YYYY-MM-DD)
    @matches = @matches.where(date: params[:date]) if params[:date].present?

    # Filtre par heure minimum (ex: matchs à partir de 18h)
    @matches = @matches.where("time >= ?", params[:time_from]) if params[:time_from].present?

    # Filtre par nombre de places disponibles minimum (> 0 pour ignorer un param vide converti en 0)
    @matches = @matches.where("player_left >= ?", params[:player_left].to_i) if params[:player_left].to_i > 0

    # Filtre "Mes lieux" — restreint aux venues favorites de l'utilisateur
    # Disponible comme filtre manuel pour combiner avec d'autres filtres (date, niveau, etc.)
    if params[:favorite_venues].present? && user_signed_in?
      venue_ids = current_user.profil&.favorite_venues&.pluck(:id)
      @matches = @matches.where(venue_id: venue_ids) if venue_ids&.any?
    end
  end

  # Vérifie si les pré-filtres doivent être appliqués
  # → True si l'utilisateur n'a modifié aucun filtre manuel ET est connecté
  # → False sinon (les filtres manuels prennent priorité)
  def should_apply_prefilters?
    return false unless user_signed_in?

    # Le lien "Voir tous les matchs" passe no_prefilter=1 pour contourner les pré-filtres
    return false if params[:no_prefilter].present?

    # Si l'utilisateur a modifié UN filtre → désactiver les pré-filtres
    params[:query].blank? &&
      params[:levels].blank? &&
      params[:place].blank? &&
      params[:date].blank? &&
      params[:time_from].blank? &&
      params[:player_left].blank? &&
      params[:sport_ids].blank? &&
      params[:favorite_venues].blank?
  end

  # Applique les pré-filtres intelligents basés sur les préférences du profil
  # Filtre automatiquement les matchs par :
  # 1. Ville préférée (if renseignée)
  # 2. Lieux favoris (if renseignés)
  # 3. Niveau de compétence pour le sport courant (if sport actif)
  def apply_prefilters
    profil = current_user.profil
    return unless profil  # Sécurité : pas de profil = pas de pré-filtres

    # Hashes pour tracker quels pré-filtres sont actifs (utilisés dans la vue)
    @active_prefilters = {}
    @prefilter_params = {}

    # 1️⃣ & 2️⃣ Pré-filtres : Ville préférée ET/OU Lieux favoris
    #
    # Logique :
    #   - Les deux renseignés → OR : matchs dans la ville OU dans un lieu favori
    #     (évite 0 résultats si le lieu favori est dans une autre ville que la ville préférée)
    #   - Seulement la ville → filtre par ville uniquement
    #   - Seulement les lieux → filtre par lieux uniquement
    has_city   = profil.preferred_city.present?
    has_venues = profil.favorite_venues.any?

    if has_city && has_venues
      # OR : on regroupe les deux conditions dans un seul WHERE
      venue_ids = profil.favorite_venues.pluck(:id)
      @matches = @matches.where(
        "place ILIKE ? OR venue_id IN (?)",
        "%#{profil.preferred_city}%",
        venue_ids
      )
      @active_prefilters[:city]   = true
      @active_prefilters[:venues] = true
      @prefilter_params[:city]    = profil.preferred_city
      @prefilter_params[:venues]  = profil.favorite_venues.pluck(:name)

    elsif has_city
      @matches = @matches.by_preferred_city(profil.preferred_city)
      @active_prefilters[:city] = true
      @prefilter_params[:city]  = profil.preferred_city

    elsif has_venues
      venue_ids = profil.favorite_venues.pluck(:id)
      @matches  = @matches.by_favorite_venues(venue_ids)
      @active_prefilters[:venues] = true
      @prefilter_params[:venues]  = profil.favorite_venues.pluck(:name)
    end

    # 3️⃣ Pré-filtre : Sport(s) pratiqués
    # - Sport actif → filtre sur ce sport + niveau de l'utilisateur
    # - Mode multisport (aucun sport actif) → filtre sur TOUS les sports pratiqués par l'user
    #   (évite de voir des matchs de sports qu'il ne pratique pas)
    if current_sport.present?
      # Un seul sport actif : filtre aussi par niveau si renseigné
      sport_profil = profil.sport_profils.find_by(sport_id: current_sport.id)
      if sport_profil&.level.present?
        @matches = @matches.by_user_level_for_sports(current_user.id, current_sport.id)
        @active_prefilters[:level] = true
        @prefilter_params[:level] = sport_profil.level
      end
    else
      # Mode multisport : restreindre aux sports que l'user pratique réellement
      user_sport_ids = current_user.sports.pluck(:id)
      if user_sport_ids.any?
        @matches = @matches.where(sport_id: user_sport_ids)
        @active_prefilters[:sports] = true
        @prefilter_params[:sports]  = current_user.sports.pluck(:name)
      end
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
    params.require(:match).permit(
      :title, :description, :date, :time, :place, :venue_id,
      :level, :player_left, :players_present, :validation_mode, :price_per_player,
      :sport_id, :format, :banner_image, :visibility,
      :genre_restriction, # Restriction de genre : "tous" ou "feminin"
      :team_id            # Équipe organisatrice (optionnel)
    )
  end

  # Pré-inscrit tous les membres de l'équipe (sauf le captain/créateur) en "pending"
  # Envoie une notification à chaque membre pour les prévenir
  def invite_team_members
    @match.team.members.where.not(id: current_user.id).each do |member|
      @match.match_users.create(user: member, role: "joueur", status: "pending")
      Notification.create(
        user:    member,
        message: "📅 #{@match.team.name} a un nouveau match : \"#{@match.title}\". Confirme ta présence !",
        link:    match_path(@match)
      )
    end
  end
end
