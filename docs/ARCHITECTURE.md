# Teams-up — Architecture

> Référence consultée **à la demande** pour comprendre les modèles, associations et flux.
> Pour fouiller les fichiers volumineux cités plus bas, **déléguer la lecture à un sous-agent Explore**.

## Modèles clés

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

## Structure fichiers

| Dossier | Contenu |
|---|---|
| `app/controllers/users/` | Surcharges Devise (sessions, registrations, passwords, omniauth_callbacks) |
| `app/controllers/admin/` | Dashboard, modération, logs |
| `app/policies/` | Policies Pundit — **toujours** `authorize @resource` dans les controllers |
| `app/views/shared/` | Partials réutilisables (`_btn_primary`, `_btn_secondary`, `_match_card`, etc.) |
| `app/javascript/controllers/` | Controllers Stimulus — snake_case, suffixe `_controller.js` |
| `app/services/image_moderation/` | Modération d'images (checker + adapters, Sightengine) |
| `app/assets/stylesheets/` | SCSS — voir `docs/DESIGN-SYSTEM.md` |

## Autorisations

11 policies Pundit dans `app/policies/`. `ApplicationController` impose `verify_authorized` + `verify_policy_scoped` → toujours `authorize` / `policy_scope`, jamais de filtrage manuel.

## Zones complexes (lecture ciblée recommandée)

Ces fichiers sont volumineux — lire des plages ciblées ou passer par un sous-agent Explore plutôt que de tout charger.

| Domaine | Fichiers | Points d'attention |
|---|---|---|
| **Recherche / création de matchs** | `MatchesController` (~580 l.), `Match` (~280 l.) | Préfiltres issus des préférences du profil **vs** filtres manuels du formulaire de recherche ; scopes (upcoming, publicly_visible, visible_for_genre…) ; votes & validations |
| **Détail match** | `app/views/matches/show.html.erb` (~1570 l.) | Méga-vue : infos, chat, participants, votes, actions |
| **Formulaire match** | `app/views/matches/_form.html.erb` (~1045 l.) + `match_form_controller.js` (~565 l.) | Synchronisation temps réel formulaire ↔ récap sidebar, boutons de niveau par sport, calcul du prix |
| **Profil** | `ProfilesController` (~535 l.), `Profil` | Upload d'images + modération via `app/services/image_moderation/` (concern `Moderatable`) |
| **Recherche de lieux** | `place_search_controller.js` (~550 l.) | Autocomplétion géolocalisée (Mapbox / OSM) |

## Temps réel (ActionCable + Turbo Streams)

- `Match` diffuse via `broadcasts_to` (callbacks) — messages de chat et mises à jour live de la page match.
- Les vues s'abonnent via `turbo_stream_from`.
- Toute modale Bootstrap doit être `dispose()` sur `turbo:before-render` (voir pièges Turbo dans `CLAUDE.md`).
