# Inscriptions à un tournoi (rejoindre / quitter).
# Version minimale du Lot 1 : inscription directe et approuvée.
# La validation manuelle, la file d'attente et la deadline stricte viendront plus tard.
class TournamentUsersController < ApplicationController
  before_action :set_tournament

  # POST /tournois/:tournament_id/tournament_users
  def create
    # Construit via TournamentUser.new (côté belongs_to), PAS via
    # @tournament.tournament_users.new : ce dernier ajoute immédiatement le
    # nouvel enregistrement (non sauvegardé) à la collection en mémoire, ce qui
    # fausserait le comptage de #full? juste en dessous (le tournoi semblerait
    # déjà complet à cause de CE joueur, avant même qu'il soit inscrit).
    tournament_user = TournamentUser.new(tournament: @tournament, user: current_user, role: "joueur", status: "approved")
    authorize tournament_user

    unless @tournament.registration_open? && !@tournament.full?
      redirect_to tournaments_path, alert: "Les inscriptions sont closes ou le tournoi est complet."
      return
    end

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

  # PATCH /tournois/:tournament_id/tournament_users/:id/withdraw
  # Déclare le forfait d'un joueur (organisateur) : victoire par forfait à ses
  # adversaires et exclusion des tours suivants (cf. WithdrawPlayer).
  def withdraw
    tournament_user = @tournament.tournament_users.find(params[:id])
    authorize tournament_user, :withdraw?

    WithdrawPlayer.new(@tournament, tournament_user).call!
    redirect_to tournament_path(@tournament),
                notice: "#{tournament_user.display_name} a déclaré forfait."
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:tournament_id])
  end
end
