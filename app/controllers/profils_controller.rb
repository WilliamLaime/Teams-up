class ProfilsController < ApplicationController
  # Retrouver le profil de l'utilisateur connecté avant chaque action
  before_action :set_profil

  # GET /profil
  # Affiche le profil de l'utilisateur connecté
  def show
  end

  # GET /profil/edit
  # Affiche le formulaire de modification du profil
  def edit
  end

  # PATCH/PUT /profil
  # Met à jour le profil de l'utilisateur connecté
  def update
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

  # Liste blanche des paramètres autorisés pour modifier le profil
  def profil_params
    # :avatar est le champ Active Storage pour la photo de profil
    params.require(:profil).permit(
      :name, :address, :description, :level, :phone, :role, :localisation, :time_available, :avatar
    )
  end
end
