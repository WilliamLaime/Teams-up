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
