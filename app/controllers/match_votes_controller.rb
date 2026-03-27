class MatchVotesController < ApplicationController
  # POST /matches/:match_id/match_votes
  def create
    # Récupère le match depuis l'URL
    @match = Match.find(params[:match_id])

    # Construit le vote avec le joueur connecté comme votant
    @vote = MatchVote.new(
      voter: current_user,
      match: @match,
      voted_for_id: match_vote_params[:voted_for_id]
    )

    # Vérifie l'autorisation via Pundit (voir MatchVotePolicy)
    authorize @vote

    respond_to do |format|
      if @vote.save
        format.html { redirect_back(fallback_location: root_path, notice: "Vote enregistré !") }
        format.json { render json: { success: true } }
      else
        error_msg = @vote.errors.full_messages.first || "Une erreur est survenue."
        format.html { redirect_back(fallback_location: root_path, alert: error_msg) }
        format.json { render json: { error: error_msg }, status: :unprocessable_entity }
      end
    end
  end

  private

  def match_vote_params
    params.require(:match_vote).permit(:voted_for_id)
  end
end
