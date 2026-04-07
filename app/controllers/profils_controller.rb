class ProfilsController < ApplicationController
  # Noms de fichiers autorisés pour les avatars prédéfinis
  VALID_PRESET_AVATARS = %w[01 02 3 4 5 6 7 8 9 10 11 12].freeze
  # Retrouver le profil de l'utilisateur connecté avant chaque action
  # On exclut show_user et show_user_simple car ils chargent le profil d'un autre utilisateur
  before_action :set_profil, except: [:show_user, :show_user_simple]

  # GET /profil/old
  # Ancien profil gamifié — conservé mais non exposé depuis la navigation principale
  def show
    authorize @profil

    # Charge tous les amis acceptés de l'utilisateur connecté
    @all_friends = current_user.all_friends.includes(:profil)

    # Charge les demandes d'ami en attente reçues par l'utilisateur connecté
    # (pour afficher les boutons Accepter / Refuser sur son propre profil)
    @pending_friend_requests = current_user.inverse_friendships
                                           .pending
                                           .includes(user: :profil)

    # Nombre de matchs réellement joués :
    # - status "approved" → l'user était bien inscrit (pas en file d'attente ni en attente)
    # - match terminé → date+heure du match < maintenant - 1h (H+1)
    @matchs_joues = current_user.match_users
                                .joins(:match)
                                .where(status: "approved")
                                .where("(matches.date + matches.time) < ?", Time.current - 1.hour)
                                .count

    # Charge les 10 derniers avis MUTUELS reçus par l'utilisateur connecté
    # Un avis A→B n'est visible que si B→A existe pour le même match
    # includes évite les N+1 queries (charge reviewer + son profil en une requête)
    @avis = Avis.mutual
                .where(reviewed_user: current_user)
                .includes(reviewer: :profil)
                .order(created_at: :desc)
                .limit(10)

    # Nombre d'avis reçus mais non-mutuels (l'autre n'a pas encore noté en retour)
    # Affiché en hint pour encourager l'user à noter ses coéquipiers
    @pending_avis_count = Avis.non_mutual
                              .where(reviewed_user: current_user)
                              .count

    # Liste des utilisateurs qui ont noté current_user sans recevoir d'avis en retour
    # → affichés comme raccourcis dans le hint pour aller les noter directement
    # On déduplique les IDs (un même user peut avoir noté dans plusieurs matchs)
    pending_reviewer_ids = Avis.non_mutual
                               .where(reviewed_user: current_user)
                               .pluck(:reviewer_id)
                               .uniq
    @pending_reviewers = User.where(id: pending_reviewer_ids).includes(:profil)

    # Équipes du joueur (affiché sur le profil)
    @profil_teams = current_user.teams.includes(:captain, :team_members).order(:name)
  end

  # GET /users/:id/profil/old
  # Ancien profil public gamifié — conservé mais non exposé depuis la navigation
  def show_user
    skip_authorization
    @profil_user = User.find(params[:id])
    @profil = @profil_user.profil || @profil_user.build_profil

    # On n'affiche pas les amis d'un autre utilisateur (trop intrusif)
    @all_friends = nil

    # Vérifie le statut de la relation entre current_user et ce profil
    if user_signed_in? && current_user != @profil_user
      # Sont-ils amis (demande acceptée) ?
      @already_friends = current_user.friends_with?(@profil_user)
      # current_user a-t-il envoyé une demande en attente à ce profil ?
      @pending_sent = current_user.pending_request_sent_to?(@profil_user)
      # Ce profil a-t-il envoyé une demande en attente à current_user ?
      @pending_received = current_user.pending_request_from?(@profil_user)
      # La friendship initiée par current_user (pour Annuler ou Retirer)
      @friendship_initiated_by_me = current_user.friendships.find_by(friend_id: @profil_user.id)
    end

    # Nombre de matchs réellement joués pour le profil public :
    # - status "approved" → l'user était bien inscrit (pas en file d'attente ni en attente)
    # - match terminé → date+heure du match < maintenant - 1h (H+1)
    @matchs_joues = @profil_user.match_users
                                .joins(:match)
                                .where(status: "approved")
                                .where("(matches.date + matches.time) < ?", Time.current - 1.hour)
                                .count

    # Charge les 10 derniers avis MUTUELS reçus par cet utilisateur
    # Un avis A→B n'est visible que si B→A existe pour le même match
    @avis = Avis.mutual
                .where(reviewed_user: @profil_user)
                .includes(reviewer: :profil)
                .order(created_at: :desc)
                .limit(10)

    # Cherche si l'utilisateur connecté peut laisser un avis à ce joueur
    # (match commun terminé, dans les 7j, pas encore noté)
    @eligible_match = find_eligible_match_for_review(@profil_user)

    # Vérifie si l'utilisateur affiché a déjà laissé un avis non-mutuel à current_user
    # → "Cet utilisateur vous a noté, notez-le pour débloquer son avis"
    @hidden_review_from_this_user = user_signed_in? &&
                                    current_user != @profil_user &&
                                    Avis.non_mutual.exists?(
                                      reviewer_id: @profil_user.id,
                                      reviewed_user_id: current_user.id
                                    )

    # Toutes les équipes du joueur affiché — toujours chargées
    @profil_teams = @profil_user.teams.includes(:captain, :team_members).order(:name)

    # Équipes où current_user est captain et peut encore inviter ce joueur
    # (uniquement si on consulte le profil de quelqu'un d'autre)
    if user_signed_in? && current_user != @profil_user
      excluded         = @profil_user.teams.pluck(:id) +
                         TeamInvitation.pending.where(invitee: @profil_user).pluck(:team_id)
      @invitable_teams = current_user.captained_teams.where.not(id: excluded).order(:name)
    end

    render :show
  end

  # GET /profil/edit
  # Affiche le formulaire de modification du profil
  def edit
    # Pundit vérifie que l'utilisateur ne peut modifier que son propre profil
    authorize @profil
  end

  # PATCH /profil/spend_stat?attribute=attr_attack
  # Dépense 1 point de stat sur l'attribut demandé
  def spend_stat
    skip_authorization
    attribute = params[:attribute]

    # Sécurité : on n'accepte que les 4 attributs connus (pas d'injection SQL possible)
    if Profil::STAT_ATTRIBUTES.include?(attribute) && @profil.stat_points.positive?
      @profil.increment!(attribute.to_sym)   # +1 sur l'attribut choisi
      @profil.decrement!(:stat_points)       # -1 point disponible
    end

    redirect_to profil_path  # profil_path → GET /profil → show_simple
  end

  # GET /profil
  # Version principale du profil (sans gamification)
  def show_simple
    # On réutilise la règle show? de ProfilPolicy (seul le propriétaire peut voir)
    authorize @profil, :show?
    # @profil_user sert dans la vue pour afficher le bon utilisateur
    @profil_user = current_user

    # Charge tous les amis acceptés de l'utilisateur connecté
    @all_friends = current_user.all_friends.includes(:profil)

    # Charge les demandes d'ami en attente reçues
    @pending_friend_requests = current_user.inverse_friendships
                                           .pending
                                           .includes(user: :profil)

    # Nombre de matchs réellement joués (status "approved" + match terminé)
    @matchs_joues = current_user.match_users
                                .joins(:match)
                                .where(status: "approved")
                                .where("(matches.date + matches.time) < ?", Time.current - 1.hour)
                                .count

    # Charge les 10 derniers avis mutuels reçus
    @avis = Avis.mutual
                .where(reviewed_user: current_user)
                .includes(reviewer: :profil)
                .order(created_at: :desc)
                .limit(10)

    # Nombre d'avis reçus mais non-mutuels (encourage l'user à noter en retour)
    @pending_avis_count = Avis.non_mutual
                              .where(reviewed_user: current_user)
                              .count

    # Utilisateurs qui ont noté current_user sans recevoir d'avis en retour
    pending_reviewer_ids = Avis.non_mutual
                               .where(reviewed_user: current_user)
                               .pluck(:reviewer_id)
                               .uniq
    @pending_reviewers = User.where(id: pending_reviewer_ids).includes(:profil)

    # Équipes du joueur (affiché sur le profil)
    @profil_teams = current_user.teams.includes(:captain, :team_members).order(:name)
  end

  # GET /users/:id/profil
  # Version principale du profil public d'un autre utilisateur
  def show_user_simple
    skip_authorization
    @profil_user = User.find(params[:id])
    @profil = @profil_user.profil || @profil_user.build_profil

    # On n'affiche pas les amis d'un autre utilisateur (trop intrusif)
    @all_friends = nil

    # Vérifie le statut de la relation entre current_user et ce profil
    if user_signed_in? && current_user != @profil_user
      @already_friends              = current_user.friends_with?(@profil_user)
      @pending_sent                 = current_user.pending_request_sent_to?(@profil_user)
      @pending_received             = current_user.pending_request_from?(@profil_user)
      @friendship_initiated_by_me   = current_user.friendships.find_by(friend_id: @profil_user.id)
    end

    # Nombre de matchs réellement joués par cet utilisateur
    @matchs_joues = @profil_user.match_users
                                .joins(:match)
                                .where(status: "approved")
                                .where("(matches.date + matches.time) < ?", Time.current - 1.hour)
                                .count

    # Charge les 10 derniers avis mutuels reçus
    @avis = Avis.mutual
                .where(reviewed_user: @profil_user)
                .includes(reviewer: :profil)
                .order(created_at: :desc)
                .limit(10)

    # Vérifie si l'utilisateur connecté peut laisser un avis à ce joueur
    @eligible_match = find_eligible_match_for_review(@profil_user)

    # Vérifie si cet utilisateur a déjà laissé un avis non-mutuel à current_user
    @hidden_review_from_this_user = user_signed_in? &&
                                    current_user != @profil_user &&
                                    Avis.non_mutual.exists?(
                                      reviewer_id: @profil_user.id,
                                      reviewed_user_id: current_user.id
                                    )

    # Toutes les équipes du joueur affiché — toujours chargées, même si c'est son propre profil
    @profil_teams = @profil_user.teams.includes(:captain, :team_members).order(:name)

    # Équipes où current_user est captain et peut encore inviter ce joueur
    # (uniquement si on consulte le profil de quelqu'un d'autre)
    if user_signed_in? && current_user != @profil_user
      excluded         = @profil_user.teams.pluck(:id) +
                         TeamInvitation.pending.where(invitee: @profil_user).pluck(:team_id)
      @invitable_teams = current_user.captained_teams.where.not(id: excluded).order(:name)
    end

    render :show_simple
  end

  # PATCH/PUT /profil
  # Met à jour le profil et les sports de l'utilisateur connecté
  def update
    # Pundit vérifie l'autorisation avant de sauvegarder
    authorize @profil

    # ── Validation serveur : type et taille de l'avatar uploadé ──────────────
    # On vérifie AVANT la sauvegarde pour bloquer les fichiers invalides
    avatar_file = params.dig(:profil, :avatar)
    if avatar_file.present? && !valid_avatar_file?(avatar_file)
      @profil.errors.add(:avatar, "doit être un fichier JPG, PNG ou GIF de moins de 5 Mo")
      render :edit, status: :unprocessable_entity
      return
    end

    # Met à jour les sports si la section sport était présente dans le formulaire
    # Le champ caché user[sports_submitted]=1 indique que la section a été soumise
    if params.dig(:user, :sports_submitted)
      # sport_ids est un tableau d'IDs — [] si aucun sport coché
      current_user.sport_ids = params.dig(:user, :sport_ids) || []
    end

    # Met à jour les niveaux et rôles par sport
    # params[:sport_profils] = { "sport_id" => { level: "...", role: "..." }, ... }
    if params[:sport_profils].present?
      selected_sport_ids = (params.dig(:user, :sport_ids) || []).map(&:to_i)

      params[:sport_profils].each do |sport_id, sp_params|
        # On ne sauvegarde que les sports réellement sélectionnés
        next unless selected_sport_ids.include?(sport_id.to_i)

        # find_or_initialize_by : met à jour si existe, crée sinon
        sp = SportProfil.find_or_initialize_by(profil: @profil, sport_id: sport_id.to_i)
        sp.level = sp_params[:level].presence
        sp.role  = sp_params[:role].presence
        # On utilise save (sans !) pour éviter une exception non gérée en cas de validation invalide
        unless sp.save
          sp.errors.full_messages.each do |msg|
            @profil.errors.add(:base, msg)
          end
          render :edit, status: :unprocessable_entity
          return
        end
      end

      # Supprime les SportProfil des sports désélectionnés
      @profil.sport_profils.where.not(sport_id: selected_sport_ids).destroy_all
    end

    # Sauvegarde le genre sur l'utilisateur connecté (le genre est sur User, pas Profil)
    # params[:user][:genre] est envoyé par le champ caché name="user[genre]" du formulaire
    if params.dig(:user, :genre).present? && User::GENRES.include?(params.dig(:user, :genre))
      current_user.update(genre: params.dig(:user, :genre))
    end

    # Gère l'avatar : photo uploadée OU avatar prédéfini
    # On le résout avant update() pour l'inclure dans le même save
    avatar = resolve_avatar
    @profil.avatar.attach(avatar) if avatar.present?

    # Le champ caché "favorite_venue_ids" envoie une string "id1,id2" (géré par Stimulus).
    # Rails attend un tableau pour l'association has_many → on convertit avant update.
    venue_ids_raw = params.dig(:profil, :favorite_venue_ids)
    if venue_ids_raw.is_a?(String)
      params[:profil][:favorite_venue_ids] = venue_ids_raw.split(",").map(&:to_i).reject(&:zero?)
    end

    if @profil.update(profil_params)
      # Vérifier l'achievement "profil complété" après la mise à jour
      # Le rescue évite qu'une erreur du service (ex: broadcast ActionCable) n'empêche la sauvegarde
      begin
        AchievementService.new(current_user).check(:profile_updated)
      rescue => e
        Rails.logger.error "[AchievementService] Erreur lors du check profile_updated : #{e.message}"
      end
      redirect_to simple_profil_path, notice: "Profil mis à jour avec succès !"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Retrouve le profil de l'utilisateur connecté
  # Si le profil n'existe pas encore, on le crée automatiquement
  def set_profil
    @profil = current_user.profil || current_user.build_profil
  end

  # Vérifie que le fichier uploadé est bien une image autorisée et dans la limite de taille
  # Utilisé avant la sauvegarde pour bloquer les fichiers invalides côté serveur
  def valid_avatar_file?(file)
    allowed_types = %w[image/jpeg image/png image/gif]
    allowed_types.include?(file.content_type) && file.size <= 5.megabytes
  end

  # Cherche un match où current_user et other_user ont joué ensemble,
  # où le match est terminé, dans la fenêtre de 7j, et pas encore noté.
  # PRIORITÉ : si other_user a déjà laissé un avis non-mutuel à current_user,
  # on retourne CE match en premier pour que les deux avis soient sur le même match
  # et deviennent mutuels (visibles publiquement).
  def find_eligible_match_for_review(other_user)
    # Pas d'avis possible sur son propre profil
    return nil if current_user == other_user

    # Récupère les match_ids où current_user a été approuvé
    my_match_ids = current_user.match_users.where(status: "approved").pluck(:match_id)
    # Récupère les match_ids où other_user a été approuvé
    their_match_ids = other_user.match_users.where(status: "approved").pluck(:match_id)

    # Intersection = matchs joués ensemble
    common_ids = my_match_ids & their_match_ids
    return nil if common_ids.empty?

    # Exclut les matchs où current_user a déjà noté other_user
    already_reviewed_ids = Avis.where(
      reviewer_id: current_user.id,
      reviewed_user_id: other_user.id
    ).pluck(:match_id)

    reviewable_ids = common_ids - already_reviewed_ids
    return nil if reviewable_ids.empty?

    # Cherche si other_user a déjà laissé un avis non-mutuel à current_user
    # sur l'un des matchs reviewable → on le priorise pour créer la mutualité
    pending_match_id = Avis.non_mutual
                           .where(reviewer_id: other_user.id, reviewed_user_id: current_user.id)
                           .where(match_id: reviewable_ids)
                           .pluck(:match_id)
                           .first

    # Si un tel match existe et est encore dans la fenêtre, on le retourne en priorité
    if pending_match_id.present?
      priority_match = Match.where(id: pending_match_id)
                            .where("(date + time) < ?", Time.current - 1.hour)
                            .where("(date + time) > ?", Time.current - 7.days - 1.hour)
                            .first
      return priority_match if priority_match.present?
    end

    # Sinon, retourne le premier match éligible : terminé (>1h) ET dans les 7 derniers jours
    Match.where(id: reviewable_ids)
         .where("(date + time) < ?", Time.current - 1.hour)
         .where("(date + time) > ?", Time.current - 7.days - 1.hour)
         .order(date: :desc)
         .first
  end

  # Résout l'avatar à attacher au profil :
  # - Cas 1 : l'user a uploadé une photo → on retourne le fichier
  # - Cas 2 : l'user a choisi un avatar prédéfini → on ouvre le PNG depuis les assets
  # - Cas 3 : rien de nouveau → nil (l'avatar existant reste inchangé)
  def resolve_avatar
    avatar_file = params.dig(:profil, :avatar)
    preset_name = params.dig(:profil, :preset_avatar)

    if avatar_file.present?
      # Photo uploadée directement (géré aussi par profil_params, mais on le gère ici
      # pour rester cohérent avec la logique preset)
      nil # profil_params s'en occupe via :avatar

    elsif preset_name.present? && VALID_PRESET_AVATARS.include?(preset_name)
      # Avatar prédéfini : ouvre le fichier PNG depuis les assets
      # File.basename supprime tout composant de répertoire (ex: "../secret" → "secret")
      # C'est une protection supplémentaire en plus de la liste blanche ci-dessus
      safe_name = File.basename(preset_name)
      preset_path = Rails.root.join("app", "assets", "images", "avatar_png", "#{safe_name}.png")
      {
        io: File.open(preset_path),
        filename: "avatar_#{preset_name}.png",
        content_type: "image/png"
      }
    end
  end

  # Liste blanche des paramètres autorisés pour modifier le profil
  def profil_params
    # :avatar est le champ Active Storage pour la photo de profil
    # Note : :role ici est le POSTE SPORTIF du joueur (ex: "attaquant", "gardien"),
    # pas un rôle système/admin — Brakeman génère un faux positif sur ce champ.
    params.require(:profil).permit( # brakeman: ignore
      :first_name, :last_name, :address, :description,
      :level, :phone, :role, :localisation, :time_available, :avatar,
      :preferred_city,      # Ville préférée pour les pré-filtres
      favorite_venue_ids: [] # Lieux favoris (multi-select)
    )
  end
end
