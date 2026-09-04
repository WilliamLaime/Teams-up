# Inscriptions à un tournoi (rejoindre / quitter).
# Version minimale du Lot 1 : inscription directe et approuvée.
# La validation manuelle, la file d'attente et la deadline stricte viendront plus tard.
class TournamentUsersController < ApplicationController
  before_action :set_tournament

  # POST /tournois/:tournament_id/tournament_users
  def create
    # find_or_initialize_by, et non new : une personne peut DÉJÀ avoir une ligne sur
    # ce tournoi sans y occuper de place de joueur — c'est le cas du co-organisateur
    # nommé par l'admin (`role: "co_organisateur"`). Comme l'index unique
    # [tournament_id, user_id] n'autorise qu'une ligne par personne, s'inscrire
    # revient à COMPLÉTER la ligne existante, pas à en créer une seconde (ce qui
    # lèverait un RecordNotUnique non rattrapé, donc une 500).
    #
    # Construit côté belongs_to (TournamentUser.…) et PAS via
    # @tournament.tournament_users.… : ce dernier ajouterait immédiatement
    # l'enregistrement non sauvegardé à la collection en mémoire, ce qui fausserait
    # le comptage de #full? juste en dessous (le tournoi semblerait déjà complet à
    # cause de CE joueur, avant même qu'il soit inscrit).
    tournament_user = TournamentUser.find_or_initialize_by(tournament: @tournament, user: current_user)

    authorize tournament_user, :create?

    if tournament_user.player?
      redirect_to tournaments_path, alert: "Tu es déjà inscrit à ce tournoi."
      return
    end

    unless @tournament.registration_open? && !@tournament.full?
      redirect_to tournaments_path, alert: "Les inscriptions sont closes ou le tournoi est complet."
      return
    end

    # Le rôle n'est assigné qu'ici, une fois les gardes passées (cf. #full? plus haut).
    # `co_organizer` n'est jamais touché : un co-organisateur qui s'inscrit garde ses
    # droits de gestion — les deux casquettes sont indépendantes.
    tournament_user.role   = "joueur"
    tournament_user.status = "approved"

    if tournament_user.save
      redirect_to tournaments_path, notice: "Tu es inscrit au tournoi « #{@tournament.name} »."
    else
      redirect_to tournaments_path, alert: "Impossible de rejoindre ce tournoi."
    end
  end

  # DELETE /tournois/:tournament_id/tournament_users/:id
  def destroy
    tournament_user = @tournament.tournament_users.find(params[:id])
    authorize tournament_user

    # Symétrique de TournamentsController#remove_co_organizer : quitter le tournoi
    # ne doit retirer que la PLACE DE JOUEUR. Un co-organisateur qui se désinscrit
    # garde ses droits de gestion, sa ligne redevient une ligne d'organisation pure.
    if tournament_user.co_organizer?
      tournament_user.update!(role: "co_organisateur")
      notice = "Tu n'es plus inscrit comme joueur, mais tu restes co-organisateur."
    else
      tournament_user.destroy
      notice = "Tu t'es désinscrit du tournoi."
    end

    redirect_to tournaments_path, notice: notice
  end

  # PATCH /tournois/:tournament_id/tournament_users/:id/withdraw
  # Déclare le forfait d'un joueur (organisateur) : victoire par forfait à ses
  # adversaires et exclusion des tours suivants (cf. WithdrawPlayer).
  def withdraw
    tournament_user = @tournament.tournament_users.find(params[:id])
    authorize tournament_user, :withdraw?

    WithdrawPlayer.new(@tournament, tournament_user).call!
    @tournament.reload

    # Turbo Stream : on rafraîchit à la fois le tableau (scores forfait) et la
    # liste des participants, SANS recharger la page — sinon l'utilisateur perd
    # l'onglet « Participants » (le show recharge toujours sur l'onglet Matchs).
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("tournament_board", partial: "tournaments/board", locals: { tournament: @tournament }),
          turbo_stream.update("tournament_participants", partial: "tournaments/participants", locals: { tournament: @tournament })
        ]
      end
      format.html do
        redirect_to tournament_path(@tournament),
                    notice: "#{tournament_user.display_name} a déclaré forfait."
      end
    end
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:tournament_id])
  end
end
