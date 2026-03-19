class ProfilsController < ApplicationController
  # Noms de fichiers autorisés pour les avatars prédéfinis
  VALID_PRESET_AVATARS = %w[01 02 3 4 5 6 7 8 9 10 11 12].freeze
  # Retrouver le profil de l'utilisateur connecté avant chaque action
  # On exclut show_user car il charge le profil d'un autre utilisateur
  before_action :set_profil, except: [:show_user]

  # GET /profil
  # Affiche le profil de l'utilisateur connecté
  def show
    authorize @profil
    # @profil_user sert dans la vue pour afficher le bon utilisateur
    @profil_user = current_user

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
  end

  # GET /users/:id/profil
  # Affiche le profil public d'un autre utilisateur
  def show_user
    # On indique à Pundit qu'on gère l'autorisation manuellement (accès public)
    skip_authorization
    @profil_user = User.find(params[:id])
    @profil = @profil_user.profil || @profil_user.build_profil

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
                                      reviewer_id:      @profil_user.id,
                                      reviewed_user_id: current_user.id
                                    )

    render :show
  end

  # GET /profil/edit
  # Affiche le formulaire de modification du profil
  def edit
    # Pundit vérifie que l'utilisateur ne peut modifier que son propre profil
    authorize @profil
  end

  # PATCH/PUT /profil
  # Met à jour le profil et les sports de l'utilisateur connecté
  def update
    # Pundit vérifie l'autorisation avant de sauvegarder
    authorize @profil

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
        sp.save!
      end

      # Supprime les SportProfil des sports désélectionnés
      @profil.sport_profils.where.not(sport_id: selected_sport_ids).destroy_all
    end

    # Gère l'avatar : photo uploadée OU avatar prédéfini
    # On le résout avant update() pour l'inclure dans le même save
    avatar = resolve_avatar
    @profil.avatar.attach(avatar) if avatar.present?

    if @profil.update(profil_params)
      redirect_to profil_path, notice: "Profil mis à jour avec succès !"
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

  # Cherche un match où current_user et other_user ont joué ensemble,
  # où le match est terminé, dans la fenêtre de 7j, et pas encore noté
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
      reviewer_id:       current_user.id,
      reviewed_user_id:  other_user.id
    ).pluck(:match_id)

    reviewable_ids = common_ids - already_reviewed_ids
    return nil if reviewable_ids.empty?

    # Retourne le premier match éligible : terminé (>1h) ET dans les 7 derniers jours
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
      preset_path = Rails.root.join("app", "assets", "images", "avatar_png", "#{preset_name}.png")
      {
        io:           File.open(preset_path),
        filename:     "avatar_#{preset_name}.png",
        content_type: "image/png"
      }
    end
  end

  # Liste blanche des paramètres autorisés pour modifier le profil
  def profil_params
    # :avatar est le champ Active Storage pour la photo de profil
    params.require(:profil).permit(
      :first_name, :last_name, :address, :description, :level, :phone, :role, :localisation, :time_available, :avatar
    )
  end
end
