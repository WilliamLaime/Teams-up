class ProfilsController < ApplicationController
  # Retrouver le profil de l'utilisateur connecté avant chaque action
  # On exclut show_user car il charge le profil d'un autre utilisateur
  before_action :set_profil, except: [:show_user]

  # GET /profil
  # Affiche le profil de l'utilisateur connecté
  def show
    authorize @profil
    # @profil_user sert dans la vue pour afficher le bon utilisateur
    @profil_user = current_user
  end

  # GET /users/:id/profil
  # Affiche le profil public d'un autre utilisateur
  def show_user
    # On indique à Pundit qu'on gère l'autorisation manuellement (accès public)
    skip_authorization
    @profil_user = User.find(params[:id])
    @profil = @profil_user.profil || @profil_user.build_profil
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
    if Profil::STAT_ATTRIBUTES.include?(attribute) && @profil.stat_points > 0
      @profil.increment!(attribute.to_sym)   # +1 sur l'attribut choisi
      @profil.decrement!(:stat_points)       # -1 point disponible
    end

    redirect_to profil_path
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

    if @profil.update(profil_params)
      # 🎮 Vérifier l'achievement "profil complété" après la mise à jour
      AchievementService.new(current_user).check(:profile_updated)
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

  # Liste blanche des paramètres autorisés pour modifier le profil
  def profil_params
    # :avatar est le champ Active Storage pour la photo de profil
    params.require(:profil).permit(
      :first_name, :last_name, :address, :description, :level, :phone, :role, :localisation, :time_available, :avatar
    )
  end
end
