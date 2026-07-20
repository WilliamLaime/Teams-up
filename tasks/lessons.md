# Leçons — erreurs à ne pas répéter

> Après chaque correction de bug, ajouter ici une entrée courte : **symptôme → cause racine → correctif**.
> Objectif : ne pas répéter la même erreur deux fois.

<!-- Exemple de format :
## YYYY-MM-DD — Titre court du bug
- **Symptôme** : ce qui était cassé / observé
- **Cause racine** : la vraie cause (pas le symptôme)
- **Correctif** : ce qui a été changé, et fichier(s) concerné(s)
-->

## 2026-07-16 — Inscription : mot de passe + captcha perdus quand un sport manque
- **Symptôme** : à l'inscription classique, un utilisateur remplit mdp + captcha mais oublie le sport ; à la soumission, erreur serveur sur le sport ET perte du mot de passe et du captcha (widget vierge) → l'utilisateur doit tout ressaisir.
- **Cause racine** : la validation client du sport (`data-action="submit->sport-select#validate"`) était posée sur le `<form>`, mais le `data-controller="sport-select"` était sur le `<div id="sport-field">`, un **descendant** du form. Une action Stimulus ne résout son controller que sur l'élément lui-même ou un **ancêtre**, jamais un descendant → `validate` ne se déclenchait jamais, le form partait au serveur, qui fait `clean_up_passwords` + régénère un hCaptcha vierge (token à usage unique, non restaurable).
- **Correctif** : déplacer `data-controller="sport-select"` du `<div id="sport-field">` vers le `<form>` (`app/views/devise/registrations/new.html.erb`). L'action `submit->sport-select#validate` trouve alors son controller, bloque la soumission côté client, la page ne recharge pas → mdp + captcha préservés. (La validation du genre marchait déjà car posée en `addEventListener('submit')` directement sur le form.)
- **Leçon** : en Stimulus, `data-action` et `data-controller` doivent être sur le même élément **ou** le controller sur un ancêtre de l'élément portant l'action — un controller sur un descendant est invisible. Pour un `submit`, mettre le controller sur le `<form>`. Corollaire UX : ce qui est vérifiable côté client (sport, genre) doit l'être, car un aller-retour serveur détruit toujours le mdp (jamais renvoyé en HTML) et le captcha (token usage unique).

## 2026-07-10 — Abandon (withdrawn) « annulé » à la ronde suivante (Lot 5 tournoi)
- **Symptôme** : en ronde suisse, un joueur déclaré forfait était **ré-apparié** à la ronde suivante alors qu'il devait être exclu (test `withdraw_player_test` : l'id du retiré réapparaissait dans les matchs de la ronde 2).
- **Cause racine** : le moteur suisse appelle `recompute_stats_for("swiss", apply_state: true)` à chaque `next_round!`, qui **réécrasait `state`** via `state_for(wins, losses)` → l'état terminal `withdrawn` repassait en `active`/`eliminated`. Or `SwissPairing#create_swiss_round!` apparie `player_scope.active` : le joueur, redevenu `active`, rentrait dans le tirage.
- **Correctif** : dans `RoundRobinStats#recompute_stats_for`, ne jamais recalculer un état terminal — `attrs[:state] = state_for(...) if apply_state && !tu.withdrawn?`. (`app/services/round_robin_stats.rb`)
- **Leçon** : un recompute déterministe qui régénère un champ d'état doit **préserver les états terminaux** (withdrawn, disqualifié…). Toujours exclure ces états du recalcul, sinon une action « one-shot » (abandon) est silencieusement défaite par le prochain passage du moteur.

## 2026-07-02 — Conversation qui disparaît parfois de la sidebar de chat
- **Symptôme** : une conversation (match/équipe/privée) disparaissait « parfois » de la sidebar du chat sticky et ne revenait qu'après un rechargement complet (F5).
- **Cause racine** : `Message#broadcast_unread_notifications` remontait la conv en tête via DEUX broadcasts ActionCable séparés (`broadcast_remove_to` puis `broadcast_prepend_to`). Si le rendu du partial du prepend échouait entre les deux, le `remove` était déjà parti → item supprimé. Comme `#sticky-chat-global` est `data-turbo-permanent`, la sidebar n'est jamais régénérée en navigation Turbo, d'où la persistance jusqu'au F5. Bug annexe : le broadcast match itérait TOUS les `match_users` (y compris pending/waiting/rejected), divergeant du filtre d'affichage `status='approved' OR role='organisateur'` → items fantômes.
- **Correctif** : nouveau partial `shared/_conversation_bump.turbo_stream.erb` qui groupe remove + prepend dans UN SEUL frame (rendu d'abord, diffusé ensuite → si le rendu échoue, rien n'est diffusé, l'item reste). `message.rb` refactorisé pour l'utiliser (`broadcast_conversation_bump`) et scope match aligné sur le filtre d'affichage.
- **Leçon** : ne jamais émettre remove + insertion d'un même élément en deux broadcasts distincts ; grouper dans un seul frame Turbo Stream. Garder la logique de broadcast alignée sur le filtre d'affichage de la vue.

## Niveaux absents à la création de match (mode multisport)
- **Symptôme** : le champ « Niveau requis » de `/matches/new` reste vide (aucun bouton), signalé en prod après la refonte du filtre multi-sport.
- **Cause racine** : `matches#new` faisait `@match.sport = current_sport`. En mode multisport (« Tous les sports »), `current_sport` renvoie `nil` → aucun sport présélectionné → au chargement, `match_form_controller#updateSport` tombe dans le `else` (guard `if (levelsMap[sportId])`) et ne génère ni boutons de niveau ni formats. La refonte du filtre (#342) a juste rendu le mode multisport bien plus facile à activer → le bug est devenu visible.
- **Correctif** : `@match.sport = current_sport || Sport.order(:name).first` (un match exige toujours un sport ; même fallback que le filtre de l'index `default_sport`).
- **Leçon** : quand un rendu JS dépend d'un champ présélectionné côté serveur, prévoir un fallback si la valeur peut être `nil`. Toujours reproduire avant de conclure : ici tout le code JS/data était correct, seul l'état « aucun sport actif » cassait le rendu.
- **Annexe** : les fixtures `matches.yml`/`teams.yml` n'avaient pas de `slug` (colonne NOT NULL + unique ajoutée par une migration récente) → toute la suite `matches_controller_test` plantait au chargement des fixtures. Les fixtures court-circuitent les callbacks du modèle qui génèrent le slug : renseigner un `slug` explicite.

## 2026-07-03 — "Il manque encore 17 places" alors que 2 joueurs ont rejoint
- **Symptôme** : sur la show d'un match, un match cherchant 17 joueurs affichait toujours « 17 places libres » après que 2 joueurs eurent rejoint (attendu : 15).
- **Cause racine** : `matches.player_left` (places restantes) était un **compteur stocké muté à la main** (`decrement!`/`increment!`) éparpillé dans `match_users_controller`. Plusieurs chemins ne le mettaient jamais à jour (notamment `confirm` d'un membre d'équipe pending→approved, et toute désync). Résultat : dérive permanente du compteur.
- **Correctif** : `player_left` devient une valeur **dérivée et self-healing**. Nouvelle colonne immuable `matches.players_needed` (capacité cible). `player_left = max(players_needed − confirmés_hors_organisateur, 0)`, recalculé par un **callback centralisé unique** sur `MatchUser` (`after_save if saved_change_to_status?` + `after_destroy`) → couvre tous les chemins. Suppression des `decrement!`/`increment!` manuels. Migration backfill (`player_left + approved` → `players_needed`, puis resync). Le formulaire soumet désormais `players_needed`. Fichiers : `app/models/match.rb`, `app/models/match_user.rb`, `app/controllers/match_users_controller.rb`, `app/views/matches/_form.html.erb`, migration `add_players_needed_to_matches`.
- **Leçon** : un compteur dénormalisé muté à la main dérive dès qu'un chemin oublie de le mettre à jour. Préférer le dériver d'une source de vérité (COUNT) via un callback centralisé, tout en gardant la colonne pour ne pas réécrire les filtres SQL (`where("player_left > 0")`).

## 2026-07-03 — Broadcast Turbo Stream des places qui ne partait jamais
- **Symptôme** : le bloc « places » (ratio X/Y + places libres) était bien abonné (`turbo_stream_from @match`) et `Match#broadcast_spots` fonctionnait en console, mais aucun message n'arrivait jamais aux visiteurs après un join/refus/départ.
- **Cause racine** : **piège de déduplication des callbacks ActiveSupport**. Enregistrer le MÊME symbole de méthode pour plusieurs hooks — `after_create_commit :broadcast_match_spots` + `after_update_commit :broadcast_match_spots` + `after_destroy_commit :broadcast_match_spots` — fait qu'ActiveSupport les fusionne en UNE seule entrée aux conditions `on:` conflictuelles (create ∧ update ∧ destroy = jamais) → le callback ne se déclenche JAMAIS. Confirmé via `MatchUser._commit_callbacks` (une seule entrée) et des traces runner (la méthode n'était jamais appelée sur create ni update).
- **Correctif** : remplacer les trois inscriptions par un unique `after_commit :broadcast_match_spots` (couvre create + update + destroy en une seule inscription, sans collision). Re-diffuser un bloc identique est idempotent (Turbo remplace la même cible). Fichier : `app/models/match_user.rb`. Testé bout-en-bout via client WebSocket : join → `2/6` devient `3/6`, `4 places libres` devient `3` en ~1 s.
- **Leçon** : ne jamais enregistrer le même symbole de méthode pour `after_create_commit`/`after_update_commit`/`after_destroy_commit` — utiliser un seul `after_commit`, OU des noms de méthode distincts. (Le macro `broadcasts` de turbo-rails évite le piège car il utilise des méthodes différentes : prepend/replace/remove.)
- **Annexe (bug latent préexistant, NON corrigé)** : `MatchUser#broadcast_new_convo_to_sidebar` (ajout temps réel de la conv dans la sidebar sticky) souffre du même piège — `after_create_commit` + `after_update_commit` sur le même symbole → probablement jamais déclenché lui aussi. À investiguer/corriger séparément.

## 2026-07-03 — Le chat sticky ne se ferme pas au clic sur un profil depuis une bulle
- **Symptôme** : depuis le sticky chat (modale Bootstrap), cliquer sur l'avatar d'un expéditeur pour voir son profil naviguait bien vers le profil, mais le panneau de chat restait affiché — il fallait recharger la page pour le faire disparaître.
- **Cause racine** : le sticky chat est une modale Bootstrap dans un conteneur `data-turbo-permanent` (`#sticky-chat-global`, voulu pour préserver les abonnements ActionCable). L'en-tête du chat fermait proprement la modale avant de naviguer via `sticky-chat#goToProfile` (hide → `hidden.bs.modal` → navigation). Mais l'avatar de CHAQUE bulle (`app/views/messages/_message.html.erb`) utilisait un simple `link_to ... data-turbo-frame="_top"` qui **court-circuitait** ce mécanisme : la navigation Turbo laissait le conteneur permanent intact → la modale gardait sa classe `.show` → chat toujours visible jusqu'au F5.
- **Correctif** : câbler l'avatar sur le même `goToProfile` que l'en-tête. Dans `_message.html.erb`, ajout de `data-action="click->sticky-chat#goToProfile"` + `data-url` + `data-turbo="false"` (au lieu de `turbo_frame:_top`). Le `data-turbo="false"` est crucial : sans lui, Turbo intercepte le clic et lance une visite Turbo → `turbo:before-render` → `dispose()` de la modale en pleine fermeture → **backdrop orphelin collé** (bug Bootstrap+Turbo). Ajout aussi de `event.preventDefault()` en tête de `goToProfile` (inoffensif sur le `<span>` de l'en-tête). Vérifié en navigateur réel (Selenium) : avant fix `chat show=true` après navigation ❌, après fix `chat show=false display=none` ✅.
- **Leçon** : dans un conteneur `data-turbo-permanent`, une modale Bootstrap survit aux visites Turbo. Tout lien interne au chat doit fermer explicitement la modale AVANT de naviguer, et être en `data-turbo="false"` pour éviter la course avec `turbo:before-render`/`dispose()` qui laisse un backdrop collé. Centraliser via une seule action Stimulus (`goToProfile`) plutôt que dupliquer la logique de fermeture.
- **Annexe (préexistant, NON corrigé)** : une modale PWA (`.pwa-modal-content`) laisse un `.modal-backdrop fade show` + `body.modal-open` collés après affichage (observé en Chrome headless sur toutes les pages). Absent du HTML serveur (créé par JS) → à investiguer séparément (même famille de bug backdrop Bootstrap+Turbo).

## 2026-07-03 — Compteur de places du match affichait "1/15" au lieu de "4/18"
- **Symptôme** : sur la show d'un match Libre, le bloc blanc affichait "1/15" alors que 4 joueurs (organisateur + 3 approuvés) étaient présents et que le total visé était 18.
- **Cause racine** : dans `matches/_spots.html.erb`, un cas spécial pour le format Libre affichait le champ statique `players_present` ("Déjà confirmés", saisi à la création = 1) comme numérateur, et `players_present + player_left` comme total. Ce champ ne reflète PAS le nombre vivant de joueurs acceptés. La branche générale (`secured_players_count` / `secured + player_left`) était déjà correcte.
- **Correctif** : suppression du cas spécial Libre. Le bloc utilise désormais toujours `secured_players_count` (organisateur + acceptés + joueurs sur place) comme X, et `X + player_left` comme total Y. Comme chaque acceptation fait X +1 et player_left −1, Y reste constant et places libres = player_left = Y − X. Numérateur désormais identique au "Joueurs inscrits (N)" de la colonne de gauche. Fichier : `app/views/matches/_spots.html.erb`.

## 2026-07-03 — Procédure : ajouter un nouveau sport (mémo réutilisable)
Un sport est **piloté par la base** (table `sports` : `name`, `icon`, `slug`) mais plusieurs comportements sont **hardcodés par `slug`/`name`** dans le code. Sans ces branches, le sport « marche » mais retombe sur des fallbacks (format Libre seul, niveaux génériques, images football, bannière tennis). Aucun i18n à toucher (les noms viennent de la colonne `name`). Aucun SCSS par sport. Exemple concret réalisé : **Ping-Pong** (slug `ping-pong`, icône 🏓, formats 1v1/2v2/Libre, 4 images).

**Checklist (dans l'ordre) :**
1. **Seed — `db/seeds.rb`** (tableau `sports_data`) : ajouter `{ name: "Ping-Pong", icon: "🏓", slug: "ping-pong" }`. L'`icon` peut être un emoji OU une URL d'image (Cloudinary) — le helper `sport_icon` détecte l'extension. Idempotent via `find_or_create_by!(slug:)`. Puis `bin/rails db:seed` (ou `Sport.find_or_create_by!` en runner).
2. **Formats — `app/models/sport.rb` `available_formats`** : ajouter un `when "<slug>"`. `players` = joueurs MANQUANTS (l'organisateur est déjà compté ; 1v1 → `players: 1`, 2v2 → `players: 3`). `players: nil` = format Libre. Sans branche → `else` = « Libre » uniquement.
3. **Niveaux — `app/models/sport.rb` `available_levels`** (optionnel) : sans branche → fallback 3 niveaux (Débutant/Intermédiaire/Avancé). Pour une grille officielle (comme tennis/padel/badminton), ajouter un `when` avec `{ label:, ref:, desc: }`, PUIS ajouter le slug aux deux listes `%w[padel tennis badminton]` de `app/views/matches/show.html.erb` (bouton « ? ») et `app/views/shared/_level_grid_modal.html.erb` (modale des grilles).
4. **Images de couverture (cartes/pages match) — `app/helpers/sport_images_helper.rb` `SPORT_IMAGES`** : ajouter `"<slug>" => %w[ ...URLs Cloudinary... ]`. Sans clé → fallback football. La rotation est déterministe : `images[match.id % images.length]` (même match → même image), pas vraiment aléatoire.
   - **Workflow images → Cloudinary** : déposer les sources dans `app/assets/images/sports/<Dossier>/` ; convertir en webp optimisé (`cwebp -q 80 -resize 1200 0 in.jpg -o out.webp`) ; ajouter la ligne `"<slug>" => Dir[BASE_DIR.join("<Dossier>/*.webp")].sort` dans `lib/tasks/upload_sports_to_cloudinary.rb` (`SPORT_FILES`) ; uploader via runner Cloudinary (`Cloudinary::Uploader.upload(f, public_id: "sports/<slug>/#{name}", overwrite: false)`) ; coller les `secure_url` retournées dans `SPORT_IMAGES`. Cloudinary est déjà configuré (cloud `dfw8rlluc`, via `CLOUDINARY_URL`).
5. **Bannière hero de la home — `app/views/pages/home.html.erb`** (`case current_sport&.name`, sur le **name** pas le slug !) : ajouter `when "Ping-Pong"` pointant vers un asset LOCAL `app/assets/images/img banner/banner_<sport>.jpeg` (créé ex : `magick src.webp -resize 900x600^ -gravity center -extent 900x600 -quality 82 banner_x.jpeg`). Sans branche → bannière tennis par défaut.
6. **Vérifs** : runner `Sport.find_by(slug:).available_formats` ; `curl -o /dev/null -w "%{http_code}"` sur chaque URL Cloudinary (doit être 200).

**Pièges** : `home.html.erb` switche sur `name` (les autres endroits sur `slug`) ; le dossier `app/assets/images/sports/` est vide en local (images uniquement sur Cloudinary) ; le `cd` persiste entre appels Bash (utiliser des chemins absolus pour `bin/rails`).

## Sports absents en prod (Railway) alors que présents en dev

**Cause racine** : un nouveau sport n'est ajouté que dans `db/seeds.rb`, mais l'entrypoint Docker (`bin/docker-entrypoint`) ne joue **jamais** `db:seed` en déploiement — seulement `db:prepare` (migrations) + `db:seed_custom_venues`. Donc le sport n'existe pas dans la base Railway. Ce n'est **pas** un problème de migration (un ajout de sport n'en crée aucune).

**Fix durable (en place)** : liste des sports extraite dans `db/sports.rb` (constante `SPORTS` + méthode idempotente `seed_sports`, même pattern que `db/custom_venues.rb`). Chargée par `db/seeds.rb` **et** par la tâche `rails db:seed_sports`, elle-même appelée dans `bin/docker-entrypoint`. Tout nouveau sport remonte désormais automatiquement à chaque déploiement.
## CI `scan_ruby` rouge : `--ensure-latest` de Brakeman masquait `bundler-audit`

**Symptôme** : `scan_ruby` échouait sur `master` depuis plusieurs merges (#348→#350), qu'on attribuait aux 2 warnings XSS `badge_svg`.

**Cause racine réelle** (log CI, pas les warnings) : le binstub `bin/brakeman` (généré par Rails 8) contient `ARGV.unshift("--ensure-latest")`. Ce flag fait sortir Brakeman en **exit 5** dès qu'une version plus récente existe sur RubyGems (« Brakeman 8.0.4 is not the latest version 8.0.5 »), **avant** d'analyser. Résultat non déterministe : la CI casse à chaque release de Brakeman, sans rapport avec le code.

**Effet masquant** : le step CI `scan_ruby` enchaîne `bin/brakeman` **puis** `bin/bundler-audit`. Comme Brakeman échouait en premier, `bundler-audit` **ne tournait jamais** — il masquait une longue liste de CVE réelles dans les gems verrouillées (puma, oauth2, jwt, faraday, addressable, nokogiri, net-imap…). Corriger Brakeman a démasqué cette 2ᵉ dette.

**Corrections** :
1. Retirer `--ensure-latest` de `bin/brakeman` (CI déterministe ; version figée par Gemfile.lock, bumpée via Dependabot/bundle).
2. Warnings `badge_svg` = **vrais faux positifs** : le SVG est input utilisateur (champ caché mass-assigné) mais assaini serveur par `Team#sanitize_badge_svg` (before_save, `Rails::Html::SafeListSanitizer` + allow-list). Ajoutés à `config/brakeman.ignore` avec note exacte.
3. Vulns gems = **PAS des faux positifs** → mise à jour des gems (jamais d'ignore dans `bundler-audit.yml`).

**Pièges** :
- `bin/brakeman` prend un `--ensure-latest` qui couple le CI au calendrier de release amont.
- Un step CI qui enchaîne 2 commandes masque la 2ᵉ tant que la 1ʳᵉ échoue — regarder le **log réel** (`gh run view --job <id> --log`), pas juste le nom du job.
- `bundle update` était bloqué par `gem "simple_form", github:` (hérité du template le wagon) : re-résolution KO sur `activemodel`. Repointer sur la gem publiée (`~> 5.4`, version identique) débloque.
- Vérifier `bundler-audit` en local exige une base d'avis à jour : `bundle exec bundler-audit update`.

---

## Statut live de la carte match Slack (chat.update)

**Besoin** : la carte Slack d'un match doit afficher un tag « À venir / En cours / Terminé » et se mettre à jour en direct.

**Contrainte clé** : un message Slack posté est **figé**. Pour le faire évoluer il faut mémoriser son `channel` + `ts` (table `slack_match_messages`) et le ré-éditer via `chat.update`. On planifie 2 rafraîchissements à la création (`SlackMatchStatusJob.set(wait_until:)`) : à l'heure de début (→ En cours) et à l'heure de fin (→ Terminé), transitions futures uniquement.

**Choix** :
- Statut basé sur `build_datetime` / `end_datetime` (horaires réels), PAS sur l'heuristique `+1h` de `in_progress?`/`completed?`.
- Bouton « S'inscrire au match » retiré dès que le match n'est plus `:upcoming`.
- Skip « match passé » du `SlackNotifyJob` **retiré** : on poste désormais avec le bon tag.
- `SlackMatchStatusJob` idempotent (reconstruit les blocs au statut du moment) → un déclenchement en retard reste correct. Purge la trace sur `message_not_found`/`cant_update_message`.

**Édition d'horaire gérée** : `Match#after_update_commit :resync_slack_messages` (si `date`/`time`/`end_time` change ET cartes suivies) → rafraîchit les cartes immédiatement (nouveau « Quand ») + `SlackMatchStatusJob.schedule_transitions` rebranche les bascules aux nouveaux horaires. Les anciens jobs planifiés restent inoffensifs (statut recalculé à T par un job idempotent).

**Piège CSS** : `.btn-cta-primary` ne fournit QUE `border-radius` + `:hover` ; le fond vert vient de Bootstrap `.btn-primary`. Un bouton `btn btn-sm btn-cta-primary` (sans `btn-primary`) est donc transparent → invisible sur fond sombre. Toujours coupler `btn-primary btn-cta-primary` (cf bouton « Connecter Slack » du profil).

## 2026-07-20 — Panne Slack transitoire masquée (dropdown de destinations vide)

**Symptôme** : plus aucun channel dans le modal « Partager sur Slack » (seul « Ma destination par défaut » restait), un matin sans déploiement.

**Cause racine** : incident réseau/Slack **transitoire** (`conversations.list`/`users.list` en échec quelques minutes). `Slack::ChannelLister.destinations` avait un `rescue StandardError` global qui renvoyait `{}` **en silence** → dropdown vide sans aucune explication. Le cache **Turbo Drive** figeait ensuite le HTML (destinations vides embarquées dans `data-slack-share-data-value`) → le vide persistait à la navigation même après rétablissement de Slack. Un **hard refresh** (Cmd+Shift+R) suffisait à récupérer les channels.

**Diagnostic** : `railway run bin/rails runner` + un script bouclant sur `SlackWorkspace.find_each` (PAS `.first` : il y a 2 workspaces, Test + CACD2) → `auth.test` / `conversations.list` / `users.list` par workspace. Tout OK au moment du diagnostic = panne passagère confirmée.

**Correctifs** : (1) `ChannelLister` isole chaque appel (`safe_fetch`) — une erreur sur `users.list` ne fait plus disparaître les channels ; (2) `resolve` renvoie `auth_failed` (erreurs FATALES `invalid_auth`/`token_revoked`/`account_inactive` + bot_token illisible) ; (3) bandeau « réinstalle l'app » dans le modal de partage + page Intégrations quand `auth_failed` → oriente vers `/slack/install` (réinstaller), PAS `/slack/connect` (relier une identité ne régénère aucun bot_token).

**Leçon** : ne jamais avaler une erreur d'API externe en `{}` silencieux dans du contenu mis en cache par Turbo — soit dégrader avec un signal visible (bandeau), soit `turbo-cache-control no-cache` sur les vues dépendant d'un état externe volatil.
