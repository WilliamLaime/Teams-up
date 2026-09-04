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
      round = @match.tournament_round.reload
      # Classement rafraîchi dès CE score saisi (Lot 6) — sans attendre que toute la
      # ronde soit jouée. Idempotent, même appel que apply_correction! ci-dessous.
      if %w[swiss league pool].include?(round.phase)
        swiss = round.phase == "swiss"
        TournamentEngine.for(@tournament)
                        .recompute_stats_for(round.phase, apply_state: swiss, count_byes: swiss)
      end

      # Ronde terminée → générer automatiquement la suite (idempotent).
      # Aiguillage selon le format via la façade TournamentEngine.
      #
      # Critérium en phase finale : la progression est ANTICIPÉE (une demi-finale
      # naît dès que ses deux quarts sont joués, cf. BracketBuilder en mode
      # incrémental), donc le moteur doit tourner à CHAQUE score et pas seulement
      # à la fin du tour — sinon le match suivant n'existerait jamais.
      advance_eagerly = @tournament.criterium? && Tournament::FINAL_PHASES.include?(round.phase)
      TournamentEngine.for(@tournament).next_round! if advance_eagerly || round.complete?

      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to tournament_path(@tournament), notice: "Score enregistré." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_score_errors }
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
        format.turbo_stream { render_score_errors }
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
  #
  # ⚠️ Critérium Fédéral : `bracket_rounds` ne désigne QUE le tableau final (il est
  # scopé sur la branche principale), donc détruire « le tableau final » y laisserait
  # les barrages, la consolante et les matchs de classement en place, calculés depuis
  # un classement de poule désormais faux. Deux cas s'y distinguent :
  #   • correction en POULE → le classement de départ change, donc tout est caduc :
  #     on détruit la phase finale entière et CriteriumFlow la rebâtit (déterministe,
  #     il reconstruit à l'identique ce que la correction n'a pas invalidé) ;
  #   • correction DANS la phase finale → les branches sont parallèles, un quart de
  #     finale corrigé ne dit rien de la consolante. CriteriumFlow#reconcile! ne
  #     détruit que l'aval réellement périmé, et les scores voisins survivent.
  def apply_correction!(match, previous_winner)
    round = match.tournament_round

    ActiveRecord::Base.transaction do
      if %w[swiss league pool].include?(round.phase)
        swiss = round.phase == "swiss"
        TournamentEngine.for(@tournament)
                        .recompute_stats_for(round.phase, apply_state: swiss, count_byes: swiss)
      end

      # Vainqueur inchangé : le score est ajusté mais l'aval reste valide.
      next if match.winner_id == previous_winner

      @tournament.update!(status: "in_progress") if @tournament.completed?

      if @tournament.criterium? && Tournament::FINAL_PHASES.include?(round.phase)
        CriteriumFlow.new(@tournament).reconcile!(from: round)
      elsif @tournament.criterium?
        @tournament.tournament_rounds.final_phase.destroy_all
      else
        case round.phase
        when "swiss"
          @tournament.swiss_rounds.where("number > ?", round.number).destroy_all
          @tournament.bracket_rounds.destroy_all
        when "league", "pool"
          @tournament.bracket_rounds.destroy_all
        when "bracket"
          @tournament.bracket_rounds.where("number > ?", round.number).destroy_all
        end
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
    render turbo_stream: [
      turbo_stream.update("tournament_board",
                          partial: "tournaments/board",
                          locals: { tournament: @tournament.reload }),
      # L'onglet Calendrier affiche les scores : sa source de vignettes vit hors du
      # board (il ne doit pas être écrasé par les rerendus du tableau), elle
      # resterait donc figée sur l'ancien score. Le contrôleur Stimulus redessine
      # la période affichée dès que cette source est remplacée.
      #
      # `replace` et non `update` : le partial rend LE conteneur lui-même (il porte
      # l'id et la cible Stimulus). En `update` on l'imbriquerait dans son propre
      # id — et surtout la cible ne serait jamais reconnectée, donc jamais redessinée.
      turbo_stream.replace("tournament_calendar_source",
                          partial: "tournaments/calendar_source",
                          locals: { tournament: @tournament }),
      # Efface le bandeau d'erreur d'une tentative précédente : la modale n'est pas
      # rerendue (elle vit hors du board), ses erreurs resteraient donc affichées.
      score_errors_stream([])
    ]
  end

  # Score refusé par le modèle : on NE touche PAS au tableau (rien n'a changé en
  # base) et on renvoie les messages dans la modale, restée ouverte.
  #
  # `:unprocessable_entity` est ce qui maintient la modale ouverte : le contrôleur
  # Stimulus ne la ferme que si `turbo:submit-end` signale un succès. En 200, un
  # score invalide se refermait sans un mot — il paraissait enregistré alors qu'il
  # ne l'était pas.
  def render_score_errors
    render turbo_stream: score_errors_stream(@match.errors.full_messages),
           status: :unprocessable_entity
  end

  def score_errors_stream(messages)
    turbo_stream.update("score_modal_errors",
                        partial: "tournaments/score_errors",
                        locals: { messages: messages })
  end
end
