# Helpers d'affichage des tournois (vue détail à onglets).
module TournamentsHelper
  # Tours à afficher en colonnes dans le bracket viewer : les rondes de la phase
  # round-robin du format (suisse / championnat / poules) dans l'ordre, PUIS les
  # tours du tableau final. Renvoie un tableau (les colonnes du ruban).
  def display_rounds(tournament)
    tournament.swiss_rounds.to_a +
      tournament.league_rounds.to_a +
      tournament.pool_rounds.to_a +
      tournament.bracket_rounds.to_a
  end

  # Libellé lisible d'un tour, centralise la logique jusqu'ici inline dans les vues.
  #   • phase suisse             → "Ronde N".
  #   • phase championnat/poules → "Journée N".
  #   • tableau final            → dérivé de la distance à la finale (Finale /
  #     Demi-finales / Quarts / 8es), sinon "Tour N" pour les tours plus lointains.
  # `bracket_rounds` = la liste ordonnée des tours du tableau final (pour situer `round`).
  def round_label(round, bracket_rounds)
    return "Ronde #{round.number}" if round.phase == "swiss"
    return "Journée #{round.number}" if %w[league pool].include?(round.phase)

    # Distance à la fin : 0 = finale, 1 = demies, 2 = quarts, 3 = 8es.
    from_end = bracket_rounds.size - 1 - bracket_rounds.index(round).to_i
    case from_end
    when 0 then "Finale"
    when 1 then "Demi-finales"
    when 2 then "Quarts"
    when 3 then "8es"
    else "Tour #{round.number}"
    end
  end

  # Pastilles carrées de bilan V/D en en-tête d'un « bracket de score » de ronde
  # suisse (façon Lolesports) — matérialise le bilan du groupe EN ENTRANT dans ce
  # tour (cf. Tournament#swiss_entering_records) : carrés verts = victoires, rouges
  # = défaites, gris = cases restantes avant qualification/élimination. Complétées
  # à un total fixe (2 victoires max + 2 défaites max avant que le groupe soit
  # qualifié/éliminé, cf. TournamentUser::WINS_TO_QUALIFY/LOSSES_TO_ELIMINATE)
  # pour que toutes les pastilles d'une même ronde aient la même largeur.
  SCORE_BRACKET_PIP_SLOTS = (TournamentUser::WINS_TO_QUALIFY - 1) + (TournamentUser::LOSSES_TO_ELIMINATE - 1)

  def score_bracket_pips(wins, losses)
    pips = (["win"] * wins) + (["loss"] * losses)
    pips += ["pending"] * (SCORE_BRACKET_PIP_SLOTS - pips.size) if pips.size < SCORE_BRACKET_PIP_SLOTS
    safe_join(pips.map { |kind| content_tag(:span, "", class: "score-bracket__pip score-bracket__pip--#{kind}") })
  end

  # Message affiché dans l'état vide de la page liste, selon l'onglet actif
  # (TournamentsController::TABS).
  def tab_empty_message(tab)
    {
      mine: "Tu n'es inscrit à aucun tournoi en cours pour l'instant.",
      join: "Aucun tournoi à rejoindre pour le moment.",
      ongoing: "Aucun tournoi en cours actuellement.",
      completed: "Aucun tournoi terminé pour l'instant."
    }.fetch(tab, "Aucun tournoi pour le moment.")
  end
end
