# Helpers d'affichage des tournois (vue détail à onglets).
module TournamentsHelper
  # Ce TournamentUser, est-ce l'utilisateur connecté ? Sert à surligner « moi »
  # partout : ma poule, mes matchs, ma ligne de classement. Un tournoi à 32
  # joueurs affiche des dizaines de cartes identiques — sans repère, retrouver la
  # sienne demande de lire chaque nom.
  # La comparaison porte sur user_id, jamais sur le nom : deux joueurs peuvent
  # parfaitement s'appeler pareil.
  def my_player?(tournament_user)
    user_signed_in? && tournament_user.present? && tournament_user.user_id == current_user.id
  end

  # Pastille « Toi » posée à côté de mon nom. Un `aria-label` explicite : hors
  # contexte, « Toi » seul ne dit pas de qui il s'agit.
  def me_badge
    tag.span "Toi", class: "tmatch-card__me-badge", aria: { label: "C'est toi" }
  end

  # ── Forfait : « V » / « D » à la place du score ───────────────────────────────
  # Un match gagné sur forfait n'a AUCUN set saisi (`score_entered?` est faux) : la
  # carte tombait donc dans la branche « pas encore joué » et n'affichait qu'un
  # tiret. Le classement de la poule, lui, était bien recalculé — le vainqueur
  # apprenait sa victoire ailleurs que sur la carte de son propre match.
  #
  # Renvoie nil hors forfait : sur un match joué, le score en vert signale déjà le
  # vainqueur, doubler le signal alourdirait la carte pour rien.
  #
  # `winner_id.present?` n'est pas défensif par excès : `forfeit: true` sans
  # `retired_player_id` ne désigne aucun vainqueur (cf.
  # TournamentMatch#forfeit_winner_id) — dans ce cas on n'invente pas un perdant.
  # « F » plutôt que « D » pour le joueur qui a DÉCLARÉ forfait : il n'a pas perdu
  # au score, il ne s'est pas présenté, et c'est cette distinction qu'on veut voir
  # sur la carte. Le « D » subsiste pour le forfait sans partant identifié.
  def forfeit_mark(match, player)
    return if player.blank?
    return unless match.forfeit? && match.winner_id.present?
    return "F" if match.retired_player_id == player.id

    match.winner_id == player.id ? "V" : "D"
  end

  # Le « V »/« D » ci-dessus, rendu prêt à poser dans une carte. `aria-label` :
  # hors contexte, une lettre seule ne se comprend pas — un lecteur d'écran
  # annoncerait « V » sans dire de quoi il s'agit.
  #
  # `tmatch-card__forfeit-mark` est TOUJOURS posée, quelle que soit la variante de
  # carte : c'est elle qui dit « ceci est une marque de forfait ». Les trois mises
  # en page n'ajoutent qu'un modificateur de géométrie via `extra_class` — sans
  # cette classe commune, chaque variante aurait son propre nom et il n'y aurait
  # plus un seul endroit où retrouver la marque (ni en CSS, ni en test).
  # Trois états, et « F » n'est PAS `is-loser` : un forfait n'est pas une défaite
  # au score, et `is-loser` porte le barré + l'atténuation du perdant.
  def forfeit_mark_tag(match, player, extra_class: nil)
    mark = forfeit_mark(match, player)
    return if mark.nil?

    state, label = case mark
                   when "F" then ["is-forfeit", "Forfait"]
                   when "V" then ["is-winner",  "Victoire par forfait"]
                   else          ["is-loser",   "Défaite par forfait"]
                   end

    tag.span mark,
             class: ["tmatch-card__forfeit-mark", state, extra_class].compact,
             title: label,
             aria: { label: label }
  end

  # ── Chat d'organisation : pastille non-lu ────────────────────────────────────
  # Ids des matchs de ce tournoi où un message d'un AUTRE joueur attend d'être lu.
  #
  # Renvoyé sous forme d'ensemble et calculé UNE FOIS par rendu de tableau : une
  # poule affiche des dizaines de cartes, et interroger la base par carte, c'était
  # un N+1 garanti sur la page la plus consultée du tournoi.
  #
  # Pas de ligne d'accusé de lecture = n'a jamais ouvert le fil : le LEFT JOIN
  # laisse alors `last_read_at` à NULL, traité comme « tout est non-lu » — c'est
  # exactement le bon comportement pour un joueur à qui l'adversaire vient d'écrire
  # pour la première fois.
  def unread_tmatch_chat_ids(tournament)
    return Set.new unless user_signed_in?

    @unread_tmatch_chat_ids ||= {}
    @unread_tmatch_chat_ids[tournament.id] ||= begin
      tmatch_ids = TournamentMatch.joins(:tournament_round)
                                  .where(tournament_rounds: { tournament_id: tournament.id })
                                  .select(:id)

      join_sql = "LEFT JOIN tournament_match_chat_reads reads " \
                 "ON reads.tournament_match_id = messages.tournament_match_id " \
                 "AND reads.user_id = ?"
      reads_join = ActiveRecord::Base.sanitize_sql_array([join_sql, current_user.id])

      Set.new(
        Message.where(tournament_match_id: tmatch_ids)
               .where.not(user_id: current_user.id)
               .joins(reads_join)
               .where("reads.last_read_at IS NULL OR messages.created_at > reads.last_read_at")
               .distinct
               .pluck(:tournament_match_id)
      )
    end
  end

  # ── Rencontre planifiée ───────────────────────────────────────────────────────
  # Quand a lieu ce match de tournoi, en une ligne lisible (« jeudi 3 sept. 19h »).
  #
  # La date ne vit PAS sur le TournamentMatch : depuis le Lot 7, les joueurs
  # conviennent eux-mêmes de leur créneau en créant une vraie rencontre (Match)
  # rattachée à la carte (has_one :match). Tant qu'elle n'existe pas — ou qu'elle
  # n'a pas de date, la colonne étant nullable — il n'y a rien à annoncer : on
  # renvoie `nil` pour que l'appelant n'affiche aucun nœud plutôt qu'un libellé vide.
  #
  # Le jour est affiché en DATE ABSOLUE (« jeudi 3 sept. »), volontairement pas
  # via `match_day_label` (ApplicationHelper) qui dit « Jeudi » tout court en deçà
  # d'une semaine : sur un tournoi qui s'étale sur plusieurs semaines, « Jeudi »
  # ne dit pas DE QUEL jeudi il s'agit, et deux cartes de deux journées
  # différentes portaient le même libellé. Le mois est abrégé (cf.
  # `abbr_month_names` dans config/locales/fr.yml) pour tenir sur une carte dense.
  def tournament_match_schedule(tournament_match)
    match = tournament_match.match
    return if match.nil? || match.date.blank?

    day  = I18n.l(match.date, format: "%A %-d %b")
    hour = tournament_hour(match)
    return day if hour.nil?

    "#{day} #{hour}"
  end

  # Heure seule d'une rencontre, à la convention du projet : « 19h » plutôt que
  # « 19h00 », « 17h45 » quand il y a des minutes (cf. _overview). nil si la
  # rencontre n'a pas d'heure — la colonne est nullable.
  #
  # Extraite de `tournament_match_schedule` parce que le calendrier affiche
  # l'heure NUE dans ses vignettes (le jour est déjà porté par la case du
  # calendrier) : sans cette extraction, la convention serait recopiée à deux
  # endroits et finirait par diverger.
  def tournament_hour(match)
    return if match.nil? || match.time.blank?

    match.time.strftime(match.time.strftime("%M") == "00" ? "%Hh" : "%Hh%M")
  end

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
  # classement. `rounds.key?` écarte celles qui ne sont pas encore ouvertes.
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

  # D'où viendra le joueur qui occupera une case encore vide du tableau final :
  # « Vainqueur demi-finale 1 », « Vainqueur quart de finale 3 ».
  #
  # Une case de tour N+1 est nourrie par deux matchs précis du tour N (les
  # matchs 2p et 2p+1, cf. BracketBuilder#advance!) : sa provenance est donc
  # connue AVANT que le moindre match soit joué. « À déterminer » ne disait rien
  # d'une information que la structure du tableau donne pourtant — impossible de
  # se projeter (« si je gagne mon quart, je tombe où ? »). Même intention que les
  # barrages, qui annoncent déjà « 2e de Poule A » (cf. _barrage_phase).
  #
  # `feeder_position` est l'index 0-based du match nourricier DANS le tour
  # précédent ; on l'affiche en 1-based, comme le lisent les joueurs.
  # Renvoie nil pour la première colonne : ses occupants viennent de la phase
  # qualificative (poules, barrages, ronde suisse), dont l'appariement dépend du
  # format et n'est PAS déductible ici — mieux vaut ne rien dire que dire faux.
  def bracket_feeder_label(round_index, feeder_position, total_rounds)
    return if round_index.zero?

    stage  = bracket_stage_label(round_index - 1, total_rounds)
    number = feeder_position + 1

    singular = { "Finale" => "finale", "Demi-finales" => "demi-finale",
                 "Quarts" => "quart de finale", "8es" => "8e de finale" }[stage]

    # Tour lointain (« Tour 3 ») : pas de forme singulière naturelle, on nomme
    # explicitement le match pour éviter un « Vainqueur tour 3 2 » illisible.
    return "Vainqueur match #{number} du #{stage.downcase}" if singular.nil?

    "Vainqueur #{singular} #{number}"
  end

  # Têtes de série attendues sur une case de la PREMIÈRE colonne du tableau final
  # (8es, quarts… selon la taille), sous la forme ["Tête de série 1", "Tête de
  # série 8"]. nil quand le tableau n'est pas seedé (voir plus bas).
  #
  # L'appariement du premier tour n'a rien d'aléatoire : BracketBuilder place les
  # entrants selon le seeding standard 1 vs N, 2 vs N-1… (cf. seed_order), donc la
  # case p oppose des têtes de série connues AVANT que le premier qualifié soit
  # désigné. « À déterminer » cachait cette information et empêchait de se
  # projeter (« si je sors 3e des poules, je joue le 6e, dans la moitié basse »).
  #
  # Réservé au tableau PRINCIPAL (`phase_key == "bracket"`) : la consolante et les
  # matchs de classement se construisent avec `persist_seeds: false`, où la
  # position n'est qu'un ordre d'arrivée et non une force — y écrire « Tête de
  # série 3 » serait faux.
  def bracket_seed_labels(size, position)
    return if size.to_i < 2

    order = BracketBuilder.seed_order(size)
    [order[position * 2], order[(position * 2) + 1]].map do |seed|
      "Tête de série #{seed}" if seed
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
    # `barrage_rounds.any?` et NON `barrage_expected?` (cf. board_phases) : la
    # phase est certes préfigurée dès le lancement, mais y ATTERRIR d'emblée
    # ouvrirait une section de cases vides alors que les poules se jouent.
    return "barrage" if tournament.barrage_rounds.any?

    "main"
  end

  # Une section de phase doit-elle arriver masquée dans le HTML ?
  #
  # Toutes les phases (poules, barrages, tableau final, consolante, classement)
  # sont rendues côté serveur, et c'est le contrôleur Stimulus qui n'en laisse
  # qu'une visible — mais seulement une fois le JavaScript chargé. Sans attribut
  # `hidden` d'origine, toutes s'empilaient donc à l'écran pendant un instant :
  # au rechargement, on voyait la section des barrages surgir en bas de page puis
  # disparaître, sur n'importe quel onglet du tournoi.
  #
  # On pose donc l'état initial côté serveur, avec la même phase par défaut que
  # celle du contrôleur. Reste au plus UNE bascule au connect, quand une phase
  # différente a été mémorisée en sessionStorage — un échange net, pas un
  # empilement.
  def phase_section_hidden?(tournament, phase_key)
    phase_key != default_board_phase(tournament)
  end

  # Les phases réellement présentes dans le board, dans l'ordre de déroulement :
  # [clé data-phase, libellé, icône Lucide]. Source unique du sélecteur (_phase_nav)
  # — une phase ajoutée ici apparaît sans toucher au JS, qui apparie sur
  # `dataset.phase` (cf. tournament_phase_switch_controller.js).
  def board_phases(tournament)
    main_label, main_icon = round_robin_phase_meta(tournament)
    phases = [["main", main_label, main_icon]]

    # Même condition que _board.html.erb : la pastille apparaît dès le lancement,
    # la section étant préfigurée avec des cases « À déterminer ».
    phases << ["barrage", "Barrages", "git-branch-plus"] if tournament.barrage_expected?
    # Même condition que _board.html.erb : un Critérium à poule unique (≤ 7
    # joueurs) n'a pas de tableau, la pastille ouvrirait une section vide.
    phases << ["bracket", "Tableau final", "trophy"] if tournament.bracket_expected?
    # Même condition que _board.html.erb : préfigurée dès le lancement, elle aussi.
    phases << ["consolation", "Consolante", "life-buoy"] if tournament.consolation_expected?
    # « Matchs de classement », et non « Classement » : la pastille était homonyme
    # de l'ONGLET Classement juste au-dessus, qui montre tout autre chose (le
    # classement lui-même, pas les matchs qui le décident). Le libellé reprend
    # celui de la section (_classification_phase). Le JS apparie sur `data-phase`,
    # inchangé.
    phases << ["classification", "Matchs de classement", "list-ordered"] if classification_tables(tournament).any?

    phases
  end

  # ── Destinations de poule (Critérium) ───────────────────────────────────────
  # Où va chaque position de poule à l'issue des poules : tableau final, barrage
  # ou consolante. RIEN n'est codé en dur — la réponse est lue dans les sources
  # déclarées par CriteriumStructure (`PoolQualifiers[rang]`), donc un changement
  # de règlement se fait à un seul endroit. { rang => :bracket|:barrage|:consolation }.
  #
  # Memoïsé par tournoi : appelé une fois par ligne de chaque table de poule.
  def pool_destinations(tournament)
    @pool_destinations ||= {}
    @pool_destinations[tournament.id] ||= begin
      # ⚠️ La garde `criterium?` est ce qui protège les autres formats, PAS
      # l'absence de données : `pool_position_of` répond très bien pour un tournoi
      # au format « poules », qui n'a pourtant aucune structure de Critérium.
      if tournament.criterium?
        tournament.criterium_structure.nodes.each_with_object({}) do |node, index|
          destination = destination_of(node)
          next if destination.nil?

          node.sources.each do |source|
            next unless source.is_a?(CriteriumStructure::PoolQualifiers)

            index[source.rank] = destination
          end
        end
      else
        {}
      end
    end
  end

  # Le nœud « barrage » est un transit, les deux autres racines sont les tableaux.
  # Les mini-tableaux de classement n'ont aucune source de poule : ils sortent
  # d'eux-mêmes de la boucle ci-dessus.
  def destination_of(node)
    case node.key
    when "barrage" then :barrage
    when "ok"      then :bracket
    when "ko"      then :consolation
    end
  end

  def pool_destination_for(tournament, tournament_user)
    rank = tournament.pool_position_of(tournament_user)
    rank && pool_destinations(tournament)[rank]
  end

  # Afficher les destinations n'a de sens que tant qu'elles sont une PRÉDICTION.
  # `final_phase_started?` est la bonne coupure : dès que les barrages existent,
  # les placements réels sont connus et posés en `state: "qualified"` — une
  # prédiction contredirait alors le tableau, et deux liserés se disputeraient la
  # même ligne.
  #
  # `uniq.size > 1` retire l'indicateur du mode intégral, où tout le monde va au
  # tableau final : un liseré vert partout n'informe de rien.
  def show_pool_destinations?(tournament)
    tournament.criterium? && tournament.in_progress? && !tournament.final_phase_started? &&
      pool_destinations(tournament).values.uniq.size > 1
  end

  # Libellé et icône d'une destination. L'icône est LITTÉRALEMENT celle de la
  # pastille de phase correspondante (cf. board_phases) : la table de poule
  # annonce ainsi la phase avec le signe qu'on retrouvera dans le board.
  DESTINATION_META = {
    bracket:     ["Va au tableau final", "trophy"],
    barrage:     ["Passe par les barrages", "git-branch-plus"],
    consolation: ["Descend en consolante", "life-buoy"]
  }.freeze

  def destination_label(destination) = DESTINATION_META.dig(destination, 0)
  def destination_icon(destination)  = DESTINATION_META.dig(destination, 1)

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

  # ── Poules ────────────────────────────────────────────────────────────────────

  # Nom d'affichage d'une poule à partir de son index 0-based : 0 → "Poule A".
  # Source unique du libellé, partagée par le sélecteur de poules (_pool_phase) et
  # l'onglet Classement (_ranking) — les deux doivent nommer la même poule pareil.
  def pool_label(pool_index)
    "Poule #{('A'.ord + pool_index.to_i).chr}"
  end

  # Index de MA poule dans ce tournoi, ou nil si je n'y suis pas inscrit.
  #
  # Lu depuis l'INSCRIPTION et non depuis les matchs affichés : dans une poule de
  # 3, un joueur est exempt une journée sur trois — sa poule doit rester la sienne
  # le jour où il n'y joue pas.
  def my_pool_index(tournament)
    tournament.tournament_users.players.approved.find { |tu| my_player?(tu) }&.pool
  end

  # Matchs de la phase de poules, groupés par poule et ordonnés journée puis
  # position : { index_poule => [TournamentMatch, ...] }.
  #
  # UNE seule requête pour toutes les poules, puis regroupement en mémoire — même
  # motif que Tournament#pool_standings, qui charge déjà les matchs de poule en
  # bloc : la vue affiche jusqu'à 8 poules d'un coup, une requête par poule serait
  # un N+1 immédiat. Les associations lues par la carte (_tmatch_scoreline :
  # joueurs, utilisateurs, rencontre rattachée, tour pour le verrouillage) sont
  # préchargées pour la même raison.
  #
  # Les BYES sont exclus : « exempt cette journée » n'est pas une confrontation, et
  # dans une poule impaire chaque joueur en a un — autant de cartes vides à faire
  # défiler avant d'atteindre les vrais matchs.
  def pool_matches(tournament)
    TournamentMatch.joins(:tournament_round)
                   .where(tournament_rounds: { tournament_id: tournament.id, phase: "pool" })
                   .where(is_bye: false)
                   .includes(:match, :tournament_round, player_a: :user, player_b: :user)
                   .to_a
                   .sort_by { |m| [m.tournament_round.number, m.position.to_i] }
                   .group_by { |m| m.player_a.pool }
  end

  # ── Calendrier ────────────────────────────────────────────────────────────────
  # Rencontres du tournoi POSITIONNÉES dans le temps, triées par date puis heure.
  #
  # La date ne vit pas sur le TournamentMatch mais sur le Match rattaché (cf.
  # tournament_match_schedule) : une carte sans rencontre, ou dont la rencontre
  # n'a pas encore de date, n'a tout simplement pas de case dans une grille de
  # calendrier. Le `joins(:match)` (jointure interne) écarte les premières, le
  # scope `Match.scheduled` les secondes.
  #
  # Le `includes` est celui de `pool_matches`, pour la même raison : la vignette
  # lit les joueurs et leur utilisateur, le tour (libellé de phase) et la
  # rencontre (heure et lien) — sans préchargement, c'est 4 requêtes par vignette.
  # `joins` filtre en SQL, `includes` précharge pour la lecture : les deux sont
  # nécessaires, ils ne font pas le même travail.
  #
  # Les BYES sont exclus, comme partout : « exempt » n'est pas une confrontation.
  #
  # Le tri est fait en Ruby et non en SQL : quelques dizaines de lignes tout au
  # plus, et cela évite un ORDER BY avec NULLS LAST sur `matches.time` (nullable).
  def calendar_matches(tournament)
    TournamentMatch.joins(:tournament_round, :match)
                   .where(tournament_rounds: { tournament_id: tournament.id })
                   .where(is_bye: false)
                   .merge(Match.scheduled)
                   .includes(:match, :tournament_round, player_a: :user, player_b: :user)
                   .to_a
                   .sort_by { |m| [m.match.date, m.match.time || Time.zone.parse("00:00")] }
  end

  # Contexte d'une rencontre affiché sur sa vignette de calendrier : sa POULE
  # quand elle en a une, son tour sinon (« Journée 3 », « Quarts »…).
  #
  # La poule ne vit pas sur la rencontre mais sur l'INSCRIPTION
  # (`tournament_users.pool`), lue côté joueur A : en phase de poules, les deux
  # joueurs sont par construction dans la même — c'est justement la définition
  # d'une poule. Hors de cette phase, l'information n'a pas de sens : barrages et
  # tableau final font délibérément se rencontrer des joueurs de poules
  # différentes (cf. CriteriumFlow#avoid_same_pool), afficher « Poule A » y serait
  # trompeur. On retombe alors sur `round_label`, déjà utilisé par le board.
  #
  # `bracket_rounds` est passé par l'appelant, chargé UNE fois pour toute la
  # grille : `round_label` en a besoin pour situer un tour du tableau final, et le
  # relire par rencontre serait un N+1 silencieux.
  def calendar_context_label(tmatch, bracket_rounds)
    round = tmatch.tournament_round
    pool  = tmatch.player_a&.pool

    return pool_label(pool) if round.phase == "pool" && pool.present?

    round_label(round, bracket_rounds)
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
