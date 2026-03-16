# Ce controller surcharge le controller d'inscription de Devise
# pour créer automatiquement un profil avec prénom, nom et avatar (photo ou preset)
class Users::RegistrationsController < Devise::RegistrationsController
  # Noms de fichiers autorisés pour les avatars prédéfinis (évite les injections de chemin)
  VALID_PRESET_AVATARS = %w[01 02 3 4 5 6 7 8 9 10 11 12].freeze

  def create
    super do |user|
      if user.persisted?
        profil_attrs = {
          first_name: sign_up_params[:first_name],
          last_name:  sign_up_params[:last_name]
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
      preset_path = Rails.root.join("app", "assets", "images", "avatar_png", "#{preset_name}.png")
      {
        io:           File.open(preset_path),
        filename:     "avatar_#{preset_name}.png",
        content_type: "image/png"
      }
    end
  end

  # Paramètres autorisés pour la création du compte
  # L'avatar et le preset ne sont PAS ici car ils sont gérés manuellement ci-dessus
  def sign_up_params
    params.require(:user).permit(
      :email, :password, :password_confirmation,
      :first_name, :last_name
    )
  end
end
