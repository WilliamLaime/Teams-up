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
- [x] Ajout d'un **co-organisateur** (autocomplete d'utilisateurs, réutilise `invite-search`) → rôle `co_organisateur` dans `tournament_users` (n'occupe pas de place de joueur).
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

### 🔜 (ex-Lot 5, reporté) — affinements
- [ ] Winner / Loser Bracket (format e-sport) — voir « Formats envisagés » #4.
- [ ] Gestion des co-organisateurs après création (ajout/retrait depuis `#edit`).

### 💡 Futurs
- [ ] **Gamification** : badges, trophées, achievements (1er tournoi gagné, 500 pts, 10e set…).
- [ ] **Calendrier des matchs** (éviter les conflits d'horaire).
- [ ] **Intégration Slack** (Bolt) : notifications de match + boutons d'action (voir / s'inscrire).
- [ ] **Dashboard personnel** à la connexion (tournois + matchs à venir, filtrés par sport du profil).
- [ ] **Export agenda** (Outlook) — déjà fonctionnel pour les matchs.

---

## 📌 État courant

**Lots 1 à 7 livrés.** Les 3 formats (`ronde_suisse`, `championnat`, `poules`) sont jouables de
bout en bout via la façade `TournamentEngine`. Un organisateur peut déclarer un **forfait**
(exclusion du joueur, victoires par forfait) et **corriger un score verrouillé** (avec
régénération cohérente de l'aval). Depuis le Lot 6, l'organisateur **et le co-organisateur**
peuvent aussi **éditer le tournoi**, **clôturer/rouvrir les inscriptions** et **terminer
manuellement** un tournoi. Depuis le Lot 7, **les joueurs planifient eux-mêmes leur rencontre**
(date et heure de leur choix) depuis leur carte de poule, le **scoring dépend de la phase**
(ping-pong : 3 sets gagnants en poule, 4 en phase finale) et l'organisateur **personnalise la
structure** de son tournoi (taille des poules, seuils de la ronde suisse, taille du tableau
final) avec des valeurs recommandées par défaut. Prochain chantier envisagé : Winner/Loser
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

### Décisions actées
- **Statuts** (`tournaments.status`) : `open` / `closed` / `in_progress` / `completed`
  (`closed` ajouté au Lot 6 — inscriptions fermées, tournoi pas encore lancé).
- **Formats** (`tournaments.format`) : `ronde_suisse` / `poules` / `championnat`.
- **3 sections** de la page liste :
  1. *Mes tournois en cours* — inscrit + non terminé (masquée si déconnecté).
  2. *Tournois à rejoindre* — `open`, deadline future, non complet, non inscrit.
  3. *Tournois en cours* (publics) — `in_progress`, non inscrit → lecture seule.
- **Droits** : tout utilisateur connecté peut créer un tournoi (en devient l'admin).
- **Co-organisateur** (tranché Lot 2) : **pas de nouvelle colonne** — rôle `co_organisateur`
  dans `tournament_users` (n'occupe pas de place de joueur). Droits fins sur la gestion du
  tableau : à câbler au Lot 3 via `Tournament#organizer?`.
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
- Droits exacts du co-organisateur sur la gestion du tableau (Pundit + `Tournament#organizer?`).

---

## ▶️ Prochaine étape proposée

**Lots 1 à 6 terminés.** Pistes suivantes, par ordre de valeur :
1. **Affiner les configs** de Ronde Suisse par effectif (16/32 ; 24 problématique) et les
   propositions du mode « Libre » (`STRUCTURE_PRESETS` + `_buildProposals` dans
   `tournament_form_controller.js`) — reste **provisoire** depuis le Lot 2.
2. **Gestion des co-organisateurs après création** (ajout/retrait depuis `#edit` — pour
   l'instant seulement à la création) — suite naturelle du Lot 6.
3. **Winner / Loser Bracket** (format e-sport) — le format complexe reporté (barrages,
   descente en loser bracket, grande finale).
4. Les **Futurs** (gamification, calendrier, Slack, dashboard perso, export agenda).
