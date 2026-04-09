class AvisController < ApplicationController
  # POST /users/:user_id/avis
  # Crée un nouvel avis pour un joueur donné
  def create
    # Retrouve le joueur qui va être noté via l'URL (/users/:user_id/avis)
    @reviewed_user = User.find(params[:user_id])

    # Construit l'avis avec le reviewer = l'utilisateur connecté
    @avis = Avis.new(
      reviewer: current_user,
      reviewed_user: @reviewed_user,
      match_id: avis_params[:match_id],
      rating: avis_params[:rating],
      content: avis_params[:content]
    )

    # Pundit vérifie l'autorisation de base (pas se noter soi-même, connecté)
    authorize @avis

    # Répond en HTML (depuis le profil) ou JSON (depuis la modal AJAX)
    respond_to do |format|
      if @avis.save
        # Email transactionnel : informe le joueur noté qu'il a reçu un avis
        UserMailer.avis_received(@avis).deliver_later
        format.html do
          redirect_back(fallback_location: user_profil_path(@reviewed_user),
                        notice: "Votre avis a bien été enregistré !")
        end
        format.json { render json: { success: true } }
      else
        # En cas d'erreur, affiche le premier message d'erreur du modèle
        error_message = @avis.errors.full_messages.first
        format.html { redirect_back(fallback_location: user_profil_path(@reviewed_user), alert: error_message) }
        format.json { render json: { error: error_message }, status: :unprocessable_entity }
      end
    end
  end

  private

  # Liste blanche des paramètres acceptés pour un avis
  def avis_params
    params.require(:avis).permit(:match_id, :rating, :content)
  end
end
