# Feature : refonte UI onglet Matchs des tournois — Phase A (ruban horizontal)

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
