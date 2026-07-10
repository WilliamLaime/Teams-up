# Saisie du score set-par-set d'un match de tournoi (Lot 4).
# Le vainqueur est DÉRIVÉ du score (voir TournamentMatch#assign_score). La saisie
# est ouverte à 4 rôles (admin, co-orga, joueur A, joueur B) via TournamentMatchPolicy,
# tant que le tour n'est pas verrouillé. Quand la ronde courante est complète, la
# ronde/tour suivant est générée automatiquement (idempotent : SwissPairing#next_round!).
class TournamentMatchesController < ApplicationController
  before_action :set_tournament

  # PATCH /tournois/:tournament_id/tournament_matches/:id
  def update
    @match = @tournament.tournament_matches.find(params[:id])
    authorize @match # organisateur OU joueur du match, tour non verrouillé

    @match.assign_score(sets_param)

    if @match.save
      # Ronde terminée → générer automatiquement la suite (idempotent).
      SwissPairing.new(@tournament).next_round! if @match.tournament_round.reload.complete?

      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), notice: "Score enregistré." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), alert: @match.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_tournament
    @tournament = Tournament.from_param(params[:tournament_id])
  end

  # Le formulaire poste deux tableaux parallèles `games_a[]` / `games_b[]` (une
  # entrée par set). On les zippe en paires [[a, b], …] — plus fiable que des
  # tableaux imbriqués, que l'encodage de formulaire aplatirait.
  def sets_param
    permitted = params.require(:tournament_match).permit(games_a: [], games_b: [])
    Array(permitted[:games_a]).zip(Array(permitted[:games_b]))
  end

  # Rerend tout le tableau (rondes + bracket) — simple et robuste face aux
  # rondes générées à la volée. `update` (et non `replace`) : on remplace le
  # CONTENU de #tournament_board sans détruire le conteneur ni son contrôleur
  # Stimulus (bracket), donc la cible reste valide pour les saisies suivantes.
  def render_board
    render turbo_stream: turbo_stream.update(
      "tournament_board",
      partial: "tournaments/board",
      locals: { tournament: @tournament.reload }
    )
  end
end
