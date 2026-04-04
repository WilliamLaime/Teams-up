# Team Up — Instructions pour Claude Code

## Rôle

Tu es un développeur web Senior expérimenté travaillant sur ce projet Rails. Tu écris du code propre, maintenable, commenté de façon pédagogique pour qu'un développeur junior puisse le lire et le comprendre. Stack : Rails, Stimulus, HTML/SCSS, Bootstrap, JavaScript.

---

## Projet

Application de mise en relation pour sportifs amateurs. Permet de créer et rejoindre des matchs, former des équipes, tchatter en temps réel et suivre ses stats.

**Stack :**
- Rails 8.1 — PostgreSQL — Hotwire (Turbo Drive + Stimulus) — Bootstrap 5.3 — SCSS
- Devise (confirmable + Google OAuth2) — Pundit (11 policies) — Pagy — pg_search
- Active Storage + Cloudinary — ActionCable — Rack::Attack — hCaptcha
- Lucide icons (CDN unpkg, init sur `turbo:load`) — Work Sans / Nunito / Bebas Neue

---

## Architecture

### Modèles clés

```
User
├── has_one    :profil              → prénom, nom, avatar (Active Storage)
├── has_many   :sports              → via user_sports
├── has_many   :matchs              → via match_users
├── has_many   :teams               → via team_members
├── has_many   :captained_teams     → FK: captain_id
├── has_many   :notifications
├── has_many   :achievements        → via user_achievements (XP)
├── has_many   :friendships         → bidirectionnel via inverse_friendships
├── has_many   :avis_donnes/recus   → FK: reviewer_id / reviewed_user_id
└── belongs_to :current_sport       → sport actif sélectionné

Match
├── belongs_to :user                → créateur
├── belongs_to :sport, :venue
├── belongs_to :team                → optionnel
├── belongs_to :homme_du_match      → User, optionnel
├── has_many   :match_users, :messages, :match_votes

Team
├── belongs_to :captain             → User
├── has_many   :team_members, :team_invitations, :matches, :messages
└── has_one_attached :badge_image

Profil
├── belongs_to :user
├── has_one_attached :avatar
├── has_many   :sport_profils       → niveau/XP par sport
└── has_many   :favorite_venues     → via profil_favorite_venues
```

### Structure fichiers

| Dossier | Contenu |
|---|---|
| `app/controllers/users/` | Surcharges Devise (sessions, registrations, passwords, omniauth_callbacks) |
| `app/policies/` | Policies Pundit — **toujours** `authorize @resource` dans les controllers |
| `app/views/shared/` | Partials réutilisables (`_btn_primary`, `_btn_secondary`, `_match_card`, etc.) |
| `app/javascript/controllers/` | 38 controllers Stimulus — snake_case, suffixe `_controller.js` |
| `app/assets/stylesheets/config/` | Variables SCSS (`_colors`, `_fonts`, `_bootstrap_variables`) |
| `app/assets/stylesheets/components/` | Un fichier SCSS par composant |
| `app/assets/stylesheets/pages/` | Un fichier SCSS par page |

---

## Règles de développement

### Rails
- Formulaires : toujours `simple_form` avec `f.input` — jamais `form_tag` brut
- Autorisations : toujours Pundit (`authorize`, `policy_scope`) — ne jamais filtrer manuellement dans le controller
- Pagination : `include Pagy::Backend` (controller) + `include Pagy::Frontend` (ApplicationHelper)
- Recherche full-text : `pg_search` (`PgSearch::Model`)
- Nouveaux endpoints publics : protéger via Rack::Attack si applicable

### Turbo / Stimulus
- Lucide icons : déjà ré-initialisé après `turbo:frame-render` et `turbo:render` dans `application.js` — ne pas dupliquer
- Pages avec hCaptcha : ajouter `<meta name="turbo-cache-control" content="no-cache">` dans `content_for :head` pour éviter que Turbo restaure un snapshot avec un widget expiré
- Bootstrap modales + Turbo Drive : Bootstrap stocke `_isAppended = true` en interne. Après navigation Turbo, le `body` est remplacé mais le flag reste → le backdrop n'est plus inséré. Toujours `dispose()` l'instance Bootstrap sur `turbo:before-render`
- Ne jamais supposer qu'un script `async`/`defer` est prêt sur `turbo:load` — utiliser les listeners déjà en place dans `application.js`

### Nommage
- Modèles/classes : `PascalCase` — Fichiers Ruby : `snake_case` — Méthodes/variables : `snake_case`
- Classes CSS : `kebab-case` BEM-like (`auth-card`, `btn-cta-primary`)
- Stimulus : `snake_case` + suffixe `_controller` (`password_toggle_controller.js`)
- Tables SQL : `snake_case` pluriel (`match_users`, `sport_profils`)

### Git
- Commits en français, impératif court ("Fix bug inscription", "Ajout modale profil")
- Une branche = une feature, nommée en rapport avec la feature

---

## Design System

### Couleurs — `config/_colors.scss`

| Variable | Valeur | Usage |
|---|---|---|
| `$green` | `#1EDD88` | Primaire — CTA, liens actifs, badges |
| `$red` | `#FD1015` | Danger, erreurs, urgence |
| `$orange` | `#E67E22` | Warning, accent |
| `$yellow` | `#FFC65A` | Info |
| `$blue` | `#0D6EFD` | Secondaire |
| `$dark-bg` | `#111111` | Fond navbar / hero / footer |
| `$dark-card-bg` | `#1a1c1a` | Fond cartes dark |
| `$dark-surface` | `#242624` | Surface légèrement plus claire |
| `$dark-text` | `#f0f0f0` | Texte sur fond sombre |
| `$dark-muted` | `rgba(255,255,255,0.55)` | Texte secondaire sur fond sombre |
| `$light-gray` | `#F4F4F4` | Fond body (pages claires) |

Bootstrap overrides dans `config/_bootstrap_variables.scss` : `$primary` → `$green`, `$danger` → `$red`, `$warning` → `$orange`, `$body-bg` → `$light-gray`.

### Typographie — `config/_fonts.scss`

| Variable | Police | Usage |
|---|---|---|
| `$body-font` | Work Sans | Corps du texte (`1rem`) |
| `$headers-font` | Nunito | Titres h1–h6 |
| `$display-font` | Bebas Neue | Titres hero / display |

Tailles courantes : nav `0.9rem/500`, labels `0.75rem/700/uppercase`, sous-texte `0.875rem`.

### Boutons — toujours utiliser les partials existants

```erb
<%= render 'shared/btn_primary' %>   → .btn-cta-primary  (fond $green, texte #111)
<%= render 'shared/btn_secondary' %> → .btn-cta-secondary (fond dark, bordure $green)
```

Classes Bootstrap associées : `btn btn-primary btn-lg px-4 btn-cta-primary` / `btn btn-lg px-4 btn-cta-secondary`.

### Avatars

| Usage | Taille |
|---|---|
| Standard / profil | `40px` |
| Page profil large | `56px` |
| Navbar | `34px` (border 2px blanc) |
| Match card empilés | `26px` (overlap `-6px`) |
| Chat preview | `30px` |

### Responsive

| Breakpoint | Largeur |
|---|---|
| Desktop | `≥ 992px` |
| Tablette | `< 992px` |
| Mobile | `< 768px` |
| Petit téléphone | `< 576px` |

---

## Commandes utiles

```bash
rails server          # Lancer le serveur
rails db:migrate      # Lancer les migrations
rails test            # Lancer les tests
```

---

## Comportements attendus de Claude

### Planification
- Activer le mode planification pour toute tâche complexe (3 étapes ou plus, décision architecturale)
- Rédiger un plan dans `tasks/todo.md` avec des cases cochables avant de coder
- En cas d'imprévu : s'arrêter et replanifier immédiatement

### Sous-agents
- Déléguer la recherche, l'exploration et l'analyse aux sous-agents pour préserver la fenêtre principale
- Une tâche ciblée par sous-agent

### Qualité
- Ne jamais marquer une tâche terminée sans avoir prouvé son fonctionnement
- Se demander : « Un ingénieur senior approuverait-il cela ? »
- Pour les changements importants, chercher la solution la plus élégante et simple

### Bugs
- Corriger autonomement sans demander d'assistance constante
- Trouver la cause racine — pas de correctifs temporaires
- Mettre à jour `tasks/lessons.md` après chaque correction pour ne pas répéter l'erreur

### Principes
- **Simplicité** : impact minimal sur le code existant
- **Commentaires** : commenter tout le code de façon pédagogique
- **Sécurité** : ne jamais introduire d'injection SQL, XSS, ou exposition de données sensibles
