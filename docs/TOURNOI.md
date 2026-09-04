# Feature Tournoi — Pilotage

> Document de suivi de la feature Tournoi. À relire au démarrage de chaque session :
> il indique **où on en est** et **quelle est la prochaine étape**.
> Sources de conception : recaps réunion du 9 juillet 2026 (Notion + Claude).

---

## 🎯 Vision

Centraliser dans Teams-up la gestion des tournois amateurs (aujourd'hui sous Excel).
Le lien **Tournoi** a remplacé **Blog** dans la navbar (Blog conservé dans le footer).

**Principe structurant :** on choisit d'abord le **sport**, puis on ne propose que les
**formats compatibles** (un tournoi de foot ne se joue pas en ronde suisse ; le tennis
c'est de l'élimination directe d'emblée).

### Formats envisagés
1. **Ronde Suisse + tableau final** — 🥇 **prioritaire**. Tirage intégral à chaque ronde
   (jamais deux fois le même adversaire), 3 victoires pour se qualifier / 3 défaites pour
   être éliminé, puis Final 8 en élimination directe (têtes de série 1 et 2 séparées
   jusqu'en finale). Configs figées selon le nombre de joueurs (16, 32… ; 24 tend à planter).
2. **Phase de poules + tableau final** — plus classique. Poules incomplètes gérées via un
   joueur « vide ».
3. **Championnat** — tout le monde s'affronte, les X premiers en playoffs.
4. **Winner / Loser Bracket** — format e-sport, complexe, **à reporter** (barrages, descente
   en loser bracket, grande finale) — à confier à l'IA.

---

## 🗺️ Roadmap par lots

### ✅ Lot 1 — Page liste des tournois `[FAIT]`
- [x] Modèle `Tournament` + jointure `TournamentUser` (+ migrations)
- [x] Route `resources :tournaments, path: "tournois"` (+ `tournament_users` imbriqué)
- [x] `TournamentPolicy` + `TournamentUserPolicy` (Pundit)
- [x] `TournamentsController#index` : 3 sections + filtre sport + recherche
- [x] Vue `index` + composant `shared/_tournament_card` (réutilise les classes `.match-card*`)
- [x] `show` / `new` en squelette (placeholders vers Lot 2/3)
- [x] Inscription minimale fonctionnelle (rejoindre / quitter)
- [x] Navbar : « Tournoi » remplace « Blog » (desktop + drawer mobile)
- [x] SCSS `pages/_tournaments_index.scss` (tokens de thème + accent vert)
- [x] Seed de démo (4 tournois couvrant les 3 sections)

### ✅ Lot 2 — Flux de création d'un tournoi `[FAIT]`
- [x] Formulaire une page (sections numérotées + récap sticky) : **sport → format (compatibles) → paramètres → date/heure/lieu → joueurs & clôture**
      (calqué sur `matches/_form`, `form_with` standard, contrôleur Stimulus `tournament-form`).
- [x] Paramètres : nom, description (facultative), date, heure, lieu (place-search), deadline d'inscription (date + heure).
- [x] Nombre de joueurs : **presets 8 / 16 / 32** (structure figée affichée) **+ mode « Libre »** (saisie d'un nombre → 1 config recommandée + propositions avec récap).
- [x] Le créateur est **admin** ; **pas inscrit d'office**, mais **toggle optionnel** d'auto-inscription comme joueur.
- [x] Ajout d'un **co-organisateur** (autocomplete d'utilisateurs, réutilise `invite-search`) → drapeau `co_organizer` dans `tournament_users` (cf. la décision d'archi plus bas : un co-organisateur peut aussi être joueur).
- [x] `Sport#available_tournament_formats` (raquette → RS/Poules ; collectif → Championnat/Poules).
- [x] Comptage des joueurs scopé au rôle `joueur` (admin/co-org exclus des places).

### ✅ Lot 3 — Ronde Suisse + tableau final `[FAIT]`
- [x] Génération des rondes (tirage intégral, jamais deux fois le même adversaire) —
      service `app/services/swiss_pairing.rb` (algo pur `build_pairs` + persistance `next_round!`).
- [x] Qualification (**3 V**) / élimination (**3 D**), gestion des byes et des effectifs
      bâtards (impairs, 24…) **sans jamais planter** (fallback rematch en dernier recours).
- [x] Final N en élimination directe (**Final 4 ≤ 8 joueurs, Final 8 au-delà** via
      `Tournament#final_size`), seeding têtes de série 1 & 2 séparées jusqu'en finale —
      service `app/services/bracket_builder.rb`. Seeding aléatoire (set/point average → Lot 4).
- [x] **Résultat V/D minimal** : bouton « vainqueur » par match (pas de score détaillé →
      Lot 4), génération auto de la ronde/tour suivant quand la ronde courante est complète.
- [x] **Animation de tirage au sort** au lancement (`tournament_draw_controller.js`).
- [x] Vrai tableau à la place du placeholder `show` (partials `_board`/`_swiss_round`/
      `_bracket`/`_tmatch`) + `TournamentsController#start` + `TournamentMatchesController#update`
      + policy `manage?` (admin **et** co-organisateur via `Tournament#organizer?`).

### ✅ Lot 4 — Saisie des scores & matchs `[FAIT]`
- [x] Score **set par set** (colonne jsonb `tournament_matches.sets`), saisissable par les
      4 rôles (admin, co-orga, joueur A, joueur B) via `TournamentMatchPolicy` — le
      **vainqueur est DÉRIVÉ du score** (`TournamentMatch#assign_score` + `derive_winner_from_sets`).
- [x] Stockage détaillé + agrégation set/point average sur `tournament_users`
      (`sets_won/lost`, `points_won/lost`) recalculés par `SwissPairing#recompute_stats!`.
- [x] **Seeding réel** : `build_pairs` et `BracketBuilder#ranked` départagent par
      set average puis point average (fini l'aléatoire).
- [x] Affichage score global (ex. 2-1) sur la carte + **modale de saisie/détail** partagée
      (`_score_modal` + `tournament_score_controller.js`).
- [x] **Verrouillage** du tour : score éditable tant que la ronde n'est pas `completed`
      (garde dans la policy + le controller).
- [x] **Règles de score par sport** (`Sport#scoring_rules`) dont la **règle des 2 points
      d'écart** (ping-pong / badminton) et le `cap` (tie-break).
- [x] **Couplage Match ↔ tournoi** : « Créer la rencontre » depuis une carte
      (préremplit + inscrit les 2 joueurs) et rattachement d'un match standard à un tournoi
      via le formulaire (`matches.tournament_id` + `tournament_match_id`).

### ✅ Refonte UI — vue détail à onglets + bracket viewer `[FAIT]`
- [x] Page `/tournois/:id` réorganisée en **4 onglets** (bascule client-side sans reload,
      `tournament_tabs_controller.js`) : **Vue d'ensemble · Matchs · Participants · Classement**.
      En-tête enrichi (badge de statut + méta sport/format/participants).
      Contrainte Turbo respectée : les onglets se masquent en CSS → `#tournament_board` reste
      dans le DOM, la saisie de score en Turbo Stream continue de fonctionner.
- [x] **Matchs** : le board de jeu existant (rondes suisses + tableau final + saisie de
      score + animation de tirage) — inchangé.
- [x] **Participants** : grille des joueurs approuvés + organisateur(s), badges qualifié/éliminé.
- [x] **Classement** : table triée (V, D, set/point average, état) — `Tournament#ranked_players`.
- [x] **Bracket viewer** interactif dans **Vue d'ensemble** (lecture seule) : toutes les rondes
      en colonnes, **défilement horizontal**, **zoom** (boutons −/+ **et** curseur, via variable
      CSS `--bracket-zoom` + unités `em`, sans `transform: scale`) et **filtre par ronde**
      (chips qui isolent une colonne). `_bracket_viewer` / `_bracket_cell` +
      `bracket_viewer_controller.js` + helper `TournamentsHelper` (`display_rounds`, `round_label`).
      Note : la Vue d'ensemble n'est pas rafraîchie en Turbo Stream → reflète l'état au chargement.

### ✅ Lot 5 — Poules / championnat + abandon + correction `[FAIT]`
- [x] **Façade d'aiguillage** `TournamentEngine.for(tournament)` → renvoie le moteur du format
      (interface commune `#next_round!`). Seul endroit où le format aiguille le moteur ; les 2
      controllers (`start`, `tournament_matches#update`) ne connaissent plus que la façade.
- [x] **Championnat** (`championnat`) : `LeagueBuilder` — round-robin intégral (méthode du cercle,
      `.schedule` pur), généré **journée par journée** (calendrier déterministe, persistance lazy),
      puis top-N (`final_size`) en playoffs via `BracketBuilder`.
- [x] **Poules** (`poules`) : `PoolBuilder` — répartition en serpentin (colonne `tournament_users.pool`),
      round-robin par poule (réutilise `LeagueBuilder.schedule`), journées fusionnées par index dans
      une ronde `pool`, **qualifiés dynamiques** (`final_size / pool_count`, filet « meilleurs restants »).
- [x] **Recompute partagé** : module `RoundRobinStats` (`recompute_stats_for(phase, apply_state:)`)
      + `build_match!` (bye/forfait) mutualisés entre les 3 moteurs. `BracketBuilder.new(t, finalists:)`
      rendu injectable (non-régression suisse : `finalists` nil = comportement d'origine).
- [x] **Abandon / forfait** : état `withdrawn` (terminal, jamais recalculé), colonnes
      `tournament_matches.forfeit` + `retired_player_id`, service `WithdrawPlayer` (forfait des matchs
      en cours + exclusion des journées futures via `build_match!`), action `tournament_users#withdraw`
      (organisateur, bouton onglet Participants).
- [x] **Correction de score verrouillé** : policy `TournamentMatchPolicy#correct?` (organisateur,
      contourne le verrou), action `tournament_matches#correct` avec **régénération déterministe de
      l'aval** (swiss → rondes postérieures + bracket ; league/pool → bracket ; bracket → tours
      postérieurs). Bouton « Corriger » (ambré) dans `_tmatch` sur un tour verrouillé.
- [x] Vues : sections board Championnat/Poules (`_pool_phase`), `_swiss_round` titre paramétrable,
      classement par poule (`ranked_pools` + `_ranking_table`), helpers `display_rounds`/`round_label`.
      Tests : `league_builder_test`, `pool_builder_test`, `withdraw_player_test`, + correction dans
      `tournament_matches_controller_test`, rendus dans `tournaments_controller_test` (835 verts).

### ✅ Lot 6 — Édition, clôture des inscriptions & fin manuelle `[FAIT]`
- [x] `TournamentsController#edit`/`#update` : réutilisent `_form.html.erb` (déjà `form_with
      model: @tournament`). Champs structurels (`sport_id`/`format`/`max_players`) verrouillés
      côté serveur (`tournament_params`) ET côté vue une fois le tournoi `in_progress`/`completed`,
      pour ne pas corrompre le tirage/tableau en cours.
- [x] `TournamentPolicy#update?` passe de `owner?` à `manage?` : le co-organisateur peut
      désormais éditer les infos au même titre que l'admin (cohérent avec ses droits déjà
      existants sur le tableau/scores/forfaits).
- [x] Nouvel état `closed` (`Tournament::STATUSES`) : inscriptions fermées mais tournoi pas
      encore lancé. Clôture **automatique** dès que le tournoi devient complet
      (`TournamentUser#after_save` → `Tournament#close_registrations_if_full!`, même pattern
      réactif que `Match#recompute_player_left!`) **et** clôture/réouverture **manuelle** par
      l'organisateur (`PATCH #toggle_registrations`).
- [x] Correctif : `TournamentUsersController#create` bloque désormais réellement l'inscription
      si `!registration_open?` ou `full?` (auparavant non vérifié — un tournoi complet ou clos
      restait rejoignable).
- [x] Fin manuelle du tournoi (`PATCH #finish`, statut → `completed`) en plus de la fin
      automatique posée par `BracketBuilder` — permet de clore un tournoi abandonné.
- [x] Affichage : libellé "participants attendus" (au lieu de "joueurs") quand `max_players`
      vient d'une saisie Libre plutôt qu'un preset 8/16/32 (`Tournament#preset_capacity?`).

### ✅ Refonte UI (post-Lot 6) — ruban de rondes, phases, tableau complet `[FAIT]`
Détail par étape dans `tasks/todo.md` (phases A → E2). Livré : ruban horizontal de rondes
(`_round_ribbon` / `_round_column`, qui **remplacent l'ancien `_swiss_round`**), sélecteur de
phase round-robin ↔ tableau final (`tournament_phase_switch_controller.js`), panneau
« Qualifiés / Éliminés » (`_qualification_panel`), structure complète du tableau final avec
cases « À déterminer » (`_bracket_placeholder_cell`), vrai tirage au sort (`draw_order`),
liens vers les profils, sélecteur de journée pour les longs championnats
(`journee_selector_controller.js`). Phases D et E2 (connecteurs CSS) abandonnées après retour
utilisateur. Reste ouvert : les vérifications visuelles navigateur (impossibles en CI).

### ✅ Lot 7 — Rencontres planifiées par les joueurs, scoring par phase & structure réglable `[FAIT]`
- [x] **Scoring dépendant de la phase** : `Sport#scoring_rules` accepte `final_best_of`
      (ping-pong : 7 au lieu de 5). `TournamentMatch#scoring_rules` devient **public** et
      applique ce durcissement quand `tournament_round.phase == "bracket"` → **3 sets gagnants
      en poule / ronde suisse, 4 en phase finale**. `sets_to_win` et les validations en
      héritent. Les vues passent par `match.scoring_rules` (jamais `sport.scoring_rules`).
- [x] **Modale de score progressive** : les lignes de sets sont ajoutées **au fur et à mesure**
      (`tournament_score_controller#refreshRows`) — 3 lignes au départ, une 4e apparaît à 2-1,
      rien de plus dès qu'un joueur atteint le nombre de sets requis. Fini les 5 lignes vides.
      Les 6 blocs de `data-*` recopiés dans `_tmatch`/`_tmatch_scoreline` sont remplacés par
      le helper `score_modal_button`.
- [x] **Rencontre planifiée par les JOUEURS** : `TournamentMatchPolicy#create_match?` (2 joueurs
      + admin + co-organisateur, hors bye, une seule rencontre par confrontation). Le bouton
      « Créer la rencontre » n'est plus réservé à l'organisateur ; les joueurs choisissent
      **leur date et leur heure**. `Match` valide l'unicité de `tournament_match_id` (plus de
      500 sur l'index unique quand les deux joueurs cliquent). Le local `can_manage` devenu
      inutile a été retiré de la chaîne `_board` → `_round_ribbon` → `_round_column`.
- [x] **Rattachement élargi** : le select « Tournoi » du formulaire de match liste les tournois
      **où l'on est inscrit**, pas seulement ceux qu'on organise
      (`MatchesController#linkable_tournaments_for_select`) + un select « Confrontation »
      (`linkable_tournament_matches_map`). Le choisir recharge le formulaire prérempli par le
      serveur (`?tournament_match_id=X`) : une seule règle de préremplissage, côté serveur.
- [x] **Bannière du tournoi pilotée par le sport**, comme à la création d'un match
      (`tournament-form#updateBanner`, persistée dans `banner_image`). Bug corrigé au passage
      côté match : `updateBanner()` re-tirait une image au hasard à chaque `connect()`, donc
      une simple édition changeait l'image — le tirage n'a plus lieu que si le sport change.
- [x] **Plus d'heure de début sur un tournoi** : l'horaire se décide par rencontre. Le champ
      a disparu du formulaire (la colonne `time` reste lue pour les tournois existants).
- [x] **Structure personnalisable** (remplace l'aperçu figé et le `STRUCTURE_PRESETS`
      provisoire du Lot 2) : 4 colonnes nullables `players_per_pool`, `bracket_size`,
      `swiss_wins_to_qualify`, `swiss_losses_to_eliminate` — **vide = valeur recommandée**,
      donc aucun changement pour les tournois existants. Lues par `Tournament#pool_size` /
      `#final_size` / `#wins_to_qualify` / `#losses_to_eliminate`, seules sources de vérité des
      moteurs. `#structure_summary` est désormais **calculé** (juste pour tout effectif, mode
      Libre compris) et son miroir client vit dans `_structureText`. Réglages verrouillés une
      fois le tournoi lancé (`STRUCTURAL_FIELDS`) ; `bracket_size` validé puissance de 2, et la
      recommandation des poules est arrondie de même (3 poules → 6 qualifiés → tableau de 8).

### ✅ Lot 8 — Critérium Fédéral (ping-pong, règlement FFTT) `[FAIT]`
Nouveau format `criterium_federal`, **à côté** de `poules` : les tournois « Poules » existants
gardent exactement leur comportement, aucun aiguillage silencieux sur le sport. Le principe du
règlement est que **chaque place se joue** — pas seulement la première.

- [x] **Départage de poule FFTT** (`PoolStandings`) : barème 2 pts par victoire / 1 par défaite
      jouée / 0 par forfait (`Sport#pool_points_rules`, lu **uniquement** ici — surtout pas dans
      `ranking_points_rules`, que la ronde suisse utilise à nombre de matchs inégal). Départage
      **restreint au sous-groupe d'ex æquo** et récursif : confrontation directe → **quotient**
      de manches → quotient de points → `draw_order`. Quotients, pas différences.
- [x] **Déclaration de structure** (`CriteriumStructure`) : pur Ruby, aucune base. Une seule
      récursion produit tous les chiffres du règlement — pour un tableau de `size` places dont
      la première est `offset`, les perdants du tour `r` sont `size / 2**r` joueurs qui se
      disputent les places à partir de `offset + size / 2**r`.
      La récursion **descend jusqu'en bas, sans seuil** : les 8 perdants d'un 8e de finale
      disputent les places 9-16 dans un vrai tableau de 8, qui reclasse lui-même ses perdants
      en 13-16 puis 15-16, exactement comme les 2 perdants de demi-finale disputent la 3e place.
      Il n'y a donc **jamais d'ex æquo** ; le seul rang partagé possible vient de
      `TournamentStandings#tail_groups` (joueurs qu'aucun tableau ne classe), départagé au
      quotient de manches puis de points comme partout ailleurs (`Tournament#rank_key`).
      À 32 joueurs (8 poules de 4) : **17 nœuds** et **120 matchs** (48 en poules, 8 barrages,
      32 par côté) — soit 4 matchs de tableau par joueur, `n/2 × log2(n)` matchs pour n places.
- [x] **Moteur** (`CriteriumFlow`) : un **réconciliateur**, pas une machine à états. Chaque appel
      recalcule ce qui devrait exister et ne crée que ce qui manque → idempotent par construction
      et déterministe (aucun `shuffle` : `draw_order` reste la seule source d'aléa). Barrages
      croisés 2es × 3es (jamais deux joueurs d'une même poule), tableau final « OK », consolante
      « KO », et les mini-tableaux de classement (3e/4e, 5e-8e…) en **branches parallèles**
      (colonne `tournament_rounds.branch`, sans laquelle l'index unique les interdirait).
- [x] **Places finales dérivées** (`TournamentStandings`) : jamais stockées — une colonne devrait
      être réécrite après chaque score, chaque correction, chaque forfait. Compaction obligatoire
      des places jamais jouées (byes), sinon le classement saute des rangs.
- [x] **Variantes par effectif** (`Tournament#criterium_mode`, colonne `final_phase_mode` = simple
      échappatoire) : ≤ 7 → poule unique, le classement final **est** celui de la poule ;
      8-16 → « classement intégral », un tableau unique, sans barrage ni consolante ;
      ≥ 17 → barrages + tableau + consolante. Le mode ne change que l'ENTRÉE dans le tableau :
      l'arbre de classement d'un tableau de 16 est le même dans les deux cas. `pool_plan` décrit la taille de chaque poule
      (11 joueurs → 4-4-3) et devient la source unique de `pool_count`, du dimensionnement du
      tableau et de `structure_summary` (miroir JS compris).
- [x] **Constitution des poules** (`PoolSeeding`) : `random` (le serpentin historique, déplacé
      sans changement) ou `pots` — chaque chapeau numéroté fournit un joueur par poule, le
      « chapeau général » complète. Ni serpent ni classement individuel : l'organisateur remplit
      les chapeaux à la main depuis l'onglet Participants (`PATCH /tournois/:id/constitution`,
      `TournamentPolicy#seeding?` : organisation seulement, et avant le lancement).
- [x] **Correction & forfaits** : corriger en **poule** reprend toute la phase finale (le
      classement de départ a changé) ; corriger **dans** la phase finale passe par
      `CriteriumFlow#reconcile!`, qui cherche le premier tour dont les joueurs ne sont plus les
      bons et ne détruit qu'à partir de lui — `id` croissant **est** l'ordre causal. Les scores
      d'une branche voisine (consolante) survivent. Un abandon en phase finale pose un forfait et
      les tours suivants naissent quand même (`build_match!`), sinon la branche resterait ouverte.

### ✅ Refonte UI (post-Lot 8) — phase de poules centrée sur la poule `[FAIT]`
La phase de poules était organisée **par journée** (`_round_ribbon` paginé → `_round_column`
`group_by_pool`) : une journée à la fois, un menu à ouvrir pour balayer les autres, et le
classement de la poule dans un **autre onglet**. Or un joueur suit **sa poule**, pas le
calendrier général. Renversé :
- [x] **Tout le calendrier de poule créé au lancement** (`PoolBuilder#create_missing_pool_rounds!`) :
      un round-robin est connu d'avance (poule de N → **N-1 matchs par joueur**, chacun affronte
      tous les autres), le générer journée par journée ne cachait que de l'information. Un joueur
      voit donc ses N-1 adversaires d'emblée — indispensable depuis le Lot 7, où c'est **lui** qui
      planifie ses rencontres. Conséquences : les poules n'avancent plus au rythme de la plus
      lente ; le calendrier n'est plus recalculé à chaque journée (fin de la fragilité décrite
      dans `RoundRobinStats#ordered_player_scope`) ; `Tournament#current_round` désigne la
      première ronde **non terminée** et non la dernière créée. Écrit comme un rattrapage
      idempotent : les tournois lancés avant reçoivent leurs journées manquantes au premier appel.
- [x] **Verrouillage de la phase EN BLOC** (`PoolBuilder#close_pool_rounds!`), à la dernière
      rencontre jouée, et non journée par journée : une journée n'est plus visible dans l'UI,
      fermer la carte d'un joueur parce que l'AUTRE rencontre de sa journée vient d'être saisie
      serait un critère invisible. Pendant la phase, chacun corrige son score ; après, c'est
      « Corriger » (organisateur).
- [x] **Sélecteur de poules** (`_pool_phase` + `pool_selector_controller.js`) : des onglets ARIA
      `Poule A…E`, **ma poule ouverte d'emblée** (`TournamentsHelper#my_pool_index`, lu depuis
      l'inscription — un joueur exempt une journée reste dans sa poule). Poule active et
      visibilité du classement mémorisées en `sessionStorage`, rejouées au `connect()` : sans ça
      le `turbo_stream.update("tournament_board")` de chaque saisie de score renverrait
      l'organisateur sur la poule A. Même raison, même mécanique que `journee_selector`.
- [x] **Toutes les confrontations de la poule d'un coup**, journées confondues
      (`TournamentsHelper#pool_matches` — une requête, byes exclus). Le filtre par journée a
      disparu de la phase de poules ; il reste au championnat.
- [x] **Classement de la poule à côté des matchs**, masquable (`.pool-view--full` → les cartes
      se répartissent alors sur plus de colonnes). Même source que l'onglet Classement
      (`ranked_pools`), en version compacte (`_ranking_table`, local `compact`).
- [x] **Carte empilée** (`_tmatch_scoreline`, local `stacked`) : A au-dessus de B, score à droite
      — poules et barrages, comme le tableau final. Championnat et ronde suisse gardent la
      scoreline centrée, adaptée à une colonne de ruban étroite.
- [x] **Un seul bouton « Gérer le score »** (plus de « Saisir » / « Modifier ») : la modale fait
      les deux. Le pied de carte commun aux trois cartes vit dans `_tmatch_actions`.
- [x] **Poule d'origine en barrage** : badge `Poule X` sur chaque joueur d'un barrage réel
      (`_tmatch_scoreline`, dérivé de `phase == "barrage"`), seul tour où deux poules se
      rencontrent et où le règlement l'interdit entre joueurs d'une même poule
      (`CriteriumFlow#avoid_same_pool`). Sur les cases **préfigurées**, le 2e est nommé
      (`2e de Poule A`… — un barrage par poule, la bijection est certaine) mais pas le 3e :
      il vient par construction d'une AUTRE poule, et l'appariement croisé ne sera tranché
      qu'à la fin des poules.
- [x] Devenus morts et supprimés : le local `group_by_pool` (`_round_ribbon` / `_round_column`)
      et le bloc SCSS `.pool-grid`.
- [x] **Règle du set durcie** (`TournamentMatch#valid_set?` + son miroir JS) : un set s'arrête
      dès qu'il est gagné, on ne peut donc pas dépasser la cible librement. La validation ne
      regardait que l'écart et acceptait `12-9` ou `15-3` au ping-pong ; au-delà de la cible,
      l'écart vaut désormais **exactement 2** (`12-10` ✔, `13-11` ✔, `12-9` ✘). Généralisé par
      `target` / `cap` / `win_by_two` (tennis : `7-5` ✔, `7-6` ✔, `8-6` ✘) ; les sports non
      configurés restent tolérants, faute de connaître leur règle.
- [x] **Migration de rattrapage** `BackfillMissingPoolRounds` : les tournois déjà en cours
      n'auraient récupéré leurs journées manquantes qu'au prochain score terminant une journée
      (`next_round!` n'est appelé qu'à l'écriture). Elle relaie une fois au moteur, dont les
      gardes protègent les tournois déjà passés en phase finale. Reste ouvert : les
      vérifications visuelles navigateur.

### 🔜 (ex-Lot 5, reporté) — affinements
- [ ] Winner / Loser Bracket (format e-sport) — voir « Formats envisagés » #4.
- [x] Gestion des co-organisateurs après création (ajout/retrait + transfert d'administration
      depuis `#edit`, panneau « Équipe organisatrice » — `_organizers_manager.html.erb`).

### 💡 Futurs
- [ ] **Gamification** : badges, trophées, achievements (1er tournoi gagné, 500 pts, 10e set…).
- [ ] **Calendrier des matchs** (éviter les conflits d'horaire).
- [ ] **Intégration Slack** (Bolt) : notifications de match + boutons d'action (voir / s'inscrire).
- [ ] **Dashboard personnel** à la connexion (tournois + matchs à venir, filtrés par sport du profil).
- [ ] **Export agenda** (Outlook) — déjà fonctionnel pour les matchs.

---

## 📌 État courant

**Lots 1 à 8 livrés.** Les 4 formats (`ronde_suisse`, `championnat`, `poules`,
`criterium_federal`) sont jouables de bout en bout via la façade `TournamentEngine`. Un organisateur peut déclarer un **forfait**
(exclusion du joueur, victoires par forfait) et **corriger un score verrouillé** (avec
régénération cohérente de l'aval). **Avant** le lancement, admin et co-organisateur peuvent
aussi **retirer un inscrit** depuis l'onglet Participants — désinscription sèche, à ne pas
confondre avec le forfait : la ligne `tournament_users` disparaît, ce qui n'est possible que
tant qu'aucun match ne la référence (4 clés étrangères depuis `tournament_matches`). Un
organisateur ne peut retirer qu'un **simple joueur**, jamais un pair ni l'admin
(`TournamentUserPolicy#destroy?`). Depuis le Lot 6, l'organisateur **et le co-organisateur**
peuvent aussi **éditer le tournoi**, **clôturer/rouvrir les inscriptions** et **terminer
manuellement** un tournoi. Depuis le Lot 7, **les joueurs planifient eux-mêmes leur rencontre**
(date et heure de leur choix) depuis leur carte de poule, le **scoring dépend de la phase**
(ping-pong : 3 sets gagnants en poule, 4 en phase finale) et l'organisateur **personnalise la
structure** de son tournoi (taille des poules, seuils de la ronde suisse, taille du tableau
final) avec des valeurs recommandées par défaut. Le Lot 8 ajoute le **Critérium Fédéral**
(ping-pong) : départage FFTT, barrages, consolante, matchs de classement — **chaque place se
joue** — avec constitution des poules par chapeaux. L'onglet Matchs d'un tournoi à poules est
depuis **centré sur la poule** : on choisit sa poule (la sienne par défaut), on y voit **toutes**
ses confrontations et **son classement** côte à côte, et un unique bouton « Gérer le score ».
Prochain chantier envisagé : Winner/Loser
Bracket, puis les « Futurs » ci-dessous (gamification, calendrier, Slack…).

<details><summary>Historique Lots 1 à 4</summary>

**Lots 1 à 4 livrés.** La page `/tournois` affiche 3 sections ; le **formulaire de
création** (`/tournois/new`) est fonctionnel. Le **moteur de jeu** est complet :
un tournoi Ronde Suisse se lance (`start`), tire au sort la ronde 1 (animation), on saisit
un **score set par set** (modale) dont le vainqueur est dérivé, les rondes s'enchaînent
(3 V → qualifié / 3 D → éliminé) puis basculent automatiquement sur le **Final 4/8** —
dont le **seeding reflète le set/point average** — jusqu'à désigner un vainqueur. Une carte
peut être transformée en **rencontre standard** rattachée au tournoi. La page `/tournois/:id`
est organisée en **4 onglets** (Vue d'ensemble · Matchs · Participants · Classement) ; la Vue
d'ensemble embarque un **bracket viewer** interactif (défilement, zoom, filtre par ronde).

### Modèle de données Lot 3 + 4 (+ Lot 5)
- `tournament_rounds` : number, phase (`swiss`/**`league`**/**`pool`**/`bracket`), status ; index
  unique `[tournament_id, phase, number]`.
- `tournament_matches` : player_a/player_b/winner (→ `tournament_users`), is_bye, position,
  status, **`sets` (jsonb, `[[a, b], …]`)**, **`forfeit` + `retired_player_id`** (Lot 5) ;
  index unique `[tournament_round_id, position]`.
- `tournament_users` (+ colonnes) : wins, **draws**, losses, seed, state
  (`active`/`qualified`/`eliminated`/**`withdrawn`**), `sets_won/sets_lost`, `points_won/points_lost`,
  **`pool`** (Lot 5, index `[tournament_id, pool]`), **`draw_order`** (tirage au sort figé au lancement).
- `matches` (couplage) : **`tournament_id`** (rattachement lâche) + **`tournament_match_id`**
  (lien 1↔1, index unique).

</details>

### Modèle de données — compléments (Lots 6 & 7)
- `tournaments` : **`playoffs`** (Lot 6, booléen — n'a de sens que pour le championnat,
  cf. `Tournament#bracket_expected?`), **`banner_image`** (image suivie du sport, Lot 7).
- `tournaments` — réglages de structure (Lot 7, **tous nullables : `nil` = recommandé**) :
  **`players_per_pool`**, **`bracket_size`**, **`swiss_wins_to_qualify`**,
  **`swiss_losses_to_eliminate`**. Ne jamais les lire directement dans un moteur : passer par
  `Tournament#pool_size` / `#final_size` / `#wins_to_qualify` / `#losses_to_eliminate`, qui
  appliquent le fallback (les noms de colonnes diffèrent volontairement de ceux des méthodes
  pour qu'aucune méthode ne masque un attribut ActiveRecord).
- `tournaments` — Critérium Fédéral (Lot 8, nullables) : **`final_phase_mode`** (`nil` = déduit
  de l'effectif, cf. `#criterium_mode`), **`pool_seeding_mode`** (`nil`/`random` | `pots`),
  **`seeded_pot_count`**. Côté inscription : **`tournament_users.pot`** (`nil` = chapeau
  général). Même règle de lecture : passer par `#criterium_mode` / `#seeding_mode` / `#pot_count`.
- `tournament_rounds` — **`branch`** (`null: false, default: "main"`) : la seconde dimension de
  l'index unique `[tournament_id, phase, branch, number]`. Indispensable, et **non nullable** :
  avec `NULL`, Postgres autoriserait des doublons (`NULL ≠ NULL`) et l'index perdrait sa garde
  anti-double-clic. Convention : `"main"`, ou `"<table>:<première>-<dernière>"` (`ok:5-8`).

### Décisions actées
- **Statuts** (`tournaments.status`) : `open` / `closed` / `in_progress` / `completed`
  (`closed` ajouté au Lot 6 — inscriptions fermées, tournoi pas encore lancé).
- **Formats** (`tournaments.format`) : `ronde_suisse` / `poules` / `championnat` /
  `criterium_federal` (Lot 8 — format à part entière, jamais déduit du sport).
- **3 sections** de la page liste :
  1. *Mes tournois en cours* — inscrit + non terminé (masquée si déconnecté).
  2. *Tournois à rejoindre* — `open`, deadline future, non complet, non inscrit.
  3. *Tournois en cours* (publics) — `in_progress`, non inscrit → lecture seule.
- **Droits** : tout utilisateur connecté peut créer un tournoi (en devient l'admin).
- **Co-organisateur** (tranché Lot 2, **révisé** depuis) : porté par la colonne booléenne
  `tournament_users.co_organizer`, et non plus par le rôle. Les deux informations sont
  désormais séparées — `role` répond à « occupe une place de joueur ? », `co_organizer` à
  « a les droits de gestion ? » — ce qui permet à **un joueur de co-organiser le tournoi
  qu'il joue**, impossible tant que l'index unique `[tournament_id, user_id]` et le rôle
  portaient les deux à la fois. Trois combinaisons existent : joueur seul, co-organisateur
  seul (nommé sans avoir rejoint le tournoi → rôle `co_organisateur`, qui n'occupe pas de
  place), et les deux. Invariant tenu par le modèle : une ligne de rôle `co_organisateur`
  porte toujours le drapeau, sinon elle ne servirait à rien
  (`TournamentUser#flag_dedicated_co_organizer`).
  Droits fins sur la gestion du tableau : câblés via `Tournament#organizer?`, qui lit le
  drapeau. Nombre **illimité**, composés depuis `#edit` par le **seul admin**
  (`TournamentPolicy#manage_organizers?` → `owner?`, et non `manage?` : sinon un
  co-organisateur pourrait coopter ou révoquer celui qui l'a nommé). Nommer un joueur
  inscrit lui **laisse sa place**, et reste possible tournoi lancé (rien n'est retiré des
  poules ni des appariements). Le révoquer le laisse joueur s'il en était un, et détruit sa
  ligne sinon. L'admin peut **transmettre l'administration** (`#transfer_ownership`) : il
  redevient co-organisateur, en gardant sa place de joueur s'il en avait une.
- **Nombre de joueurs** : presets 8/16/32 **+ mode Libre** (nombre arbitraire). Depuis le Lot 7,
  la structure qui en découle n'est plus un aperçu figé en lecture seule : elle est **calculée**
  (`Tournament#structure_summary`) et chacun de ses critères est **personnalisable** par
  l'organisateur, avec la valeur recommandée en placeholder.
- **Formats par sport** : `Sport#available_tournament_formats` (raquette → RS/Poules ;
  collectif → Championnat/Poules).

### Modèle de données actuel
- `tournaments` : name, description, slug, banner_image, sport_id, format, max_players,
  date, time, place, venue_id, registration_deadline, status, user_id (admin).
- `tournament_users` : tournament_id, user_id, role, status (index unique [tournament_id, user_id]).

### Points ouverts à trancher (avant Lot 3)
- Configs précises de Ronde Suisse par nombre de joueurs (16, 32… ; 24 problématique)
  → remplacer les valeurs **provisoires** de `Tournament::STRUCTURE_PRESETS` + la logique
  de `_buildProposals` (mode Libre) dans `tournament_form_controller.js`.
- Gestion des **abandons** (victoire par abandon) et **correction d'un score après verrouillage**.
- ~~Droits exacts du co-organisateur sur la gestion du tableau~~ → tranché : `manage?` pour
  tout ce qui touche au tableau, `owner?` pour la suppression et la composition de l'équipe.

---

## ▶️ Prochaine étape proposée

**Lots 1 à 6 terminés.** Pistes suivantes, par ordre de valeur :
1. **Affiner les configs** de Ronde Suisse par effectif (16/32 ; 24 problématique) et les
   propositions du mode « Libre » (`STRUCTURE_PRESETS` + `_buildProposals` dans
   `tournament_form_controller.js`) — reste **provisoire** depuis le Lot 2.
2. **Winner / Loser Bracket** (format e-sport) — le format complexe reporté (barrages,
   descente en loser bracket, grande finale).
3. Les **Futurs** (gamification, calendrier, Slack, dashboard perso, export agenda).
