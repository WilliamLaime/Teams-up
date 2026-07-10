# Saisie du score set-par-set d'un match de tournoi (Lot 4).
# Le vainqueur est DÉRIVÉ du score (voir TournamentMatch#assign_score). La saisie
# est ouverte à 4 rôles (admin, co-orga, joueur A, joueur B) via TournamentMatchPolicy,
# tant que le tour n'est pas verrouillé. Quand la ronde courante est complète, la
# ronde/tour suivant est générée automatiquement (idempotent) via le moteur adapté
# au format (TournamentEngine.for(tournament).next_round!).
class TournamentMatchesController < ApplicationController
  before_action :set_tournament

  # PATCH /tournois/:tournament_id/tournament_matches/:id
  def update
    @match = @tournament.tournament_matches.find(params[:id])
    authorize @match # organisateur OU joueur du match, tour non verrouillé

    @match.assign_score(sets_param)

    if @match.save
      # Ronde terminée → générer automatiquement la suite (idempotent).
      # Aiguillage selon le format via la façade TournamentEngine.
      TournamentEngine.for(@tournament).next_round! if @match.tournament_round.reload.complete?

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

  # PATCH /tournois/:tournament_id/tournament_matches/:id/correct
  # Correction d'un score APRÈS verrouillage du tour, réservée à l'organisateur.
  # Contourne le verrou de update? (policy correct?) et, si le vainqueur change,
  # régénère l'aval devenu caduc de façon déterministe.
  def correct
    @match = @tournament.tournament_matches.find(params[:id])
    authorize @match, :correct?

    previous_winner = @match.winner_id
    @match.assign_score(sets_param)

    if @match.save
      apply_correction!(@match, previous_winner)
      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), notice: "Score corrigé." }
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

  # Répercute une correction de score :
  #   • rafraîchit toujours le classement de la phase round-robin ;
  #   • si le vainqueur a changé, détruit l'aval caduc puis le régénère (le moteur
  #     étant déterministe, il reconstruit à l'identique à partir des scores restants).
  # Politique de destruction selon la phase corrigée :
  #   • swiss   → rondes suisses postérieures + tableau final (appariements dépendants) ;
  #   • league/pool → tableau final seulement (calendrier indépendant des résultats) ;
  #   • bracket → tours postérieurs du tableau uniquement.
  def apply_correction!(match, previous_winner)
    round = match.tournament_round

    ActiveRecord::Base.transaction do
      if %w[swiss league pool].include?(round.phase)
        TournamentEngine.for(@tournament)
                        .recompute_stats_for(round.phase, apply_state: round.phase == "swiss")
      end

      # Vainqueur inchangé : le score est ajusté mais l'aval reste valide.
      next if match.winner_id == previous_winner

      @tournament.update!(status: "in_progress") if @tournament.completed?

      case round.phase
      when "swiss"
        @tournament.swiss_rounds.where("number > ?", round.number).destroy_all
        @tournament.bracket_rounds.destroy_all
      when "league", "pool"
        @tournament.bracket_rounds.destroy_all
      when "bracket"
        @tournament.bracket_rounds.where("number > ?", round.number).destroy_all
      end

      round.update!(status: "in_progress") unless round.reload.complete?

      TournamentEngine.for(@tournament).next_round!
    end
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
