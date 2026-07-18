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
