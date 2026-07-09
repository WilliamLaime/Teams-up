# Inscriptions à un tournoi (rejoindre / quitter).
# Version minimale du Lot 1 : inscription directe et approuvée.
# La validation manuelle, la file d'attente et la deadline stricte viendront plus tard.
class TournamentUsersController < ApplicationController
  before_action :set_tournament

  # POST /tournois/:tournament_id/tournament_users
  def create
    tournament_user = @tournament.tournament_users.new(user: current_user, role: "joueur", status: "approved")
    authorize tournament_user

    if tournament_user.save
      redirect_to tournaments_path, notice: "Tu es inscrit au tournoi « #{@tournament.name} »."
    else
      # Cas principal : déjà inscrit (index unique) → on ne bloque pas l'utilisateur.
      redirect_to tournaments_path, alert: "Impossible de rejoindre ce tournoi."
    end
  end

  # DELETE /tournois/:tournament_id/tournament_users/:id
  def destroy
    tournament_user = @tournament.tournament_users.find(params[:id])
    authorize tournament_user
    tournament_user.destroy
    redirect_to tournaments_path, notice: "Tu t'es désinscrit du tournoi."
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:tournament_id])
  end
end
