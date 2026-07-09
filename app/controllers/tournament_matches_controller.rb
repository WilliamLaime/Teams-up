# Saisie du résultat d'un match de tournoi (Lot 3).
# On ne stocke que le vainqueur (V/D) ; le score set-par-set viendra au Lot 4.
# Quand la ronde courante est complète, la ronde/tour suivant est générée
# automatiquement (idempotent : voir SwissPairing#next_round!).
class TournamentMatchesController < ApplicationController
  before_action :set_tournament

  # PATCH /tournois/:tournament_id/tournament_matches/:id
  def update
    # Seul l'organisateur (admin ou co-organisateur) peut saisir les résultats.
    authorize @tournament, :manage?

    match = @tournament.tournament_matches.find(params[:id])
    match.assign_attributes(winner_id: match_params[:winner_id], status: "completed")

    if match.save
      # Ronde terminée → générer automatiquement la suite (idempotent).
      SwissPairing.new(@tournament).next_round! if match.tournament_round.complete?

      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), notice: "Résultat enregistré." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), alert: "Résultat invalide." }
      end
    end
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:tournament_id])
  end

  def match_params
    params.require(:tournament_match).permit(:winner_id)
  end

  # Rerend tout le tableau (rondes + bracket) — simple et robuste face aux
  # rondes générées à la volée.
  def render_board
    render turbo_stream: turbo_stream.replace(
      "tournament_board",
      partial: "tournaments/board",
      locals: { tournament: @tournament.reload }
    )
  end
end
