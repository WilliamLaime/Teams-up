# Ce controller surcharge le controller d'inscription de Devise
# pour créer automatiquement un profil avec prénom, nom et avatar (photo ou preset)
module Users
  class RegistrationsController < Devise::RegistrationsController
    # Noms de fichiers autorisés pour les avatars prédéfinis (évite les injections de chemin)
    VALID_PRESET_AVATARS = %w[01 02 3 4 5 6 7 8 9 10 11 12].freeze

    # Vérifie le captcha AVANT de traiter l'inscription
    before_action :verify_captcha_on_signup, only: [:create]

    # Action appelée quand l'utilisateur arrive sur la page d'inscription (GET)
    # Si l'utilisateur arrive directement (pas depuis la page de connexion),
    # on efface la "stored location" de Devise pour éviter une redirection non désirée
    # vers une page protégée (ex: "trouver un match") après inscription.
    # Cas souhaités :
    #   - homepage → S'inscrire → homepage ✓
    #   - matches (protégé) → connexion → S'inscrire → matches ✓
    def new
      if came_from_sign_in?
        # L'utilisateur vient de la page de connexion : on garde la stored location
        # (il voulait accéder à une page protégée avant d'être redirigé)
      else
        # Arrivée directe sur l'inscription : on efface la stored location
        # pour que la redirection post-inscription aille vers l'accueil
        session.delete("user_return_to")
      end
      super
    end

    def create
      # ── Validation serveur : au moins un sport requis ─────────────────────────
      sport_ids = params.dig(:user, :sport_ids).to_a.reject(&:blank?)

      if sport_ids.empty?
        # Construit le resource sans le sauvegarder pour réafficher le formulaire
        build_resource(sign_up_params)
        # Clé :sports → permet à la vue d'afficher l'erreur directement près du champ sport
        resource.errors.add(:sports, "Sélectionne au moins un sport pour continuer.")
        clean_up_passwords resource
        render :new, status: :unprocessable_entity
        return
      end

      # ── Validation serveur : genre obligatoire ────────────────────────────────
      genre = params.dig(:user, :genre).presence

      unless genre.present? && User::GENRES.include?(genre)
        # Construit le resource sans le sauvegarder pour réafficher le formulaire
        build_resource(sign_up_params)
        # Clé :genre → permet à la vue d'afficher l'erreur directement près du champ genre
        resource.errors.add(:genre, "Sélectionne ton genre pour continuer.")
        clean_up_passwords resource
        render :new, status: :unprocessable_entity
        return
      end

      # ── Validation serveur : type et taille de l'avatar uploadé ──────────────
      # On vérifie AVANT la création du compte pour éviter qu'un utilisateur
      # envoie un fichier malveillant ou trop lourd en renommant son extension en .jpg
      avatar_file = params.dig(:user, :avatar)
      if avatar_file.present? && !valid_avatar_file?(avatar_file)
        build_resource(sign_up_params)
        resource.errors.add(:base, "La photo de profil doit être un JPG, PNG ou GIF de moins de 5 Mo.")
        clean_up_passwords resource
        render :new, status: :unprocessable_entity
        return
      end

      super do |user|
        if user.persisted?
          # Log de sécurité : inscription réussie
          SecurityLog.log("signup", request, user: user)

          profil_attrs = {
            first_name: sign_up_params[:first_name],
            last_name: sign_up_params[:last_name]
          }

          # Résout l'avatar (photo uploadée ou preset) et l'ajoute si présent
          avatar = resolve_avatar
          profil_attrs[:avatar] = avatar if avatar.present?

          user.create_profil(profil_attrs)

          # Ajoute les sports sélectionnés par l'utilisateur lors de l'inscription
          sport_ids = params.dig(:user, :sport_ids).to_a.reject(&:blank?).map(&:to_i)
          if sport_ids.any?
            # On récupère uniquement les sports qui existent vraiment en base
            sports = Sport.where(id: sport_ids)
            user.sports = sports

            # Le premier sport sélectionné devient le sport actif par défaut
            user.update(current_sport_id: sports.first.id) if sports.any?
          end
        end
      end
    end

    private

    # Vérifie que le widget hcaptcha a bien été complété avant l'inscription
    def verify_captcha_on_signup
      return if verify_hcaptcha

      # Recrée le resource pour réafficher le formulaire avec les valeurs saisies
      build_resource(sign_up_params)
      flash.now[:alert] = "Vérification captcha échouée. Veuillez réessayer."
      render :new, status: :unprocessable_entity
    end

    # Retourne l'avatar à attacher au profil :
    # - Cas 1 : photo personnelle uploadée par l'utilisateur
    # - Cas 2 : avatar prédéfini choisi dans la grille (fichier PNG dans assets)
    # - Cas 3 : nil si aucun avatar choisi
    def resolve_avatar
      # Récupère les paramètres d'avatar hors de sign_up_params
      # (pour ne pas les assigner au modèle User qui n'a pas ces champs)
      avatar_file = params.dig(:user, :avatar)
      preset_name = params.dig(:user, :preset_avatar)

      if avatar_file.present?
        # Cas 1 : l'utilisateur a uploadé une photo personnelle
        avatar_file

      elsif preset_name.present? && VALID_PRESET_AVATARS.include?(preset_name)
        # Cas 2 : l'utilisateur a choisi un avatar prédéfini
        # On ouvre le fichier PNG depuis assets et on l'attache via Active Storage
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

    # Retourne true si l'utilisateur arrive sur la page d'inscription depuis la page de connexion.
    # On compare le chemin du referer HTTP avec le chemin de la page de connexion Devise.
    def came_from_sign_in?
      return false unless request.referer.present?

      begin
        # On compare uniquement le chemin (path) pour ignorer le domaine
        URI.parse(request.referer).path == new_user_session_path
      rescue URI::InvalidURIError
        false
      end
    end

    # Vérifie que le fichier uploadé est bien une image autorisée et dans la limite de taille
    # Utilisé avant la création du compte pour bloquer les fichiers invalides côté serveur
    def valid_avatar_file?(file)
      allowed_types = %w[image/jpeg image/png image/gif]
      allowed_types.include?(file.content_type) && file.size <= 5.megabytes
    end

    # Redirection après inscription avec confirmation en attente (:confirmable activé)
    # Devise appelle cette méthode quand l'utilisateur n'est pas encore confirmé.
    # On stocke l'email en session pour l'afficher sur la page de confirmation,
    # puis on redirige vers la page dédiée qui explique quoi faire.
    def after_inactive_sign_up_path_for(resource)
      session[:confirmation_pending_email] = resource.email
      email_confirmation_pending_path
    end

    # ─────────────────────────────────────────────────────────────────────────────
    # Action DELETE : suppression de compte (droit à l'effacement, RGPD art. 17)
    # ─────────────────────────────────────────────────────────────────────────────
    # Surcharge Devise pour vérifier l'identité (mot de passe ou confirmation OAuth)
    # et gérer les actions métier avant destruction :
    # - Transfert du capitanat des équipes au membre avec le plus haut niveau XP
    # - Annulation des matchs futurs (participants notifiés par email)
    # - Log de sécurité
    # - Email de confirmation RGPD
    def destroy
      # ────── Étape 1 : Vérifier l'identité de l'utilisateur ──────────────────
      user = current_user
      return redirect_to edit_user_registration_path, alert: "Impossible de supprimer ton compte." unless user

      # Cas 1 : User OAuth (Google) → vérifie la checkbox de confirmation
      if user.provider.present?
        unless params[:delete_confirmation] == "1"
          return redirect_to edit_user_registration_path,
                            alert: "Veuillez confirmer la suppression de votre compte."
        end
      else
        # Cas 2 : User classique → vérifie le mot de passe
        password = params[:current_password_for_deletion].presence
        unless user.valid_password?(password)
          return redirect_to edit_user_registration_path,
                            alert: "Mot de passe incorrect. Suppression annulée."
        end
      end

      # ────── Étape 2 : Capturer les données avant destruction ──────────────────
      # (Le user sera bientôt détruit → impossible de lire ses données après)
      user_email = user.email
      user_name  = user.display_name
      deleted_at = Time.current

      # ────── Étape 3 : Transférer le capitanat ou supprimer les équipes ────────
      transfer_captainship_or_destroy(user)

      # ────── Étape 4 : Annuler les matchs futurs ─────────────────────────────────
      cancel_upcoming_matches_for(user, organizer_name: user_name)

      # ────── Étape 5 : Logger l'événement ─────────────────────────────────────
      SecurityLog.log("account_deletion", request, user: user)

      # ────── Étape 6 : Envoyer email de confirmation RGPD ──────────────────────
      AccountDeletionMailer.account_deleted(
        user_email:  user_email,
        user_name:   user_name,
        deleted_at:  deleted_at
      ).deliver_later

      # ────── Étape 7 : Déconnecter et détruire ─────────────────────────────────
      sign_out(user)
      user.destroy!

      # ────── Étape 8 : Rediriger avec confirmation ────────────────────────────
      redirect_to root_path, notice: "Ton compte a été supprimé. Nous espérons te revoir bientôt !"
    rescue => e
      Rails.logger.error("[AccountDeletion] Erreur lors de la suppression : #{e.message}")
      redirect_to edit_user_registration_path,
                  alert: "Une erreur est survenue. Veuillez réessayer."
    end

    private

    # Transfère le capitanat des équipes au membre avec le XP level le plus élevé
    # Si l'user était seul membre, l'équipe est détruite
    # @param user [User] l'utilisateur supprimé
    def transfer_captainship_or_destroy(user)
      user.captained_teams.each do |team|
        # Trouve tous les autres membres (SAUF celui supprimé)
        other_members = team.team_members
                            .where.not(user_id: user.id)
                            .includes(user: :profil)

        if other_members.any?
          # Transfère au membre avec le xp_level le plus élevé
          # team_members.user.profil.xp_level OU 0 si pas de profil
          new_captain = other_members.max_by { |tm| tm.user.profil&.xp_level || 0 }.user
          team.update!(captain: new_captain)
        else
          # L'user était le seul membre → détruit l'équipe
          team.destroy
        end
      end
    end

    # Annule tous les matchs futurs créés par l'user
    # Envoie un email aux participants pour les en informer
    # @param user           [User]   l'utilisateur supprimé
    # @param organizer_name [String] nom d'affichage du créateur (pour l'email)
    def cancel_upcoming_matches_for(user, organizer_name:)
      Match.where(user: user).upcoming.each do |match|
        # Notifie chaque participant approuvé (SAUF l'organisateur supprimé)
        match.match_users
             .where(status: "approved")
             .where.not(user_id: user.id)
             .includes(:user)
             .each do |match_user|
          # Utilise la version asynchrone de match_cancelled (scalaires uniquement)
          UserMailer.match_cancelled_async(
            user_email:      match_user.user.email,
            match_title:     match.title,
            match_date:      match.date,
            match_time_str:  match.time&.strftime("%Hh%M"),
            venue_name:      match.venue&.name,
            venue_city:      match.venue&.city,
            organizer_name:  organizer_name
          ).deliver_later
        end

        # Supprime le match
        match.destroy
      end
    end

    # Paramètres autorisés pour la création du compte
    # L'avatar et le preset ne sont PAS ici car ils sont gérés manuellement ci-dessus
    # :genre → stocké directement sur la table users
    def sign_up_params
      params.require(:user).permit(
        :email, :password, :password_confirmation,
        :first_name, :last_name,
        :genre
      )
    end
  end
end
