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

**Choisir l'outil selon la question** — pas de « graphe d'abord » systématique, les mesures
sur ce dépôt (15 août 2026) ne le justifient pas :

| Question | Outil | Pourquoi |
|---|---|---|
| Fichier déjà connu / chaîne précise à trouver | **`grep` ciblé** | `grep -rn 'state: "qualified"' app/` = ~95 tokens et réponse complète, contre ~500 et une réponse incomplète via le graphe. Le graphe est un détour ici |
| « Qui appelle vraiment X ? », « qu'est-ce qui casse si je change X ? » | **`graphify affected "<X>"`** | ⭐ le vrai gain : sur `TournamentStandings`, 1 appelant réel contre 10 résultats grep dont **8 en commentaire**. Le graphe est bâti sur l'AST, il ne confond pas « appelle X » et « parle de X » — décisif dans un dépôt aussi commenté que celui-ci |
| « Que fait ce service, avec quoi est-il lié ? » | **`graphify explain "<Classe>"`** | 43 relations avec `fichier:ligne` en ~500 tokens, contre ~5 800 pour ouvrir `criterium_flow.rb` (23 Ko) |
| Relation entre deux entités nommées | **`graphify path "<A>" "<B>"`** | |
| Question floue en langage naturel | **`graphify query`, en dernier recours** | ⚠️ le plus faible ici : la recherche est captée par les titres markdown de `docs/TOURNOI.md` et `tasks/`, et retourne des sections de doc plutôt que du code |

`explain` et `affected` attendent un **nom d'entité** (`CriteriumFlow`, `TournamentUser`) —
c'est ce qui les rend fiables. Si le nom de l'entité est encore inconnu, le trouver d'abord
(`graphify god-nodes`, ou un grep étroit) plutôt que de tenter `query`.

Quand le graphe ne suffit pas :

1. **Sous-agent Explore** pour fouiller de **gros fichiers** (`matches/show.html.erb` ~1570 l., `matches/_form.html.erb` ~1045 l., `_match_form.scss` / `_match_show.scss` ~36 Ko)
2. **Lecture directe** de plages de lignes ciblées — jamais un méga-fichier en entier

Autres règles :

- Ne PAS lire `graphify-out/GRAPH_REPORT.md` en entier (33 Ko) : réservé à une revue d'architecture d'ensemble, quand `explain`/`affected` n'ont pas suffi
- Le graphe ne couvre PAS tout : il a raté une écriture d'état dans `league_builder.rb` que le grep ciblé trouvait. Ne jamais conclure « ça n'existe pas » sur la seule foi du graphe
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
