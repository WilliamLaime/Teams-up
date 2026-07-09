# Feature Tournoi — Pilotage

> Document de suivi de la feature Tournoi. À relire au démarrage de chaque session :
> il indique **où on en est** et **quelle est la prochaine étape**.
> Sources de conception : recaps réunion du 9 juillet 2026 (Notion + Claude).

---

## 🎯 Vision

Centraliser dans Team Up la gestion des tournois amateurs (aujourd'hui sous Excel).
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

### 🔜 Lot 3 — Ronde Suisse + tableau final
- [ ] Génération des rondes (tirage intégral, jamais deux fois le même adversaire).
- [ ] Qualification (3 V) / élimination (3 D). Configs figées par nombre de joueurs.
- [ ] Final 8 en élimination directe, seeding (aléatoire, puis set average / point average).
- [ ] Idée : **animation de tirage au sort** au lancement.

### 🔜 Lot 4 — Saisie des scores & matchs
- [ ] Score set par set, saisissable par 4 rôles (admin, co-orga, joueur A, joueur B).
- [ ] Stockage détaillé des scores (pour set average / point average plus tard).
- [ ] Affichage score global (ex. 3-1) + détail set par set en modal.
- [ ] Verrouillage définitif du tour une fois tous les scores saisis.
- [ ] Création de match depuis la **vue tournoi** ET depuis la **création de match standard** (association au tournoi).
- [ ] Règle des 2 points d'écart (ping-pong).

### 💡 Futurs
- [ ] **Gamification** : badges, trophées, achievements (1er tournoi gagné, 500 pts, 10e set…).
- [ ] **Calendrier des matchs** (éviter les conflits d'horaire).
- [ ] **Intégration Slack** (Bolt) : notifications de match + boutons d'action (voir / s'inscrire).
- [ ] **Dashboard personnel** à la connexion (tournois + matchs à venir, filtrés par sport du profil).
- [ ] **Export agenda** (Outlook) — déjà fonctionnel pour les matchs.

---

## 📌 État courant

**Lots 1 & 2 livrés.** La page `/tournois` affiche 3 sections (cartes cohérentes avec
les matchs). Le **formulaire de création** (`/tournois/new`) est fonctionnel : sport →
format compatible → paramètres → date/heure/lieu → joueurs (presets ou mode Libre) &
clôture, avec co-organisateur et auto-inscription optionnelle du créateur.

### Décisions actées
- **Statuts** (`tournaments.status`) : `open` / `in_progress` / `completed`.
- **Formats** (`tournaments.format`) : `ronde_suisse` / `poules` / `championnat`.
- **3 sections** de la page liste :
  1. *Mes tournois en cours* — inscrit + non terminé (masquée si déconnecté).
  2. *Tournois à rejoindre* — `open`, deadline future, non complet, non inscrit.
  3. *Tournois en cours* (publics) — `in_progress`, non inscrit → lecture seule.
- **Droits** : tout utilisateur connecté peut créer un tournoi (en devient l'admin).
- **Co-organisateur** (tranché Lot 2) : **pas de nouvelle colonne** — rôle `co_organisateur`
  dans `tournament_users` (n'occupe pas de place de joueur). Droits fins sur la gestion du
  tableau : à câbler au Lot 3 via `Tournament#organizer?`.
- **Nombre de joueurs** : presets 8/16/32 **+ mode Libre** (nombre arbitraire). Structures
  figées (`Tournament::STRUCTURE_PRESETS`) et propositions du mode Libre **provisoires** —
  affichées en aperçu lecture seule, à affiner au Lot 3.
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

**Lot 3 — Ronde Suisse + tableau final.** Génération des rondes (tirage intégral, jamais
deux fois le même adversaire), qualification (3 V) / élimination (3 D), puis Final 8 en
élimination directe. Figer les configs par nombre de joueurs (remplacer les presets
provisoires) et remplacer le placeholder `tournaments/show` par le vrai tableau.
