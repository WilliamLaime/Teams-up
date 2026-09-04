# Feature : refonte UI onglet Matchs des tournois — Phase A (ruban horizontal) + Phase B (pastilles)

Plan complet (5 phases) : `/home/axelb/.claude/plans/woolly-tinkering-nebula.md`
Doc de suivi feature : `docs/TOURNOI.md`

## Objectif Phase A
Remplacer le grid vertical empilé des rondes suisses / journées de championnat /
journées de poules par un ruban de colonnes horizontales scrollables (une par
tour), même esprit que `.bracket` (tableau final) mais avec des cartes `_tmatch`
éditables. Base de travail pour les phases B/C/D/E à venir (branches séparées).

## Étapes
1. [x] `_round_column.html.erb` — une colonne = un tour (locals: round, can_manage,
   title, group_by_pool:) ; id="round_<id>" en ancre pour la Phase B future
2. [x] `_round_ribbon.html.erb` — conteneur scrollable, boucle sur les rounds
3. [x] `_board.html.erb` — sections Ronde Suisse / Championnat / Poules basculent
   sur `_round_ribbon`
4. [x] `_pool_phase.html.erb` — devient un simple appel à `_round_ribbon` avec
   `group_by_pool: true`
5. [x] Supprimer `_swiss_round.html.erb` (contenu migré dans `_round_column`)
6. [x] SCSS `.round-ribbon`/`.round-col` dans `_tournament_bracket.scss`
   (flex-start + gap fixe, PAS space-around comme `.bracket__matches`)
7. [x] Tests controller mis à jour (`.swiss-round` → `.round-col`, 3 assertions) ;
   suite tournois complète (80 tests : controllers/models/policies/services) verte
8. [ ] Vérif visuelle navigateur — **non faite** : aucun navigateur/chromedriver
   disponible dans ce sandbox (ni chromium-cli, ni chrome/chromium binaire). À
   confirmer en local par l'utilisateur (`rails server`, onglet Matchs d'un
   tournoi ronde suisse/poules/championnat en cours, desktop + mobile ~375px,
   saisie de score, survol tracking joueur, animation de tirage au lancement)
9. [x] Pastilles d'en-tête façon Lolesports (ronde suisse) : une pastille CARRÉE
   par groupe de bilan entrant dans le tour, colorée via `TournamentUser.state_for`
   (vert qualifié / gris en lice / rouge éliminé), à la place du statut générique
   Terminée/En cours — `TournamentUser.state_for` extrait en class method
   (réutilisé par `SwissPairing#state_for`), `_round_column.html.erb` calcule les
   groupes une seule fois (header + corps), SCSS `.round-col__pips`/`__pip` dans
   `_tournament_bracket.scss`. Tests contrôleur + swiss_pairing verts (51 runs).
   Vérif visuelle en attente, cf. étape 8.

## Phase B — Sélecteur de phase (2 pastilles, onglets « stage » façon lolesports)
Redéfinie en cours de route : 1er jet en pastille-par-ronde (façon "Ronde 1/2/3…")
jugé peu lisible par l'utilisateur (retour visuel + lien lolesports.com/.../stage/…) —
remplacé par un vrai bascule à 2 états (round-robin ↔ tableau final), qui montre/
cache la section plutôt que de juste y faire défiler.
1. [x] `tournaments_helper.rb#round_robin_phase_meta(tournament)` — libellé + icône
   Lucide de la phase round-robin selon `tournament.format` (Ronde Suisse/
   Championnat → swords, Poules → layout-grid) ; remplace l'ancien `phase_nav_icon`
   par-tour (supprimé)
2. [x] `_phase_nav.html.erb` — 2 pastilles (phase round-robin / Tableau final),
   affichées uniquement si `tournament.bracket_started?` (avant ça une seule phase
   existe, rien à basculer)
3. [x] `tournament_phase_switch_controller.js` (remplace `tournament_phase_nav_controller.js`,
   supprimé) — `show(phase)` bascule `hidden` sur les sections cibles + `is-active`
   sur les pastilles ; `defaultValue` recalculée côté serveur à chaque rendu
   (`tournament.bracket_started? ? "bracket" : "main"`) → pointe toujours vers la
   phase "en cours", donc rien d'important n'est perdu au re-render Turbo Stream
   (même compromis qu'A.8 pour le scroll horizontal)
4. [x] `_board.html.erb` — nouveau wrapper `.tournament-board__phases` avec
   `data-controller="tournament-phase-switch"` autour de `_phase_nav` + des
   sections round-robin/tableau final (chacune taguée `data-phase="main"` ou
   `"bracket"` + `data-tournament-phase-switch-target="section"`)
5. [x] `_pool_phase.html.erb` / `_bracket.html.erb` — tags `data-phase`/`data-*-target`
   ajoutés sur leur `<section class="tournament-phase">` respective (l'ancre
   `id="round_<id>"` ajoutée puis retirée de `_bracket.html.erb` — plus nécessaire,
   ce n'est plus un scroll par ronde)
6. [x] SCSS `.phase-nav`/`.phase-nav__pill` réécrit : pastille active = accent
   plein `$green` (bascule réelle de contenu, pas juste un filtre visuel comme
   `.bracket-viewer__chip`)
7. [x] Tests contrôleur : absence avant démarrage du tableau final, présence
   (2 pastilles) une fois `bracket_started?` vrai (tournoi joué jusqu'au bout via
   `SwissPairing#next_round!` + `win_tournament_match!`) ; suite tournois verte
   (84 runs sur controllers/models/policies/services)
8. [ ] Vérif visuelle navigateur — **non faite**, même limitation qu'étape A.8
   (clic pastille → bascule instantanée round-robin/tableau final, mobile ~375px,
   icônes Lucide bien résolues, accent vert visible en dark ET light mode)

## Phase C — Panneau « Qualifiés / Éliminés » (ronde suisse uniquement)
Redéfinie en cours de route (2e retour utilisateur, lien lolesports.com/.../stage/…
— vue Système suisse) : le panneau n'est plus un bloc à part sous le ruban, il est
rendu EN CONTINUITÉ HORIZONTALE des colonnes de rondes, comme une colonne de plus
dans le même ruban scrollable. Corrige au passage un doublon d'affichage (le
panneau restait visible même en vue Tableau final, qui montre déjà cette info).
1. [x] `_qualification_panel.html.erb` — devient UNE colonne (`.qualification-col`,
   pas deux blocs côte à côte) avec 2 groupes empilés à l'intérieur (Qualifiés /
   Éliminés), à partir de `tournament.ranked_players.select(&:qualified?)` /
   `select(&:eliminated?)` (zéro requête supplémentaire, `ranked_players` déjà
   trié et chargé) ; n'affiche rien si les deux listes sont vides ; chaque groupe
   affiche quand même son titre + un état vide dédié si l'AUTRE groupe a des
   entrées mais pas lui
2. [x] `_round_ribbon.html.erb` — nouveau local optionnel `extra_columns` (HTML
   déjà rendu, ajouté après la dernière colonne de tour dans le même `.round-ribbon`)
3. [x] `_board.html.erb` — passe `render("tournaments/qualification_panel", …)`
   comme `extra_columns:` du ruban de la ronde suisse (plus de render séparé après
   la section). Conséquence directe : la colonne vit maintenant DANS la section
   `data-phase="main"` → masquée par le bascule Phase B en vue Tableau final, qui
   montre déjà cette info au fil des tours joués (fin du doublon signalé)
4. [x] SCSS `.qualification-col` : mêmes proportions qu'une colonne de tour
   (`.round-col`, `min-width`/`max-width` identiques) pour lire comme sa suite
   naturelle plutôt qu'un bloc à part ; 2 groupes empilés (pas côte à côte, une
   colonne de ruban est trop étroite) ; réutilise l'accent `$green`/`#c0392b`
   déjà posé par `.ranking-badge`
5. [x] Scrollbar horizontale « pimpée » (2e retour utilisateur) : mixin
   `themed-scrollbar` (fin, couleur `--theme-border-strong`, se fond dans le
   thème dark/light) appliqué à `.round-ribbon` et `.bracket` — remplace la barre
   grise par défaut du navigateur
6. [x] Tests contrôleur : sélecteur renommé `.qualification-panel` → `.qualification-col`
   (absent tant qu'aucun joueur n'a 3V/3D, présent une fois un joueur qualifié,
   absent pour un format championnat) ; suite tournois verte (73 runs) ; SCSS
   validé par `bin/rails assets:precompile RAILS_ENV=test` (compile sans erreur)
7. [ ] Vérif visuelle navigateur — **non faite**, même limitation qu'étapes A.8/B.8
   (colonne bien alignée dans la continuité du ruban desktop + mobile ~375px,
   disparition propre en vue Tableau final, icônes Lucide check-circle/x-circle
   résolues, scrollbar discrète visible dark ET light mode)

## Phase D — abandonnée (retour utilisateur)
1ère version : condensé de classement par poule (une carte par poule, rang/V/D/Pts)
injecté dans `_pool_phase.html.erb`, au-dessus du ruban de journées. Retour
utilisateur : le classement n'a rien à faire dans l'onglet **Matchs** — cet onglet
ne montre QUE des matchs, le classement (par poule ou global) vit déjà dans
l'onglet **Classement** (`_ranking.html.erb`/`_ranking_table.html.erb`), pas de
raison de le dupliquer. Entièrement retiré : `_pool_standings.html.erb` supprimé,
`_pool_phase.html.erb` revenu à un simple appel `_round_ribbon`, SCSS
`.pool-standings-row`/`.pool-standings` retiré, tests contrôleur associés retirés.

## Nettoyage table de classement (`_ranking_table.html.erb`, retour utilisateur)
Deux colonnes questionnées sur le tournoi de test (format poules, football) :
1. [x] Colonne **État** (badge Qualifié/Éliminé/Abandon/En lice) retirée : aucune
   valeur ajoutée par rapport au reste de la ligne (le panneau dédié de la Phase C
   couvre déjà qualifiés/éliminés pour la ronde suisse ; pour poules/championnat
   l'état est presque toujours "En lice" tant que le tableau final n'a pas
   commencé). `.ranking-badge` (SCSS, devenu orphelin) supprimé avec.
2. [x] Colonne **Sets** (différentiel de sets, `tu.set_average`) : n'a de sens que
   pour les sports joués en sets (tennis, padel, badminton, ping-pong, volley —
   `Sport#scoring_rules[:mode] == :sets`). Pour les sports à score simple
   (football, handball, basketball), ce différentiel vaut toujours V-D — aucune
   info en plus, cf. constat sur le tournoi "Test foot". Masquée conditionnellement
   (`show_sets`, même pattern que `show_draws` déjà existant pour la colonne "N"),
   pas supprimée : reste utile/correcte pour les sports à sets.
3. [x] Suite tournois verte (53 runs), SCSS validé par
   `bin/rails assets:precompile RAILS_ENV=test`.

## Bug corrigé — poules à 32 joueurs sautait les huitièmes (retour utilisateur)
Constaté en simulant le tournoi de test "Test foot" (32 joueurs) : la phase de
poules basculait sur un tableau final à 4 matchs (quarts, 8 qualifiés) au lieu des
8 attendus (huitièmes, 16 qualifiés — top 2 de chaque poule, règle standard type
Coupe du monde). Cause racine : `Tournament#final_size` (tournament.rb) utilisait
une formule à 2 paliers (≤ 8 joueurs → 4, au-delà → 8) pensée pour la ronde suisse/
le championnat (plafond volontaire, cf. STRUCTURE_PRESETS) — mais jamais adaptée
pour le format "poules", qui grandit avec le nombre de poules (2 poules → demies,
4 poules → quarts, 8 poules → huitièmes, conforme à STRUCTURE_PRESETS["poules"]
qui promettait déjà ce texte sans que le code ne le respecte).
1. [x] `Tournament#pool_count` — nouvelle méthode publique (~4 joueurs/poule),
   remplace la version dupliquée en `private` dans `PoolBuilder` (qui délègue
   maintenant à `@tournament.pool_count` — une seule source de vérité)
2. [x] `Tournament#final_size` — `return pool_count * 2 if format == "poules"`
   avant la formule générique (ronde suisse/championnat inchangés)
3. [x] Test `PoolBuilderTest` : 32 joueurs → 8 poules de 4, top 2/poule qualifiés
   (16 au total), tableau final ouvre bien sur 8 matchs (huitièmes)
4. [x] Suite tournois verte (68 runs), SCSS validé

## Ajout — indicateur de qualification par poule dans l'onglet Classement
Retour utilisateur : après la suppression de la colonne "État" (ci-dessus), plus
aucun moyen de voir dans l'onglet Classement quels joueurs sont qualifiés au sein
de chaque poule. Pas de réintroduction de la colonne texte (jugée sans valeur) :
icône ciblée à la place.
1. [x] `_ranking_table.html.erb` — icône Lucide `check-circle` (verte) à côté du
   nom du joueur si `tu.qualified?` (posé par `PoolBuilder#start_playoffs!`/
   `LeagueBuilder`/`SwissPairing` sur les qualifiés une fois leur phase terminée —
   rien avant, on ne peut pas savoir qui est qualifié tant que ce n'est pas décidé)
2. [x] SCSS `.tournament-ranking__qualified-icon` + léger liseré vert
   (`box-shadow: inset` sur la 1ère cellule) sur `&__row--qualified`
3. [x] Suite tournois verte, SCSS validé
4. [ ] Vérif visuelle navigateur — non faite, même limitation que les phases
   précédentes (icône bien résolue, liseré visible dark ET light mode)

## Phase E1 — Structure complète du tableau final + cases « À déterminer »
Objectif : afficher dès le lancement du tournoi toutes les colonnes que comptera
le tableau final (ex. huitièmes → quarts → demies → finale), pas seulement les
tours déjà joués — les places futures affichent une case « À déterminer » en
pointillés plutôt que de ne pas exister du tout.
1. [x] `Tournament#expected_bracket_round_count` (tournament.rb, à côté de
   `#final_size`) : `Math.log2(final_size).to_i` — nombre de tours prévus.
2. [x] `TournamentsHelper#bracket_stage_label(index, total)` — extrait de la
   branche bracket de `round_label` (logique par distance à la finale : 0 =
   Finale, 1 = Demi-finales, 2 = Quarts, 3 = 8es, sinon "Tour N"), en fonction
   PURE (index/total) réutilisable pour des colonnes qui n'ont pas encore de
   `TournamentRound` réel. `round_label` délègue maintenant à cette fonction.
3. [x] `_bracket.html.erb` réécrit : boucle sur `0...total` (`total` = tours
   déjà joués une fois le tournoi `completed?`, sinon
   `max(expected_bracket_round_count, tours réels)` — évite des colonnes
   fantômes si l'effectif réel a produit moins de tours que prévu, cas limite
   petits effectifs). Tour existant → vrais matchs (`_tmatch`) ; tour futur →
   autant de `_bracket_placeholder_cell` que ce tour comptera de places
   (`final_size / 2**(index+1)`).
4. [x] `_bracket_placeholder_cell.html.erb` — nouvelle carte, même gabarit que
   `.tmatch-card--bye` (bordure pointillés) mais vide ("À déterminer").
5. [x] `_board.html.erb` — condition d'affichage du tableau final passée de
   `bracket_started?` à `(in_progress? || completed?) && playoffs?` : le
   tableau (avec ses placeholders) apparaît dès le lancement du tournoi, pas
   seulement une fois de vrais matchs de bracket générés. Le cas championnat
   SANS playoffs (jamais de bracket_rounds) reste bien exclu.
6. [x] `_phase_nav.html.erb` — même condition (sinon le sélecteur de phase
   n'aurait pas pu basculer vers un tableau final désormais visible plus tôt).
7. [x] Tests contrôleur mis à jour : l'ancien test "pas de sélecteur de phase
   tant que le tableau n'a pas démarré" n'a plus lieu d'être (comportement
   voulu inverse) → remplacé par un test qui vérifie que les 2 pastilles ET la
   structure complète (tours + cases "À déterminer") apparaissent dès le
   lancement, avant tout match de bracket joué.
8. [x] Suite tournois verte (69 runs), SCSS validé.
9. [ ] Vérif visuelle navigateur — non faite, même limitation que les phases
   précédentes (alignement des cases pointillées dans la colonne, dark ET
   light mode). E2 (connecteurs CSS entre les cases) reste à faire ensuite,
   volontairement pas dans cette itération (cf. plan).

## Phase E2 — Connecteurs CSS entre les tours
Objectif du plan : relier visuellement les cases du tableau final d'une colonne
à l'autre (façon bracket papier), en CSS pur (pseudo-éléments, pas de SVG/JS).
Fallback explicitement prévu par le plan si la version complète (trait vertical
reliant précisément chaque PAIRE de cartes) s'avère trop fragile à valider sans
rendu navigateur réel — c'est le cas ici (sandbox sans navigateur) :
1. [x] Version retenue = le fallback : un court trait horizontal (`::before`/
   `::after`) entre chaque carte et la colonne suivante, PAS un trait vertical
   précis entre paires. Raison du choix : un connecteur vertical pixel-parfait
   suppose soit un espacement purement proportionnel entre cartes
   (`justify-content: space-around` sans le `gap: 1.25rem` fixe actuel), soit
   une structure de markup imbriquée par paire (les matchs d'un tour sont
   aujourd'hui à plat dans `.bracket__matches`, pas nichés 2 par 2) — les deux
   sont des changements plus risqués, impossibles à valider visuellement ici.
2. [x] `.bracket__round` (SCSS) : `.tmatch-card` (dans `.bracket__matches`)
   passée en `position: relative` pour ancrer les traits à CHAQUE carte (pas au
   conteneur) ; trait `::after` (sort vers la droite) sur toute colonne sauf la
   dernière, trait `::before` (arrive de la gauche) sur toute colonne sauf la
   première. Couleur neutre (`var(--theme-border-strong)`, cohérent avec les
   bordures de carte existantes).
3. [x] Cases "À déterminer" (Lot 7/E1) et byes reçoivent le même trait (classe
   de base `.tmatch-card` commune) — leur fil visuel ne disparaît pas.
4. [x] Aucun changement de markup (CSS seul) — suite tournois verte (69 runs,
   inchangée), SCSS validé (`bin/rails assets:precompile RAILS_ENV=test`).
5. [ ] Vérif visuelle navigateur — non faite (pas de navigateur dans ce
   sandbox). À valider en priorité : les traits ne doivent pas se chevaucher
   avec les avatars/boutons des cartes voisines, lisible dark ET light mode.
   Si le rendu simple déçoit visuellement, l'étape suivante serait de
   restructurer `.bracket__matches` en paires imbriquées pour un vrai
   connecteur vertical façon arbre complet (plus gros chantier, pas fait ici).

## Bug corrigé — tableau final invisible sur "Test foot" après E1 (retour utilisateur)
Constaté par l'utilisateur : le tournoi "Test foot" (poules, terminé, vainqueur
Joueur 6) n'affichait plus RIEN dans l'onglet Matchs — juste la bannière
vainqueur, plus aucune pastille ni tableau. Cause racine : la condition
d'affichage du tableau final posée en E1 (`_board.html.erb`/`_phase_nav.html.erb`)
testait `tournament.playoffs?` pour tous les formats — or la colonne `playoffs`
n'a de sens que pour le championnat (seul `LeagueBuilder` la lit) ; pour les
poules/ronde suisse elle peut porter n'importe quelle valeur héritée sans rapport
avec l'existence d'un tableau final. "Test foot" avait `playoffs: false` en base
(tournoi ancien, valeur jamais pertinente pour son moteur) → tableau masqué à tort.
1. [x] `Tournament#bracket_expected?` (tournament.rb, à côté de `bracket_started?`) :
   `format != "championnat" || playoffs?` — seule source de vérité sur la
   pertinence de `playoffs` selon le format.
2. [x] `_board.html.erb` / `_phase_nav.html.erb` : `tournament.playoffs?` remplacé
   par `tournament.bracket_expected?`.
3. [x] Test de régression : tournoi ronde suisse avec `playoffs: false` explicite
   en base → tableau final et sélecteur de phase doivent quand même s'afficher.
4. [x] Suite tournois verte (69 runs contrôleur/modèles + le nouveau test).
5. [ ] Vérif visuelle navigateur sur "Test foot" (id 40) — non faite, même
   limitation que le reste (pas de navigateur dans ce sandbox), mais la
   condition serveur est confirmée correcte (`bracket_expected?` → true pour ce
   tournoi précis, vérifié via `bin/rails runner`).

## Bug corrigé — traits de connexion E2 invisibles (retour utilisateur)
Constaté par l'utilisateur : aucun trait visible entre les colonnes du tableau
final malgré le CSS ajouté en E2. Cause racine : couleur `var(--theme-border-strong)`
= `rgba(255,255,255,0.1)` en thème sombre (10% d'opacité) — correcte pour une
bordure fine de 1px (usage prévu partout ailleurs dans ce fichier) mais quasi
invisible en aplat de 2px de haut sur fond sombre.
1. [x] Couleur remplacée par `var(--theme-text-muted)` (`rgba(255,255,255,0.55)`
   en dark / `rgba(0,0,0,0.55)` en light) — bien plus opaque tout en restant un
   ton discret (pas un accent vert).
2. [x] Vérifié dans le CSS précompilé (`public/assets/application-*.css`) que la
   règle contient bien la nouvelle valeur.
3. [ ] Vérif visuelle navigateur — non faite (pas de navigateur dans ce
   sandbox) ; à confirmer que 0.55 d'opacité est suffisamment visible SANS être
   trop appuyé, dans les deux thèmes.

## Bug corrigé — CSS totalement absent après suppression de `public/assets/`
Mon diagnostic précédent (juste au-dessus) était FAUX et l'action qui a suivi a
cassé tout le CSS du site (capture utilisateur : HTML brut, aucun style). Cause
racine réelle, confirmée par `curl` sur le serveur de dev déjà en cours (celui de
l'utilisateur) : ce projet n'a PAS de recompilation SCSS en direct en
développement — `public/assets/` (généré par `assets:precompile`) est la SEULE
source du CSS servi, comme en production. En supprimant ce dossier pour "lever
un manifeste figé qui bloquait la recompilation live", j'ai en fait supprimé
l'unique copie du CSS compilé qui existait — `curl` sur l'URL `.css` renvoyée
par la page a confirmé une vraie `ActionController::RoutingError` (pas une 404
Sprockets), preuve qu'aucune route de compilation live n'est montée.
Complication additionnelle : le serveur `rails server` déjà en cours (démarré
par l'utilisateur avant cette session) garde le manifeste/digest en mémoire
depuis son démarrage — régénérer `public/assets/` ne suffit donc pas seul, le
process continue de réclamer l'ANCIEN nom de fichier tant qu'il n'est pas
redémarré.
1. [x] `bin/rails assets:precompile` (sans `RAILS_ENV=test` cette fois, pour
   l'environnement réellement servi) — régénère `public/assets/` avec tout le
   SCSS/JS à jour (E1, E2, fix couleur, tout ce qui a été fait cette session).
2. [ ] **Redémarrer le serveur `rails server`** — action à faire côté
   utilisateur (son process tourne dans son propre terminal) : sans ça, le CSS
   régénéré sur disque ne sera pas repris par le process déjà démarré.
3. [x] Vérif visuelle navigateur — faite par l'utilisateur après redémarrage :
   le CSS général est revenu, les traits E2 étaient bien visibles.
4. **Leçon corrigée** (annule celle du dessus, fausse) : sur ce projet,
   `public/assets/` doit TOUJOURS exister et être à jour — ce n'est pas un
   artefact optionnel. Après tout changement SCSS/JS : `assets:precompile` PUIS
   redémarrage du serveur. Ne plus jamais supprimer ce dossier sans avoir un
   plan pour le regénérer + redémarrer dans la foulée. Détail complet dans
   `tasks/lessons.md` (entrée du 2026-07-28).

## Phase E2 — retirée (retour utilisateur, rendu jugé pas fantastique)
Une fois visible (après le fix ci-dessus), le rendu réel du fallback (traits
courts non reliés entre eux, cf. capture utilisateur) a été jugé pas assez
qualitatif pour une fonctionnalité non essentielle — exactement le risque
identifié dès l'implémentation ("fallback si le rendu simple ne suffit pas").
Décision : retirer plutôt que retenter une version plus ambitieuse maintenant
(nécessiterait de restructurer `.bracket__matches` en paires imbriquées, gros
chantier pour un gain purement visuel, pas jugé prioritaire).
1. [x] Bloc SCSS "Connecteurs entre tours (Lot 7, E2)" entièrement supprimé de
   `_tournament_bracket.scss` (règles `.bracket__round` / `::before` / `::after`
   sur `.tmatch-card`). Aucun autre fichier n'y faisait référence.
2. [x] Structure E1 (colonnes + cases "À déterminer") intacte, non concernée par
   ce retrait — seul l'habillage visuel des connecteurs disparaît.
3. [x] Suite tournois verte (70 runs).
4. [ ] `bin/rails assets:precompile` + redémarrage serveur nécessaires pour que
   le retrait soit visible (même contrainte que le reste, cf. leçon ci-dessus).
5. Plan initial (E2) considéré clos ici, sans suite prévue pour l'instant — à
   ne reprendre que si le besoin visuel redevient prioritaire, avec la
   restructuration en paires imbriquées comme piste sérieuse.

---

# Feature : vrai tirage au sort, liens profils (Vue d'ensemble), sélecteur de journée

Plan complet : `/home/axelb/.claude/plans/tidy-spinning-codd.md` (branche `matchsmodifstournoi`)

Demande initiale (4 points) — exploration a montré que 2 étaient déjà faits :
liens profils dans `_tmatch.html.erb` (onglet Matchs) et score adapté au sport
(`Sport#scoring_rules`, déjà branché de bout en bout). Restait donc : le vrai
tirage au sort, le lien profil manquant dans la Vue d'ensemble, et le sélecteur
de journée du championnat/poules.

## 1. Vrai tirage au sort
Root cause : `SwissPairing#build_pairs` (ronde 1, tout à égalité), `LeagueBuilder
#ordered_players`, `PoolBuilder#assign_pools!/#pool_schedules` triaient tous par
`id` (ordre d'inscription) → toujours "J1 vs J2, J3 vs J4…". `Tournament#rank_key`
retombait sur `display_name` (alphabétique) pour le seeding direct-au-bracket.
1. [x] Migration `draw_order:integer` sur `tournament_users`.
2. [x] `TournamentsController#start` : `assign_draw_order!` (shuffle + persist)
   AVANT `TournamentEngine.for(@tournament).next_round!`, dans la transaction.
3. [x] `SwissPairing#build_pairs` : départage `p.id` → `p.draw_order`.
4. [x] `LeagueBuilder#ordered_players` / `PoolBuilder#assign_pools!`/
   `#pool_schedules` : `order(:id)` → `order(:draw_order)`.
5. [x] `Tournament#rank_key` : dernier départage `display_name` → `draw_order`.
6. [x] `test/services/swiss_pairing_test.rb` : `Player` Struct + champ
   `draw_order` (défaut sur `id`, ne casse aucun test existant), + nouveau test
   prouvant que le tri suit bien draw_order et PAS l'id.
7. [x] Nouveau test contrôleur : `POST start` fige un draw_order (permutation
   complète 0..n-1) différent de l'ordre d'inscription (seed fixée pour
   reproductibilité).

## 2. Liens profils dans la Vue d'ensemble (`_bracket_cell.html.erb`)
1. [x] `link_to user_profil_path(player.user)` autour avatar+nom (même pattern
   que `_tmatch.html.erb`), branche bye et branche normale.
2. [x] SCSS `.bracket-cell__player-link` (mirror de `.tmatch-card__player-link`).
3. [x] Test contrôleur : lien présent avec le bon href sur un tournoi qui saute
   direct au tableau final (4 joueurs, `final_size` 4).

## 3. Sélecteur de journée (menu déroulant)
Championnat/poules seulement (jusqu'à 31 journées) — pas la ronde suisse (peu de
tours + `extra_columns` non rattaché à un tour précis).
1. [x] `_round_ribbon.html.erb` : local `paginated:` optionnel → `<select>`
   "Aller à la journée" au-dessus du ruban, présélectionné sur la journée en
   cours (1ère non terminée, sinon la dernière). Chaque colonne wrappée dans
   `.round-ribbon__page` avec `data-round-number`.
2. [x] `journee_selector_controller.js` (nouveau, calqué sur
   `tournament_tabs_controller.js`) : affiche une seule colonne à la fois, pilotée
   par le `<select>` (`change` event).
3. [x] `paginated: true` passé depuis `_board.html.erb` (championnat) et
   `_pool_phase.html.erb` (poules).
4. [x] SCSS `.round-ribbon--paginated`/`__picker`/`__select`/`__page` — code
   couleur du fichier existant (`--theme-bg-card`, `--theme-border`, accent
   `$green` au focus/hover), pas de `form-select` Bootstrap brut.
5. [x] Test contrôleur : select présent avec le bon nombre d'options et la bonne
   option `selected` après avoir fait avancer une journée.

## 4. Score adapté au sport — vérifié, rien à coder
`Sport#scoring_rules` (`mode: :score` sans sets pour football/handball/
basketball, `mode: :sets` pour tennis/padel/badminton/ping-pong/volleyball) déjà
branché sur `TournamentMatch` + `_score_modal.html.erb` + `tournament_score_
controller.js`, testé dans `sport_test.rb`. Confirmé à l'utilisateur, pas de
changement.

## Vérification
- [x] `bin/rails test` complet : 942 runs, 0 failures (44 erreurs Slack
  pré-existantes, sans rapport — credentials chiffrement manquants en local,
  hors périmètre de cette feature).
- [x] `bin/rails assets:precompile` (SCSS + nouveau contrôleur JS compilent).
- [ ] Vérif visuelle navigateur (thème clair + sombre) — à faire par
  l'utilisateur ; lui rappeler de redémarrer `rails server` après précompile
  (cf. leçon Phase E1/E2 ci-dessus : pas de live-reload SCSS en dev sur ce projet).

---

# Itération 2 : retours utilisateur post-review (classement, sélecteur, scores)

Suite au retour visuel de l'utilisateur sur l'itération 1 : lien profil manquant
dans "Classement", sélecteur de journée pas assez habillé une fois ouvert, et
scores affichés en 2 lignes empilées + score FAUX pour les sports à score simple
(toujours 1-0/0-0 au lieu du vrai score marqué).

## 1. Lien profil manquant dans "Classement"
1. [x] `_ranking_table.html.erb` : avatar+nom de `.is-player` enveloppés dans
   `link_to user_profil_path(tu.user)` (même principe que `_tmatch`/`_bracket_cell`).
2. [x] SCSS `.tournament-ranking__player-link`.

## 2. Sélecteur de journée : `<select>` natif → menu déroulant CUSTOM
Root cause du "pas terrible une fois ouvert" : un `<select>` natif est habillé
par l'OS/le navigateur une fois ouvert, aucun moyen de le styler pour matcher le
code couleur de la page.
1. [x] `_round_ribbon.html.erb` : remplace le `<select>` par un bouton
   (`.journee-picker__toggle`, façon `.phase-nav__pill`) + une liste custom
   (`.journee-picker__menu`/`__option`, role listbox/option). L'état initial
   (journée en cours visible, reste `hidden`) est posé CÔTÉ SERVEUR (pas de flash
   JS au chargement).
2. [x] `journee_selector_controller.js` réécrit : `toggle`/`open`/`close` (+ fermeture
   au clic extérieur) et `choose` (bascule la colonne visible + met à jour le
   libellé + l'état actif de l'option cliquée).
3. [x] SCSS `.journee-picker` (remplace `.round-ribbon__select`/`__picker`) :
   pilule + menu flottant, mêmes variables de thème que le reste du fichier.
4. [x] Test contrôleur mis à jour pour la nouvelle structure (bouton + options,
   colonnes `hidden`/visible posées côté serveur).

## 3. Scores : vrai score + affichage centré compact
Root cause du "toujours 1-0/0-0" : `sets_won_by` compte des SETS gagnés (0 ou 1
en mode :score, puisqu'une seule "paire" = le score final) — jamais le score réel.
1. [x] `TournamentMatch#display_score_for(player)` (nouveau) : `points_won_by`
   (vrai score) en mode `:score`, `sets_won_by` (inchangé) en mode `:sets`.
   `#score_summary` (nouveau) : équivalent de `sets_summary` mais basé dessus.
2. [x] `_bracket_cell.html.erb` : `sets_won_by` → `display_score_for` (correction
   seule, layout inchangé — pas la demande explicite de l'utilisateur ici).
3. [x] `_tmatch.html.erb` : restructuré en scoreline centrée façon tableau de
   scores sportif (2 `.tmatch-card__player` flex de part et d'autre d'un
   `.tmatch-card__center` — score/statut "VS"/"En cours"/"Fin" — vainqueur
   surligné en vert sur son score) au lieu de 2 lignes empilées nom+score.
   Score du footer (redondant avec la scoreline) retiré. Icône de victoire
   séparée retirée (remplacée par le surlignage vert du score).
4. [x] SCSS : `.tmatch-card__scoreline`/`__center`/`__center-score`/
   `__center-status` (nouveau), `.tmatch-card__sets`/`__win-icon` (retirés,
   plus utilisés).
5. [x] Tests : `tournament_match_test.rb` (display_score_for/score_summary en
   mode :sets ET :score, avec assertion explicite que sets_won_by donnerait
   0/1 pour prouver le bug évité) + `tournaments_controller_test.rb` (le score
   réel "3-2" s'affiche bien dans la scoreline pour un match de football).

## Vérification itération 2
- [x] `bin/rails test` complet : 945 runs, 0 failures (mêmes 44 erreurs Slack
  pré-existantes, hors périmètre).
- [x] `bin/rails assets:precompile` (SCSS + JS compilent).
- [ ] Vérif visuelle navigateur (thème clair + sombre) — même rappel que
  l'itération 1 : redémarrer `rails server` après précompile.


---

# Gestion des organisateurs après création d'un tournoi

## Problème

Le bloc « Co-organisateur » de `_form.html.erb` est conditionné à `@tournament.new_record?`
(l. 195) et `add_co_organizer` n'est appelé que depuis `#create`. Résultat : une fois le
tournoi créé, l'admin ne peut plus ni ajouter/retirer un co-organisateur, ni transmettre
l'administration. (Trou déjà noté dans `docs/TOURNOI.md:243`.)

## Décisions (validées)

- Co-organisateurs **illimités**, gérés depuis `/tournois/:id/edit`.
- **Seul l'admin** (`tournaments.user_id`) gère la liste — un co-org ne peut pas se coopter.
- **Transfert d'administration** possible : l'ancien admin devient co-organisateur.

## Contrainte structurante

Index unique `[tournament_id, user_id]` sur `tournament_users` → un joueur inscrit ne peut
pas avoir une 2ᵉ ligne co-org : le promouvoir = **UPDATE de son `role`**, donc il perd sa
place de joueur. Interdit une fois le tournoi lancé (il a déjà des matchs / un classement).

## Étapes

- [x] `routes.rb` : 3 member actions francisées (`co-organisateurs`, `.../retrait`, `transfert-admin`)
- [x] `TournamentPolicy` : `manage_organizers?` → `owner?` ; `transfer_ownership?` → `owner? && !completed?`
- [x] `TournamentsController` : `add_co_organizer` / `remove_co_organizer` / `transfer_ownership`
      (helper de création renommé `add_initial_co_organizer`) + exclusions dans `#search`
- [x] `TournamentUser` : prédicats `player?` / `co_organizer?`
- [x] Vue `_organizers_manager.html.erb` rendue par `edit.html.erb` **hors** du `form_with`
      (pas de formulaire imbriqué) — réutilise `invite-search`
- [x] SCSS dans `pages/_tournaments_form.scss`
- [x] Tests `test/controllers/tournament_organizers_test.rb`

## Vérification

`bin/rails test test/controllers/tournament_organizers_test.rb` puis parcours manuel
sur `/tournois/<slug>/edit`.
