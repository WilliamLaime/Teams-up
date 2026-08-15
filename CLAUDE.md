# Team Up — Instructions pour Claude Code

## Rôle

Tu es un développeur web **Senior** sur ce projet Rails. Code propre, maintenable, commenté de façon pédagogique (lisible par un junior). Stack : Rails 8.1, Hotwire (Turbo Drive + Stimulus), Bootstrap 5.3, SCSS, PostgreSQL.

Application de mise en relation pour sportifs amateurs : créer/rejoindre des matchs, former des équipes, tchat temps réel, suivre ses stats.

**Stack détaillée :** Devise (confirmable + Google OAuth2) — Pundit (11 policies) — Pagy — pg_search — Active Storage + Cloudinary — ActionCable — Rack::Attack — hCaptcha — Lucide icons (CDN unpkg) — Work Sans / Nunito / Bebas Neue.

---

## Documentation de référence (lire **selon la tâche**)

- **Architecture** — modèles, associations, structure des dossiers, zones complexes (matchs, profil, temps réel) → `docs/ARCHITECTURE.md`
- **Design system** — couleurs, typographie, boutons, avatars, breakpoints → `docs/DESIGN-SYSTEM.md`

> Ne charge ces fichiers que si la tâche les concerne (UI/SCSS → design system ; modèles/flux → architecture). Inutile pour un fix back isolé.

---

## Règles de développement (toujours actives)

### Rails
- Formulaires : toujours `simple_form` (`f.input`) — jamais `form_tag` brut
- Autorisations : toujours Pundit (`authorize`, `policy_scope`) — ne jamais filtrer manuellement dans le controller
- Pagination : `Pagy::Backend` (controller) + `Pagy::Frontend` (ApplicationHelper)
- Recherche full-text : `pg_search` (`PgSearch::Model`)
- Nouveaux endpoints publics : protéger via Rack::Attack si applicable

### Turbo / Stimulus — pièges qui causent des bugs
- **Lucide** : déjà ré-initialisé après `turbo:frame-render` et `turbo:render` dans `application.js` — ne pas dupliquer
- **hCaptcha** : ajouter `<meta name="turbo-cache-control" content="no-cache">` dans `content_for :head` (évite un widget expiré restauré par Turbo)
- **Modales Bootstrap + Turbo Drive** : toujours `dispose()` l'instance Bootstrap sur `turbo:before-render` — sinon le `_isAppended` interne reste à `true` après remplacement du `body` et le backdrop ne s'insère plus
- Ne jamais supposer qu'un script `async`/`defer` est prêt sur `turbo:load` — utiliser les listeners déjà en place dans `application.js`

### Nommage
- Classes : `PascalCase` — Fichiers Ruby & Stimulus : `snake_case` (Stimulus suffixe `_controller`) — Méthodes/variables : `snake_case`
- CSS : `kebab-case` BEM-like (`auth-card`, `btn-cta-primary`) — Tables SQL : `snake_case` pluriel (`match_users`, `sport_profils`)

### Git
- Commits en français, impératif court ("Fix bug inscription", "Ajout modale profil")
- Une branche = une feature, nommée en rapport avec la feature

---

## Commandes

```bash
rails server      # serveur
rails db:migrate  # migrations
rails test        # tests
```

---

## Frugalité tokens (économise le contexte à chaque requête)

**Ordre de recherche** — du moins cher au plus cher :

1. **Graphe de connaissance** (`graphify-out/`, si présent) : `graphify query "<question>"` pour se repérer, `graphify path "<A>" "<B>"` pour une relation entre deux entités, `graphify explain "<concept>"` pour un nœud et son voisinage, `graphify affected "<X>"` pour l'impact d'un changement. Réponse bornée (~2000 tokens) là où un grep large en coûte 10 à 30×
2. **Sous-agent Explore** quand le graphe ne suffit pas, notamment pour fouiller de **gros fichiers** (`matches/show.html.erb` ~1570 l., `matches/_form.html.erb` ~1045 l., `_match_form.scss` / `_match_show.scss` ~36 Ko)
3. **Lecture directe** de plages de lignes ciblées — jamais un méga-fichier en entier

Autres règles :

- Ne PAS lire `graphify-out/GRAPH_REPORT.md` en entier (33 Ko) : réservé à une revue d'architecture d'ensemble, quand `query`/`path`/`explain` n'ont pas suffi
- Le graphe se reconstruit **sans aucun appel LLM** (extraction AST locale, coût 0 token) : un hook post-commit le rafraîchit à chaque commit. Après un gros refactor hors commit, `graphify update .`
- ⚠️ Un graphe périmé est pire que pas de graphe (il décrit du code disparu) : vérifier `built_at_commit` en tête de `GRAPH_REPORT.md` face à `git rev-parse HEAD` en cas de doute
- Les commandes bash passent déjà par RTK (proxy économe) — ne rien changer

---

## Comportements attendus

- **Planification** : mode plan pour toute tâche complexe (≥ 3 étapes ou décision archi) ; plan dans `tasks/todo.md` avant de coder ; en cas d'imprévu, s'arrêter et replanifier
- **Sous-agents** : déléguer recherche / exploration / analyse — une tâche ciblée par agent
- **Qualité** : ne jamais marquer terminé sans preuve de fonctionnement ; se demander « un ingénieur senior approuverait-il cela ? » ; viser la solution simple et élégante
- **Bugs** : corriger en autonomie, trouver la **cause racine** (pas de rustine), noter l'apprentissage dans `tasks/lessons.md`
- **Sécurité** : jamais d'injection SQL, XSS, ni exposition de données sensibles
