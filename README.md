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

## Prérequis

- [Ruby 3.3.5](https://www.ruby-lang.org/) (via `rbenv` ou `asdf`)
- [PostgreSQL 14+](https://www.postgresql.org/)
- [Node.js 18+](https://nodejs.org/) (pour Importmap / assets)
- Compte [Cloudinary](https://cloudinary.com/) (stockage images)
- Compte [Google Cloud](https://console.cloud.google.com/) (OAuth2 — optionnel en dev)
- Compte [hCaptcha](https://www.hcaptcha.com/) (optionnel en dev)

---

## Installation locale

```bash
# 1. Cloner le dépôt
git clone https://github.com/WilliamLaime/Teams-up.git
cd Teams-up

# 2. Installer les gems Ruby
bundle install

# 3. Configurer les variables d'environnement (voir section ci-dessous)
cp .env.example .env
# Éditez .env avec vos propres clés

# 4. Créer et migrer la base de données
rails db:create db:migrate

# 5. (Optionnel) Charger les données de seed
rails db:seed

# 6. Lancer le serveur
rails server
```

L'application est disponible sur [http://localhost:3000](http://localhost:3000).

---

## Variables d'environnement

Créez un fichier `.env` à la racine du projet avec les clés suivantes :

```bash
# Base de données (automatique en dev si PostgreSQL est local)
DATABASE_URL=postgresql://user:password@localhost/teams_up_production

# Cloudinary — stockage des avatars et images
CLOUDINARY_URL=cloudinary://api_key:api_secret@cloud_name

# Google OAuth2 (connexion Google)
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# hCaptcha — protection anti-bot sur l'inscription
HCAPTCHA_SITE_KEY=your_hcaptcha_site_key
HCAPTCHA_SECRET_KEY=your_hcaptcha_secret_key

# Sightengine — modération d'images par IA (optionnel)
SIGHTENGINE_API_USER=your_sightengine_user
SIGHTENGINE_API_SECRET=your_sightengine_secret

# Sentry — monitoring des erreurs (optionnel)
SENTRY_DSN=https://your_sentry_dsn@sentry.io/...

# Ngrok — tunneling HTTPS local (optionnel, pour OAuth en dev)
NGROK_URL=https://your-ngrok-url.ngrok.io
```

> **Note :** En développement, `GOOGLE_CLIENT_ID`, `HCAPTCHA_*` et `SIGHTENGINE_*` peuvent rester vides — les fonctionnalités associées seront simplement désactivées ou en mode test.

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

## Déploiement (Railway.app)

L'application est conteneurisée et déployée sur [Railway](https://railway.app/) via Docker + Thruster (reverse proxy devant Puma).

```bash
# Construire l'image Docker localement
docker build -t teams-up .

# Variables à définir dans Railway Dashboard
DATABASE_URL=...
CLOUDINARY_URL=...
GOOGLE_CLIENT_ID=...
# etc.
```

Le health-check est exposé sur `GET /up` (Rails 8 built-in).

---

## Tests

```bash
# Lancer toute la suite de tests
rails test

# Tests système (Capybara + Selenium)
rails test:system

# Audit de sécurité des gems
bundle exec bundler-audit check --update

# Analyse statique de sécurité
bundle exec brakeman
```

---

## Contribution

1. Forkez le dépôt
2. Créez une branche feature : `git checkout -b ma-feature`
3. Committez vos changements : `git commit -m "Ajout ma feature"`
4. Pushez la branche : `git push origin ma-feature`
5. Ouvrez une Pull Request

> Consultez `CLAUDE.md` pour les conventions de code, nommage, et les patterns attendus.

---

## License

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

---

<div align="center">

Fait avec ❤️ pour le sport amateur

</div>
