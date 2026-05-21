<div align="center">

# ⚽ Teams Up

**Trouvez des coéquipiers, organisez vos matchs, progressez ensemble.**

Application web de mise en relation pour sportifs amateurs — créez ou rejoignez des matchs, formez des équipes, tchattez en temps réel et suivez vos stats.

[![Ruby](https://img.shields.io/badge/Ruby-3.3.5-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/Rails-8.1.3-CC0000?logo=rubyonrails&logoColor=white)](https://rubyonrails.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Bootstrap](https://img.shields.io/badge/Bootstrap-5.3-7952B3?logo=bootstrap&logoColor=white)](https://getbootstrap.com/)
[![Deploy on Railway](https://img.shields.io/badge/Deploy-Railway-0B0D0E?logo=railway&logoColor=white)](https://railway.app/)

</div>

---

## Fonctionnalités

- **Matchs** — Créer, rechercher et rejoindre des matchs par sport, niveau, ville et date
- **Équipes** — Former une équipe, inviter des joueurs, nommer un capitaine
- **Chat temps réel** — Messagerie par match, par équipe et en 1-to-1 (ActionCable + Turbo)
- **Profils joueurs** — Statistiques par sport, niveaux, avis et classements XP
- **Votes & Achievements** — Élire le joueur du match, débloquer des badges de progression
- **Amis** — Envoyer/accepter des demandes d'amis, retrouver ses contacts facilement
- **Cartes & Terrains** — Recherche de terrains par géolocalisation (Mapbox GL)
- **Notifications** — Notifications in-app et push (PWA + Web Push API)
- **Auth sécurisée** — Inscription e-mail + connexion Google OAuth2 + hCaptcha
- **Admin panel** — Dashboard KPI, modération de contenu (IA), logs de sécurité, liste d'attente
- **PWA** — Application installable sur mobile, mode hors-ligne, icônes natives

---

## Stack technique

| Couche | Technologies |
|---|---|
| **Backend** | Rails 8.1.3 · Ruby 3.3.5 · PostgreSQL · Puma · Thruster |
| **Frontend** | Hotwire (Turbo + Stimulus) · Bootstrap 5.3 · SCSS · Importmap |
| **Temps réel** | ActionCable · Turbo Streams · Solid Cable |
| **Auth & Sécu** | Devise · Google OAuth2 · Pundit · Rack::Attack · hCaptcha |
| **Fichiers** | Active Storage · Cloudinary · Image Processing |
| **Recherche** | pg_search (full-text PostgreSQL) |
| **Pagination** | Pagy 9.x |
| **Monitoring** | Sentry · Security Logs |
| **Déploiement** | Docker · Railway.app · Kamal |
| **Tests** | Minitest · Capybara · Selenium · WebMock |

---

## Architecture — Modèles principaux

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
└── belongs_to :current_sport       → sport actif sélectionné

Match
├── belongs_to :user                → créateur
├── belongs_to :sport, :venue
├── belongs_to :team                → optionnel
├── has_many   :match_users         → participants
└── has_many   :messages            → chat du match

Team
├── belongs_to :captain             → User
├── has_many   :team_members
├── has_many   :team_invitations
└── has_one_attached :badge_image
```

**26 modèles · 24 controllers · 46 Stimulus controllers · 11 policies Pundit**

---

## Structure du projet

```
Teams-up/
├── app/
│   ├── controllers/          # 24 controllers + admin/ + users/ (Devise)
│   ├── models/               # 26 modèles ActiveRecord
│   ├── views/
│   │   └── shared/           # Partials réutilisables (boutons, cartes, nav...)
│   ├── javascript/
│   │   └── controllers/      # 46 Stimulus controllers
│   ├── assets/
│   │   └── stylesheets/
│   │       ├── config/       # Variables SCSS (_colors, _fonts, _bootstrap_variables)
│   │       ├── components/   # Un fichier SCSS par composant
│   │       └── pages/        # Un fichier SCSS par page
│   └── policies/             # 11 policies Pundit
├── config/
│   ├── routes.rb             # Routes de l'application
│   └── initializers/         # Devise, Pundit, Rack::Attack, Sentry...
├── db/
│   ├── migrate/              # Migrations PostgreSQL
│   └── schema.rb             # Schéma courant
├── public/                   # Icônes PWA (icon.png, icon-192.png, icon-512.png)
├── Dockerfile                # Build de production multi-stage
├── railway.toml              # Configuration Railway.app
└── CLAUDE.md                 # Guidelines pour le développement assisté par IA
```

---

## Design system

| Variable | Couleur | Usage |
|---|---|---|
| `$green` | `#1EDD88` | CTA principal, liens actifs, badges |
| `$red` | `#FD1015` | Danger, erreurs |
| `$orange` | `#E67E22` | Warning, accent |
| `$dark-bg` | `#111111` | Fond navbar / hero / footer |
| `$dark-card-bg` | `#1a1c1a` | Fond cartes dark |

Typographie : **Work Sans** (corps) · **Nunito** (titres) · **Bebas Neue** (display/hero)

---

<div align="center">

Fait avec ❤️ pour le sport amateur

</div>
