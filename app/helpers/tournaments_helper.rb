# Helpers d'affichage des tournois (vue détail à onglets).
module TournamentsHelper
  # Tours à afficher en colonnes dans le bracket viewer : les rondes de la phase
  # round-robin du format (suisse / championnat / poules) dans l'ordre, PUIS les
  # tours du tableau final. Renvoie un tableau (les colonnes du ruban).
  # Les barrages du Critérium s'intercalent entre les poules et le tableau final :
  # sans eux, le bracket viewer sauterait la moitié de la phase finale.
  # Les phases du Critérium s'intercalent entre les poules et le tableau final, ou
  # le suivent : sans elles, le bracket viewer s'arrêterait au tableau principal et
  # la moitié des matchs du format seraient invisibles en Vue d'ensemble.
  def display_rounds(tournament)
    tournament.swiss_rounds.to_a +
      tournament.league_rounds.to_a +
      tournament.pool_rounds.to_a +
      tournament.barrage_rounds.to_a +
      tournament.bracket_rounds.to_a +
      tournament.tournament_rounds.consolation.main_branch.ordered.to_a +
      classification_tables(tournament).flat_map(&:last)
  end

  # Les mini-tableaux de classement RÉELLEMENT créés, triés par la première place
  # qu'ils attribuent (le 3e/4e avant le 5e-8e). Chaque entrée = [nœud, ses tours].
  #
  # On part de la structure et non de la base pour l'ORDRE : les branches sont
  # créées dans l'ordre où leurs sources se terminent, qui n'est pas l'ordre du
  # classement. Les paliers d'ex æquo sont naturellement exclus — ils n'ont aucun
  # tour, donc aucune clé dans `rounds`.
  def classification_tables(tournament)
    return [] unless tournament.criterium?

    rounds = tournament.tournament_rounds.classification.ordered.group_by(&:branch)
    tournament.criterium_structure.nodes
              .select { |node| node.phase == "classification" && rounds.key?(node.branch) }
              .sort_by(&:first_place)
              .map { |node| [node, rounds[node.branch]] }
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
    return "Barrages" if round.phase == "barrage"

    # Un tour de consolante ou de classement (Critérium) n'appartient PAS à
    # `bracket_rounds` : `index` renverrait nil, et `nil.to_i` étiquetterait
    # silencieusement le tour comme le PREMIER du tableau final — un libellé faux
    # et indétectable. On préfère un libellé neutre mais juste.
    index = bracket_rounds.index(round)
    return "Tour #{round.number}" if index.nil?

    bracket_stage_label(index, bracket_rounds.size)
  end

  # Libellé d'un tour du tableau final à partir de sa position (0-based) et du
  # nombre total de tours prévus — fonction pure, sans dépendance à un
  # TournamentRound réel, pour pouvoir étiqueter aussi bien les tours déjà joués
  # (round_label ci-dessus) que les colonnes "À déterminer" pas encore jouées
  # (cf. _bracket.html.erb, Tournament#expected_bracket_round_count).
  def bracket_stage_label(index, total)
    # Distance à la fin : 0 = finale, 1 = demies, 2 = quarts, 3 = 8es.
    from_end = total - 1 - index
    case from_end
    when 0 then "Finale"
    when 1 then "Demi-finales"
    when 2 then "Quarts"
    when 3 then "8es"
    else "Tour #{index + 1}"
    end
  end

  # Libellé + icône Lucide de la phase round-robin du tournoi (ronde suisse /
  # championnat / poules — un seul de ces 3 formats existe par tournoi) pour
  # le sélecteur de phase (_phase_nav, bascule round-robin vs tableau final).
  def round_robin_phase_meta(tournament)
    case tournament.format
    when "poules", "criterium_federal" then ["Poules", "layout-grid"]
    when "championnat" then ["Championnat", "swords"]
    else ["Ronde Suisse", "swords"]
    end
  end

  # Phase à afficher par défaut dans le board : la plus avancée qui existe. Le
  # Critérium ajoute un palier entre les poules et le tableau final, et un tournoi
  # peut y stationner longtemps (les barrages sont un tour complet à jouer).
  # Le tableau final reste la phase par défaut même quand la consolante et les
  # matchs de classement existent : c'est là que se joue le titre, donc ce que
  # l'utilisateur vient voir. Les autres phases sont à un clic.
  def default_board_phase(tournament)
    return "bracket" if tournament.bracket_started?
    return "barrage" if tournament.barrage_rounds.any?

    "main"
  end

  # Les phases réellement présentes dans le board, dans l'ordre de déroulement :
  # [clé data-phase, libellé, icône Lucide]. Source unique du sélecteur (_phase_nav)
  # — une phase ajoutée ici apparaît sans toucher au JS, qui apparie sur
  # `dataset.phase` (cf. tournament_phase_switch_controller.js).
  def board_phases(tournament)
    main_label, main_icon = round_robin_phase_meta(tournament)
    phases = [["main", main_label, main_icon]]

    phases << ["barrage", "Barrages", "git-branch-plus"] if tournament.barrage_rounds.any?
    phases << ["bracket", "Tableau final", "trophy"]
    phases << ["consolation", "Consolante", "life-buoy"] if tournament.tournament_rounds.consolation.exists?
    phases << ["classification", "Classement", "list-ordered"] if classification_tables(tournament).any?

    phases
  end

  # Pastilles carrées de bilan V/D en en-tête d'un « bracket de score » de ronde
  # suisse (façon Lolesports) — matérialise le bilan du groupe EN ENTRANT dans ce
  # tour (cf. Tournament#swiss_entering_records) : carrés verts = victoires, rouges
  # = défaites, gris = cases restantes avant qualification/élimination. Complétées
  # à un total fixe pour que toutes les pastilles d'une même ronde aient la même
  # largeur : le nombre de cases dépend des seuils DU TOURNOI (personnalisables
  # depuis le Lot 7), un joueur ne pouvant entrer dans un tour qu'avec au plus
  # (seuil - 1) victoires et (seuil - 1) défaites.
  def score_bracket_pips(wins, losses, tournament)
    slots = (tournament.wins_to_qualify - 1) + (tournament.losses_to_eliminate - 1)
    pips = (["win"] * wins) + (["loss"] * losses)
    pips += ["pending"] * (slots - pips.size) if pips.size < slots
    safe_join(pips.map { |kind| content_tag(:span, "", class: "score-bracket__pip score-bracket__pip--#{kind}") })
  end

  # ── Modale de score ───────────────────────────────────────────────────────────
  # Bouton d'ouverture de la modale de score partagée (contrôleur Stimulus
  # tournament-score). Les 3 usages — « Saisir/Modifier », « Détail » (lecture
  # seule) et « Corriger » (poste sur l'action correct) — ne diffèrent que par le
  # libellé, la classe, l'URL de soumission et le flag `editable` : tout le reste
  # (règles du sport, sets déjà saisis, noms des joueurs) est identique, d'où ce
  # helper unique plutôt que 6 blocs de data-* recopiés dans _tmatch et
  # _tmatch_scoreline.
  #
  # IMPORTANT : les règles viennent de `match.scoring_rules` (et NON de
  # `match.tournament.sport.scoring_rules`), seule source qui tient compte de la
  # phase — au ping-pong, 3 sets gagnants en poule mais 4 en phase finale.
  def score_modal_button(match, label:, editable:, url: nil, css_class: "tmatch-card__score-btn")
    rules = match.scoring_rules

    button_tag type: "button", class: css_class, data: {
      action: "tournament-score#open",
      tournament_score_url_param: url,
      tournament_score_mode_param: rules[:mode],
      tournament_score_allow_draw_param: rules[:allow_draw],
      tournament_score_best_of_param: rules[:best_of],
      tournament_score_sets_to_win_param: match.sets_to_win,
      tournament_score_target_param: rules[:target],
      tournament_score_win_by_two_param: rules[:win_by_two],
      tournament_score_cap_param: rules[:cap],
      tournament_score_sets_param: match.sets.to_json,
      tournament_score_name_a_param: match.player_a.display_name,
      tournament_score_name_b_param: match.player_b.display_name,
      tournament_score_editable_param: editable
    }.compact do # compact : `cap: nil` (pas de plafond) ne doit pas devenir la chaîne ""
      label
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
