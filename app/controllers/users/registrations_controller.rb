# Ce controller surcharge le controller d'inscription de Devise
# pour créer automatiquement un profil avec prénom, nom et avatar (photo ou preset)
module Users
  class RegistrationsController < Devise::RegistrationsController
    # Noms de fichiers autorisés pour les avatars prédéfinis (évite les injections de chemin)
    VALID_PRESET_AVATARS = %w[01 02 3 4 5 6 7 8 9 10 11 12].freeze

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
        respond_with resource
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
        respond_with resource
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
        respond_with resource
        return
      end

      super do |user|
        if user.persisted?
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
