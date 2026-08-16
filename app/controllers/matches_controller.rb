class MatchesController < ApplicationController
  # Pagination serveur de la liste des matchs (évite de charger tous les matchs
  # + leurs avatars préchargés d'un coup — indispensable à la montée en charge).
  include Pagy::Backend

  # Permet aux visiteurs non connectés de voir la liste et le détail d'un match.
  # Les autres actions (créer, rejoindre, etc.) restent protégées par authenticate_user!
  skip_before_action :authenticate_user!, only: %i[index show]

  # Retrouver le match avant les actions qui en ont besoin
  before_action :set_match, only: %i[show edit update destroy calendar make_public share_on_slack]

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
      # match_users préchargé pour afficher le statut de participation dans la card
      @matches = policy_scope(Match)
                 .includes(:sport,
                           { user: { profil: { avatar_attachment: :blob } } },
                           { match_users: { user: { profil: { avatar_attachment: :blob } } } })
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

    # Pagination : 12 matchs par page (3 colonnes × 4 lignes sur desktop).
    # Appliquée en dernier, après tous les filtres, pour ne charger et ne
    # précharger (avatars, sport…) que les matchs réellement affichés.
    # Pagy conserve automatiquement les paramètres de filtre dans les liens.
    @pagy, @matches = pagy(@matches, limit: 12)

    # Meta tags pour la liste des matchs — description adaptée au sport actif si filtré
    sport_name = current_sport&.name
    set_meta_tags(
      title: sport_name ? "Matchs de #{sport_name}" : "Trouver un match",
      description: if sport_name
                     "Trouve et rejoins un match de #{sport_name} près de chez toi. " \
                       "Tous niveaux, toutes villes — inscris-toi en quelques secondes sur Teams-up."
                   else
                     "Trouve et rejoins un match de sport amateur près de chez toi. " \
                       "Football, basket, tennis et plus — Teams-up."
                   end
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

    # Récupère les participants du match avec leur profil (évite les N+1 dans la vue).
    # `displayed_match_users` = tous les inscrits, SAUF sur une confrontation de
    # tournoi où seuls les deux adversaires sont montrés : l'organisateur qui a
    # planifié la rencontre sans y jouer n'a pas à figurer dans un 1v1.
    @match_users = @match.displayed_match_users.includes(user: :profil)
    authorize @match

    # Meta tags dynamiques — chaque match a son propre titre dans Google
    # Ex: "Match de Football — Partie du dimanche à Paris | Teams-up"
    sport_label = @match.sport&.name || "Sport"
    place_label = @match.place.present? ? " à #{@match.place}" : ""
    set_meta_tags(
      title: "Match de #{sport_label} — #{@match.title}",
      description: "Rejoins ce match de #{sport_label}#{place_label} sur Teams-up. " \
                   "#{@match.title} — Niveau #{@match.level}. Inscris-toi en quelques secondes.",
      # noindex pour les matchs privés — ils ne doivent pas apparaître dans Google
      noindex: @match.private?
    )

    # Si l'utilisateur n'est pas connecté, on mémorise l'URL du match.
    # Devise s'en servira pour rediriger automatiquement ici après la connexion.
    store_location_for(:user, match_path(@match)) unless user_signed_in?

    # Vérifie si l'utilisateur connecté est déjà inscrit à ce match
    @current_match_user = @match.match_users.find_by(user: current_user)

    # Vérifie si current_user est ami avec l'organisateur (pour afficher l'icône ami)
    if user_signed_in?
      # L'organisateur vient du match lui-même, et non de @match_users : sur une
      # confrontation de tournoi il peut avoir été écarté de la liste affichée.
      organizer_user = @match.user
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
    @match.players_needed  = 4                 # Joueurs recherchés : 4 par défaut
    @match.validation_mode = "automatic"       # Validation : automatique par défaut
    @match.time            = default_match_time # Heure : +30 min arrondie au quart d'heure
    @match.end_time        = @match.time + 1.hour # Fin : 1h après le début par défaut (modifiable)
    # Sport : pré-rempli avec le sport actif. En mode multisport (« Tous les sports »),
    # current_sport vaut nil → on retombe sur le 1er sport pour qu'un sport soit toujours
    # présélectionné. Sinon aucun sport n'est choisi au chargement et le JS (updateSport)
    # ne génère ni boutons de niveau ni formats (le champ « Niveau requis » reste vide).
    @match.sport           = current_sport || Sport.order(:name).first

    # Si on vient depuis une page équipe (?team_id=X), pré-associer l'équipe
    if params[:team_id].present?
      @match.team = Team.find_by(id: params[:team_id])
      # Un match d'équipe est privé par défaut
      @match.visibility = "private" if @match.team
    end

    # Équipes dont l'user est capitaine (pour le select dans le formulaire)
    @my_captained_teams = current_user.captained_teams.order(:name)

    # Couplage tournoi (Lot 4, élargi Lot 7) : préremplissage depuis « Créer la
    # rencontre » d'une carte, et listes du formulaire (tournois rattachables +
    # confrontations rattachables, pour le préremplissage côté client).
    prefill_from_tournament_match
    load_tournament_link_options
    # Les destinations Slack ne sont PLUS chargées ici : elles arrivent dans un
    # turbo-frame (cf. shared/_slack_share_frame et Slack::ShareFieldsController),
    # pour que l'API Slack ne retarde plus l'affichage du formulaire.
  end

  # POST /matches
  # Crée un nouveau match
  def create
    @match = Match.new(match_params)
    @match.user = current_user
    # Sécurité : seules les femmes peuvent créer un match "femme uniquement"
    # Si un non-femme envoie cette valeur (ex: via requête HTTP directe), on la remet à "tous"
    @match.genre_restriction = "tous" unless current_user.genre == "femme"

    # Si une équipe est associée, on vérifie juste que l'user en est bien
    # capitaine (sécurité). On NE force PLUS la visibilité : le choix
    # public/privé envoyé par le formulaire fait foi (côté form, choisir une
    # équipe met "privé" par défaut, mais l'user peut cliquer "Public").
    if @match.team_id.present?
      @match.team = Team.find_by(id: @match.team_id)
      unless @match.team&.captain?(current_user)
        @match.team = nil
        @match.team_id = nil
      end
    end

    # Couplage tournoi (Lot 4, élargi Lot 7) : ne conserver le rattachement que si
    # l'utilisateur y a droit (joueur de la confrontation ou organisateur du
    # tournoi) — pattern défensif, comme pour team_id.
    sanitize_tournament_link

    authorize @match

    # Sauvegarde + organisateur + rappel : logique commune mutualisée avec la
    # création via slash Slack (voir Slack::CommandsController / view_submission).
    if MatchCreationService.new(match: @match).call.success?
      # Rencontre issue d'une carte de tournoi → inscrire ses deux joueurs.
      enroll_tournament_players if @match.tournament_match

      # Si c'est un match d'équipe, on pré-inscrit les autres membres en "pending"
      # Ils devront confirmer leur participation depuis la page du match
      invite_team_members if @match.team

      # ⚠️  GAMIF_PAUSED — désactivé temporairement
      # AchievementService.new(current_user).check(:match_created)

      # Email de confirmation avec récapitulatif du match pour l'organisateur
      UserMailer.match_created(@match).deliver_later

      # Notifie en Web Push les utilisateurs dont le profil correspond à ce match
      # (sport + niveau + localisation). Exécuté en arrière-plan via SolidQueue.
      MatchWebPushJob.perform_later(@match.id)

      # Partage Slack : uniquement si l'organisateur a coché la case dans le formulaire.
      # Le job ne fait rien si le compte n'est pas lié ou si aucun channel n'est résoluble.
      if params[:post_to_slack].present? && current_user.slack_linked?
        SlackNotifyJob.perform_later("Match", @match.id, current_user.id,
                                     params[:slack_channel_id].presence,
                                     params[:slack_workspace_id].presence)
      end

      redirect_to @match, notice: "Match créé avec succès !"
    else
      @my_captained_teams = current_user.captained_teams.order(:name)
      load_tournament_link_options
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
    params[:match][:genre_restriction] = "tous" if params.dig(:match,
                                                              :genre_restriction) == "feminin" && current_user.genre != "femme"

    # ── Capturer les valeurs AVANT la mise à jour ──────────────────────────────
    # On sauvegarde les données actuelles pour détecter les changements pertinents.
    previous_values = {
      date: @match.date,
      time: @match.time,
      end_time: @match.end_time,
      venue_id: @match.venue_id,
      title: @match.title
    }

    if @match.update(match_params)
      # ── Après succès : notifier les participants des changements ────────────
      # (la cloche navbar se mettra à jour en temps réel via ActionCable)
      notify_participants_of_changes(previous_values)
      redirect_to @match, notice: "Match mis à jour avec succès !"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /matches/:id
  # Supprime un match et notifie tous les participants (temps réel + email).
  # Logique déléguée au service partagé avec l'annulation depuis Slack, qui
  # édite aussi les cartes Slack en « Annulé » avant la suppression.
  def destroy
    authorize @match

    MatchCancellationService.new(match: @match).call

    redirect_to matches_path, notice: "Match supprimé."
  end

  # PATCH /matches/:id/make_public
  # Passe un match privé en public — réservé à l'organisateur
  def make_public
    authorize @match
    @match.update!(visibility: "public")
    redirect_to @match, notice: "Le match est maintenant ouvert au public !"
  end

  # POST /matches/:id/share_on_slack
  # Partage manuel du match dans une destination Slack — réservé à l'organisateur.
  # Rattrapage si la case « Partager sur Slack » n'a pas été cochée à la création.
  # Réutilise le même job que #create ; la destination (channel/DM) et le workspace
  # sont facultatifs → fallback sur la destination par défaut via ChannelResolver.
  def share_on_slack
    authorize @match

    unless current_user.slack_linked?
      return redirect_to @match, alert: "Ton compte n'est lié à aucun espace Slack."
    end

    SlackNotifyJob.perform_later("Match", @match.id, current_user.id,
                                 params[:slack_channel_id].presence,
                                 params[:slack_workspace_id].presence)

    redirect_to @match, notice: "Match partagé sur Slack 🎉"
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
    # Fin réelle du match (heure de fin saisie, sinon +1h par défaut)
    end_dt = @match.end_datetime || (start_dt + 1.hour)

    # Lieu : venue ou adresse libre
    location = @match.place.presence || ""

    # Description enrichie pour le calendrier
    description = "Match #{@match.title} - Niveau : #{@match.level}"

    # Contenu du fichier ICS (format standard iCalendar)
    ics_content = <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Teams-up//Teams-up//FR
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

  # Applique tous les filtres optionnels sur @matches selon les params reçus
  def apply_filters
    # Recherche full-text — titre, ville, description ou prénom/nom du créateur
    @matches = @matches.search_by_title_place_and_creator(params[:query]) if params[:query].present?

    # Filtre par sport (multi-sélection) :
    # - sport(s) sélectionné(s) dans l'URL → filtrer par ces sports
    # - Aucun param sport ET pas de no_prefilter → fallback sur le sport actif de l'utilisateur
    # - no_prefilter=1 (bouton "Effacer les filtres") → aucun filtre sport = TOUS les sports
    sport_ids = params[:sport_ids]&.reject(&:blank?) || []
    if sport_ids.any?
      @matches = @matches.where(sport_id: sport_ids)
    elsif current_sport.present? && params[:no_prefilter].blank?
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
    @matches = @matches.where("player_left >= ?", params[:player_left].to_i) if params[:player_left].to_i.positive?

    # Filtre "Mes lieux" — restreint aux venues favorites de l'utilisateur
    # Disponible comme filtre manuel pour combiner avec d'autres filtres (date, niveau, etc.)
    return unless params[:favorite_venues].present? && user_signed_in?

    venue_ids = current_user.profil&.favorite_venues&.pluck(:id)
    @matches = @matches.where(venue_id: venue_ids) if venue_ids&.any?
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
    return unless profil # Sécurité : pas de profil = pas de pré-filtres

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
    @match = Match.from_param(params[:id])
  end

  # Liste blanche des paramètres autorisés pour créer/modifier un match
  def match_params
    params.require(:match).permit(
      :title, :description, :date, :time, :end_time, :place, :venue_id,
      :level, :players_needed, :players_present, :validation_mode, :price_per_player,
      :sport_id, :format, :banner_image, :visibility,
      :genre_restriction, # Restriction de genre : "tous" ou "feminin"
      :team_id,           # Équipe organisatrice (optionnel)
      :booking_link,      # Lien de réservation/paiement du terrain (optionnel)
      :tournament_id,        # Tournoi auquel rattacher la rencontre (Lot 4, optionnel)
      :tournament_match_id   # Carte de tournoi précise reliée (Lot 4, optionnel)
    )
  end

  # ── Couplage tournoi ────────────────────────────────────────────────────────
  # Options du bloc « Tournoi » du formulaire : les tournois rattachables + la map
  # de leurs confrontations rattachables (pour le select « Confrontation » et le
  # préremplissage côté client, cf. match_form_controller#updateTournament).
  def load_tournament_link_options
    @linkable_tournaments = linkable_tournaments_for_select
    @linkable_tournament_matches = linkable_tournament_matches_map(@linkable_tournaments)
  end

  # Tournois non terminés auxquels l'utilisateur peut rattacher une rencontre :
  # ceux qu'il organise ET ceux où il est inscrit (un joueur planifie lui-même sa
  # rencontre de poule, cf. TournamentMatchPolicy#create_match?).
  def linkable_tournaments_for_select
    Tournament.where.not(status: "completed")
              .left_joins(:tournament_users)
              .where(
                "tournaments.user_id = :id OR (tournament_users.user_id = :id AND tournament_users.status = 'approved')",
                id: current_user.id
              )
              .distinct.order(:name)
  end

  # Confrontations rattachables, groupées par tournoi :
  #   { tournament_id => [{ id:, label:, sport_id:, title:, place:, … }, …] }
  # Filtres : pas de bye, pas déjà rattachée à une rencontre, et l'utilisateur y
  # joue ou organise le tournoi — mêmes règles que create_match?, mais évaluées
  # une seule fois par tournoi (organizer? interroge les co-organisateurs).
  def linkable_tournament_matches_map(tournaments)
    return {} if tournaments.empty?

    pending = TournamentMatch.where(is_bye: false).where.missing(:match)
                             .joins(:tournament_round)
                             .where(tournament_rounds: { tournament_id: tournaments.map(&:id) })
                             # user > profil préchargés : les libellés des options
                             # appellent short_name / display_name sur les DEUX joueurs
                             # (cf. tournament_match_option), soit 4 requêtes par
                             # confrontation sans ce preload — une centaine de
                             # confrontations en poule suffit à faire traîner la page.
                             .includes(:tournament_round,
                                       player_a: { user: :profil },
                                       player_b: { user: :profil })
                             .order(:position)

    pending.group_by { |tm| tm.tournament_round.tournament_id }.each_with_object({}) do |(tournament_id, tms), map|
      tournament = tournaments.find { |t| t.id == tournament_id }
      organizer  = tournament.organizer?(current_user)

      rows = tms.filter_map do |tm|
        next if tm.player_b.nil? # carte incomplète (ne devrait pas arriver hors bye)
        next unless organizer || [tm.player_a.user_id, tm.player_b.user_id].include?(current_user.id)

        tournament_match_option(tm, tournament)
      end

      map[tournament_id] = rows if rows.any?
    end
  end

  # Une confrontation telle que la voit le formulaire (JSON consommé par Stimulus).
  # Les champs de préremplissage reprennent exactement ceux de
  # prefill_from_tournament_match : une seule règle, deux points d'application.
  def tournament_match_option(tmatch, tournament)
    {
      id: tmatch.id,
      # short_name (« Prénom N. ») et non display_name : deux noms complets dans
      # une même option dépassent la largeur du <select> et sont tronqués.
      label: "#{tmatch.player_a.short_name} vs #{tmatch.player_b.short_name}",
      title: tournament_match_title(tmatch, tournament),
      sport_id: tournament.sport_id,
      place: tournament.place,
      venue_id: tournament.venue_id,
      date: tournament.date&.to_s,
      time: tournament.time&.strftime("%H:%M"),
      banner_image: tournament.banner_image
    }
  end

  # Titre par défaut d'une rencontre issue d'une confrontation de tournoi.
  def tournament_match_title(tmatch, tournament)
    "#{tournament.sport&.name} — #{tmatch.player_a.display_name} vs #{tmatch.player_b.display_name}"
  end

  # Préremplit @match depuis une carte de tournoi (?tournament_match_id=X).
  # Sécurité : ignoré si la carte est absente ou si l'utilisateur n'a pas le droit
  # de planifier cette rencontre (bye, rencontre déjà créée, ni joueur ni
  # organisateur — cf. TournamentMatchPolicy#create_match?).
  def prefill_from_tournament_match
    return if params[:tournament_match_id].blank?

    tm = TournamentMatch.find_by(id: params[:tournament_match_id])
    return if tm.nil? || !policy(tm).create_match?

    @match.tournament_match = tm
    @match.tournament       = tm.tournament
    @match.sport            = tm.tournament.sport
    @match.level            = "Tout niveau" # niveau neutre : bypass la grille du sport
    @match.players_needed   = 2
    @match.title            = tournament_match_title(tm, tm.tournament)
    # Format : premier format à taille définie du sport (1v1 en ping-pong, tennis
    # ou badminton, 2v2 en padel). Le sélecteur de format n'est pas affiché en
    # contexte tournoi (cf. _form.html.erb) : une confrontation oppose deux
    # joueurs, la question ne se pose pas.
    #
    # On écarte le format « Libre » : il rendrait `players_present` obligatoire
    # (cf. Match) alors qu'aucun champ ne permet plus de le saisir. Un sport sans
    # format chiffré reste donc sans format, ce que le modèle accepte.
    @match.format = tournament_match_format(tm)

    # Reprend le lieu et la date/heure déjà connus du tournoi, pour éviter de tout
    # ressaisir à la main. Tout reste modifiable : les deux joueurs conviennent de
    # leur créneau (un tournoi n'a d'ailleurs plus d'heure de début, cf. Lot 7).
    @match.venue_id = tm.tournament.venue_id if tm.tournament.venue_id.present?
    @match.place    = tm.tournament.place    if tm.tournament.place.present?
    @match.date     = tm.tournament.date     if tm.tournament.date.present?
    if tm.tournament.time.present?
      @match.time     = tm.tournament.time
      @match.end_time = @match.time + 1.hour # le défaut posé dans `new` (basé sur l'heure courante) ne vaut plus une fois `time` écrasée
    end
    @match.banner_image = tournament_banner_image(tm)
  end

  # Format imposé à une rencontre créée depuis une carte de tournoi : le premier
  # format du sport dont la taille d'équipe est chiffrée (« Libre » exclu, voir
  # prefill_from_tournament_match). nil si le sport n'en propose aucun.
  def tournament_match_format(tmatch)
    formats = tmatch.tournament.sport&.available_formats || []
    formats.find { |fmt| fmt[:players].present? }&.dig(:label)
  end

  # Image de bannière d'une rencontre créée depuis une carte de tournoi.
  #
  # On veut une image DU SPORT du tournoi, connue dès le rendu serveur : la vue
  # `new` s'en sert pour peindre la bannière tout de suite, sans laisser
  # apparaître l'image multisport du CSS avant que le JS ne prenne la main.
  #
  # L'image du tournoi n'est conservée que si elle appartient à la banque du
  # sport : sinon `updateBanner()` (match_form_controller.js) la jugerait
  # incohérente au chargement et la remplacerait par une autre — ce qui
  # provoquerait justement le clignotement qu'on cherche à éviter.
  #
  # Choix déterministe (id de la carte) : le ré-affichage du formulaire après
  # une erreur de validation ne change pas l'image sous les yeux de l'utilisateur.
  def tournament_banner_image(tmatch)
    images = helpers.sport_images_for(tmatch.tournament.sport&.slug)
    current = tmatch.tournament.banner_image

    images.include?(current) ? current : images[tmatch.id % images.size]
  end

  # Valide le rattachement tournoi envoyé par le formulaire : ne le persiste que
  # si l'utilisateur y a droit (joueur de la confrontation ou organisateur du
  # tournoi), sinon on annule les deux refs.
  def sanitize_tournament_link
    if @match.tournament_match_id.present?
      tm = TournamentMatch.find_by(id: @match.tournament_match_id)
      if tm && policy(tm).create_match?
        @match.tournament = tm.tournament
        # Le format et la capacité d'une confrontation ne se négocient pas : ils
        # découlent du sport du tournoi (1v1 en ping-pong). On les réimpose ici
        # plutôt que de faire confiance aux champs cachés du formulaire — sinon
        # un POST forgé, ou une valeur héritée d'un autre sport ("3v3"), passe.
        # Mêmes règles qu'au préremplissage (prefill_from_tournament_match).
        @match.sport           = tm.tournament.sport
        @match.format          = tournament_match_format(tm)
        @match.players_needed  = 2
      else
        @match.tournament = nil
        @match.tournament_match = nil
      end
    elsif @match.tournament_id.present?
      tournament = Tournament.find_by(id: @match.tournament_id)
      @match.tournament = nil unless tournament && linkable_tournament?(tournament)
    end
  end

  # L'utilisateur peut-il rattacher une rencontre à ce tournoi (sans viser une
  # confrontation précise) ? Organisateur ou inscrit approuvé.
  def linkable_tournament?(tournament)
    tournament.organizer?(current_user) ||
      tournament.tournament_users.approved.exists?(user_id: current_user.id)
  end

  # Inscrit les deux joueurs de la carte de tournoi comme participants approuvés
  # (en plus de l'organisateur déjà créé). Idempotent, saute le créateur.
  def enroll_tournament_players
    @match.tournament_match.players.each do |tu|
      next if tu.user_id == current_user.id

      @match.match_users.find_or_create_by(user_id: tu.user_id) do |mu|
        mu.role = "joueur"
        mu.status = "approved"
      end
    end
  end

  # Pré-inscrit tous les membres de l'équipe (sauf le captain/créateur) en "pending"
  # Envoie une notification à chaque membre pour les prévenir
  def invite_team_members
    @match.team.members.where.not(id: current_user.id).each do |member|
      @match.match_users.create(user: member, role: "joueur", status: "pending")
      Notification.create(
        user: member,
        message: "📅 #{@match.team.name} a un nouveau match : \"#{@match.title}\". Confirme ta présence !",
        link: match_path(@match)
      )
    end
  end

  # ── Notifie tous les participants approuvés si les détails clés du match ont changé
  # Invoquée après une mise à jour réussie du match (date, heure, lieu, titre).
  # Crée des notifications qui s'affichent en temps réel dans la cloche navbar via ActionCable.
  def notify_participants_of_changes(previous_values)
    # ── Détecter les champs modifiés pertinents ────────────────────────────────
    # On compare uniquement les champs importants pour les participants :
    # date, heure de début, lieu, et titre.
    changes = []
    changes << "la date" if previous_values[:date] != @match.date
    changes << "l'heure" if previous_values[:time] != @match.time
    changes << "l'heure de fin" if previous_values[:end_time] != @match.end_time
    changes << "le lieu" if previous_values[:venue_id] != @match.venue_id
    changes << "le titre" if previous_values[:title] != @match.title

    # Si aucun champ pertinent n'a changé, on abandonne
    return if changes.empty?

    # ── Construire le message de notification ───────────────────────────────
    # Format : "📋 Le match "X" a été modifié : [liste des champs]"
    changed_text = changes.join(", ")
    message = "📋 Le match \"#{@match.title}\" a été modifié : #{changed_text} a changé."

    # ── Notifier tous les participants approuvés (sauf l'organisateur) ─────────
    # On récupère les match_users avec status "approved" (excluant les en attente
    # ou refusés), et on exclut l'organisateur du match lui-même.
    participants = @match.match_users
                         .where(status: "approved")
                         .where.not(user_id: @match.user_id)
                         .includes(:user)

    # Créer une notification pour chaque participant + envoyer email
    participants.each do |match_user|
      Notification.create!(
        user: match_user.user,
        actor: current_user,
        message: message,
        link: match_path(@match),
        read: false
      )

      # Envoi email asynchrone (SolidQueue) — ne bloque pas la requête
      UserMailer.match_modified(@match, match_user.user, changes: changes).deliver_later
    end
  end
end
