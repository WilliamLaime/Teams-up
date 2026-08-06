# Sécurité & données personnelles — Teams-up

Ce document tient lieu de **registre des traitements simplifié** (RGPD art. 30) et de référence
sécurité du projet. Il est la **source de vérité du contrôle automatisé `bin/pii-guard`** :
toute colonne de `db/schema.rb` ressemblant à une donnée personnelle doit figurer dans le
tableau §1, sinon la CI échoue.

> **Quand tu ajoutes une colonne** contenant une donnée personnelle : ajoute-la au tableau §1
> avec sa finalité, sa base légale et sa durée de conservation. C'est une décision produit,
> pas une formalité — la durée doit être réellement applicable (purge automatisée ou
> suppression liée au compte).

Pour auditer ou corriger un point de sécurité, utiliser l'agent **`security-rgpd-expert`**
(`.claude/agents/security-rgpd-expert.md`).

---

## 1. Cartographie des données personnelles

Format des lignes : `` | `table.colonne` | finalité | base légale | durée | chiffré | ``
(ne pas modifier ce format, il est parsé par `bin/pii-guard`).

| Colonne | Finalité | Base légale | Durée de conservation | Chiffré |
|---|---|---|---|---|
| `users.email` | Identifiant de connexion, notifications transactionnelles | Exécution du contrat (CGU) | Durée de vie du compte ; supprimé immédiatement à la demande | Non (index unique nécessaire) |
| `users.unconfirmed_email` | Vérification d'un changement d'adresse (Devise `reconfirmable`) | Exécution du contrat | Jusqu'à confirmation ; purge des comptes jamais confirmés après 12 mois *(backlog P3)* | Non |
| `users.genre` | Composition des matchs et équipes (mixte / féminin / masculin) | Intérêt légitime — champ facultatif | Durée de vie du compte | Non |
| `users.uid` | Identifiant Google renvoyé par OAuth2 | Exécution du contrat (connexion SSO) | Durée de vie du compte | Non |
| `profils.first_name` | Identification du joueur auprès des autres participants | Exécution du contrat | Durée de vie du compte | Non (recherche `pg_search`) |
| `profils.last_name` | Identification du joueur auprès des autres participants | Exécution du contrat | Durée de vie du compte | Non (recherche `pg_search`) |
| `profils.phone` | Contact entre joueurs d'un même match — facultatif | Consentement (saisie volontaire) | Durée de vie du compte | Non *(chiffrement en backlog P2)* |
| `profils.address` | Proposition de matchs proches — facultatif | Consentement (saisie volontaire) | Durée de vie du compte | Non *(chiffrement en backlog P2)* |
| `profils.localisation` | Ville/zone de jeu déclarée — facultatif | Consentement (saisie volontaire) | Durée de vie du compte | Non |
| `profils.preferred_city` | Filtrage des matchs par ville | Exécution du contrat | Durée de vie du compte | Non (colonne indexée) |
| `contact_messages.email` | Réponse à une demande de contact | Intérêt légitime | 12 mois après traitement *(backlog P3 : purge)* | Non |
| `contact_messages.nom` | Réponse à une demande de contact | Intérêt légitime | 12 mois après traitement *(backlog P3 : purge)* | Non |
| `contact_messages.prenom` | Réponse à une demande de contact | Intérêt légitime | 12 mois après traitement *(backlog P3 : purge)* | Non |
| `waitlist_entries.email` | Information de l'ouverture du service | Consentement | Jusqu'au lancement + 12 mois | Non (index unique) |
| `security_logs.ip_address` | Détection d'abus, preuve en cas d'incident (RGPD art. 32) | Intérêt légitime / obligation de sécurité | **12 mois** — `rake security_logs:purge` | Non |
| `security_logs.user_agent` | Détection d'abus, preuve en cas d'incident | Intérêt légitime / obligation de sécurité | **12 mois** — `rake security_logs:purge` | Non |
| `push_subscriptions.endpoint` | Envoi des notifications Web Push | Consentement (autorisation navigateur) | Jusqu'au désabonnement ou suppression du compte | Non |
| `push_subscriptions.p256dh` | Clé publique de chiffrement du push | Consentement | Jusqu'au désabonnement ou suppression du compte | Non |
| `push_subscriptions.auth` | Secret d'authentification du push | Consentement | Jusqu'au désabonnement ou suppression du compte | Non |
| `slack_identities.slack_user_id` | Lien entre un compte Teams-up et un compte Slack | Consentement (installation de l'app) | Jusqu'à la désinstallation | Non |
| `slack_workspaces.bot_token` | Jeton d'API du bot Slack (secret, pas une donnée personnelle) | Exécution du contrat | Jusqu'à la désinstallation | **Oui** (`encrypts`) |
| `matches.pin_latitude` | Point de rendez-vous précis d'un match, posé par l'organisateur sur la carte. Peut désigner une adresse privée (match chez un particulier) → traitée comme **donnée personnelle indirecte**, au contraire de `venues.latitude` qui décrit un équipement public | Consentement (saisie volontaire de l'organisateur) | Durée de vie du match | Non |
| `matches.pin_longitude` | Idem `matches.pin_latitude` (l'autre moitié de la coordonnée) | Consentement (saisie volontaire de l'organisateur) | Durée de vie du match | Non |
| `venues.address` | Adresse d'un équipement sportif — **donnée de lieu public, pas de PII** | Intérêt légitime | Illimitée | Non |
| `venues.city` | Ville d'un équipement sportif — **pas de PII** | Intérêt légitime | Illimitée | Non |
| `venues.latitude` | Position d'un équipement sportif — **pas de PII** | Intérêt légitime | Illimitée | Non |
| `venues.longitude` | Position d'un équipement sportif — **pas de PII** | Intérêt légitime | Illimitée | Non |

### Contenus rédigés par les utilisateurs

`messages`, `private_conversations`, `avis`, `profils.description`, `matches.description` :
textes libres pouvant contenir des données personnelles saisies volontairement. Conservés
pour la durée de vie du compte auteur. Les images (`active_storage_blobs` : avatars,
blasons, covers) sont des données personnelles à part entière et passent par la modération
NSFW (`app/models/concerns/moderatable.rb`).

**Résidu connu après suppression de compte** : `messages` et `avis` ne sont pas en
`dependent: :destroy` sur `User` — les contenus restent, détachés de leur auteur. À arbitrer
(anonymisation plutôt que suppression, pour ne pas trouer les conversations) → backlog P2.

### Pas de données sensibles

Aucune donnée de l'article 9 (santé, origine, opinions, orientation sexuelle) n'est collectée.
`users.genre` n'est pas une donnée sensible mais reste facultatif.
Aucune date de naissance, aucune géolocalisation d'utilisateur persistée (le GPS est un
paramètre transitoire de `venues_controller#search`).

---

## 2. Sous-traitants et transferts

| Destinataire | Données transmises | Localisation | Notes |
|---|---|---|---|
| **Cloudinary** | Images (avatars, blasons, covers) | UE/US | Assets servis en **URL publique non signée** → backlog P3 |
| **Sentry** | Traces d'erreur | Région **EU** | `send_default_pii = false` (`config/initializers/sentry.rb`) |
| **Google (OAuth2)** | Email, identifiant, avatar | US | Connexion SSO, à l'initiative de l'utilisateur |
| **hCaptcha** | Adresse IP, signaux navigateur | US | Anti-abus sur les formulaires d'authentification |
| **Slack** | Identifiants d'espace de travail et d'utilisateur Slack | US | Uniquement si l'intégration est installée |
| **Nominatim (OSM)** | Requêtes de géocodage de **lieux** | UE | Aucune donnée utilisateur transmise |

---

## 3. Droits des personnes

| Droit | État | Où |
|---|---|---|
| **Effacement** (art. 17) | ✅ Implémenté | `app/controllers/users/registrations_controller.rb` — vérification du mot de passe (ou case à cocher OAuth), transfert de capitanat, annulation des matchs futurs, `SecurityLog.log("account_deletion")`, mail de confirmation (`AccountDeletionMailer`), puis `user.destroy!` avec `dependent: :destroy` sur 18 associations |
| **Rectification** (art. 16) | ✅ Implémenté | Édition du profil (`profils_controller#update`) |
| **Accès / portabilité** (art. 15 & 20) | ❌ Manquant | Backlog P3 — export JSON des données du compte |
| **Opposition / limitation** | ⚠️ Partiel | Désactivation des notifications possible ; pas de mécanisme formel d'opposition |
| **Notification de violation** (art. 33) | 📋 Procédure | CNIL sous 72 h ; information des personnes si risque élevé |

---

## 4. Mesures de sécurité en place (art. 32)

- **Transport** : `force_ssl` + `assume_ssl` en production (cookies `Secure`), `config.hosts` restreint
- **Authentification** : Devise (`confirmable`, `reconfirmable`), bcrypt `stretches = 12`, mot de passe avec exigence de complexité (majuscule + chiffre + symbole), `reset_password_within = 6.hours`, `config.paranoid = true` (pas d'énumération de comptes), hCaptcha sur les formulaires d'auth
- **Autorisation** : Pundit avec `verify_authorized` + `verify_policy_scoped` globaux (`ApplicationController`), 18 policies ; back-office derrière `require_admin!` avec journalisation `admin_access`
- **Anti-abus** : Rack::Attack (login, inscription, reset, OAuth, création de match/équipe, recherche d'utilisateurs, Slack), déclenchements journalisés en `SecurityLog`
- **XSS** : CSP active (non report-only) ; aucune interpolation de donnée utilisateur dans `innerHTML` côté Stimulus
- **Identifiants publics** : les emails ne circulent plus dans les formulaires ni les réponses JSON — remplacés par des `signed_id` à `purpose` et durée de vie limitée
- **Journaux** : `filter_parameters` couvre les secrets **et** les champs personnels (voir §5)
- **Chaîne de build** : Brakeman, bundler-audit, `importmap audit`, `bin/pii-guard` en CI ; Dependabot hebdomadaire
- **Chiffrement au repos** : Active Record Encryption configuré (`config/initializers/active_record_encryption.rb`), utilisé pour `slack_workspaces.bot_token`

### 5. Décisions de journalisation

`config/initializers/filter_parameter_logging.rb` filtre les secrets (mots de passe, tokens,
captcha, code OAuth) **et** les champs personnels (`phone`, `first_name`, `last_name`, `nom`,
`prenom`, `address`, `localisation`, `latitude`, `longitude`, secrets Web Push).

**Décision assumée** : les contenus rédigés (messages du tchat, `content`, `body`) ne sont
**pas** filtrés — le débogage des flux ActionCable en deviendrait impraticable. Le niveau de
log en production est `info`, ces paramètres n'y apparaissent donc pas en temps normal.
À revoir si le niveau de log est passé à `debug` en production.

---

## 6. Backlog priorisé

### P0 — corrigé
- [x] **XSS stocké** dans l'autocomplete d'invitation (`invite_search_controller.js`) : prénom/nom interpolés dans `innerHTML`
- [x] **Énumération d'emails** via `/search` (`ILIKE` sur `users.email` + email renvoyé en JSON)
- [x] **Email d'un tiers exposé** dans le HTML d'un profil public (`profils/_profil_teams.html.erb`)

### P1 — corrigé
- [x] `filter_parameters` étendu aux champs personnels
- [x] Devise `config.paranoid = true`
- [x] Rétention des `security_logs` : 12 mois, `rake security_logs:purge`

### P2 — à faire
- [ ] Devise `lockable` (module + migration `failed_attempts` / `unlock_token` / `locked_at`) : Rack::Attack limite par IP, pas la cible d'un credential stuffing distribué
- [ ] Chiffrement de `profils.phone` et `profils.address` (`encrypts`) + tâche rake de migration des lignes existantes
- [ ] Anonymisation (plutôt que conservation à l'identique) des `messages` et `avis` à la suppression d'un compte
- [ ] Planifier `rake security_logs:purge` côté hébergeur (la tâche existe, le cron reste à brancher)

### P3 — backlog
- [ ] Export RGPD des données du compte (art. 15 & 20)
- [ ] CSP : `frame-ancestors`, `base-uri`, `form-action` ; en-têtes `Referrer-Policy` et `Permissions-Policy`
- [ ] CSP : supprimer `unsafe_inline` de `script_src` / `style_src` (passage aux nonces)
- [ ] Cloudinary en `type: authenticated` + `config.active_storage.urls_expire_in` (aujourd'hui les URLs d'assets sont permanentes)
- [ ] Purge des `contact_messages` traités (12 mois) et des comptes jamais confirmés (12 mois)
