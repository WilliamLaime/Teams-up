# Teams-up — Design System

> Référence consultée **à la demande** pour les tâches UI / SCSS.
> Source : `app/assets/stylesheets/config/`.

## Couleurs — `config/_colors.scss`

| Variable | Valeur | Usage |
|---|---|---|
| `$green` | `#1EDD88` | Primaire — **mode sombre** (voir § Thèmes) |
| `$green-light` | `#00A44A` | Primaire — **mode clair** |
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

Bootstrap overrides dans `config/_bootstrap_variables.scss` : `$primary` → `$green`, `$success` → `$green`, `$danger` → `$red`, `$warning` → `$orange`, `$info` → `$yellow`, `$body-bg` → `$light-gray`, `$body-color` → `$gray`.

## Thèmes clair / sombre

L'app est **dark-first**. Le thème est porté par l'attribut `data-theme` sur `<html>`,
posé côté serveur dans `layouts/application.html.erb` (préférence en BDD si connecté,
`localStorage` sinon) pour éviter le flash au chargement, puis basculé au runtime par
`theme_toggle_controller.js`. La préférence OS (`prefers-color-scheme`) est volontairement
ignorée pour les couleurs. `layouts/landing.html.erb` force `data-theme="dark"`.

Toutes les couleurs qui varient sont des **custom properties CSS**, redéfinies dans les deux
blocs `[data-theme="dark"]` / `[data-theme="light"]` de `config/_colors.scss` :

| Famille | Exemples | Rôle |
|---|---|---|
| `--theme-*` | `--theme-page-bg`, `--theme-bg-card`, `--theme-text-primary`, `--theme-border`, `--theme-input-bg` | fonds, textes, bordures, inputs |
| `--green*` | voir ci-dessous | le vert primaire et ses dérivées |

### Le vert primaire

⚠️ **Ne jamais écrire le vert en dur, ni via `$green`, dans un composant.** Une variable Sass
est résolue à la compilation : elle produit la même valeur dans les deux thèmes. Utiliser :

| Token | Sombre | Clair | Usage |
|---|---|---|---|
| `var(--green)` | `#1EDD88` | `#00A44A` | la couleur pleine |
| `rgba(var(--green-rgb), α)` | | | n'importe quelle transparence |
| `var(--green-d8 / -d10 / -d12)` | | | hovers et dégradés assombris |
| `var(--green-l10)` | | | variante éclaircie |
| `var(--green-readable)` | `#1EDD88` | `#007A37` | **texte** vert sur fond clair (`#00A44A` plafonne à ~3,2:1, insuffisant pour AA) |

Ces tokens sont générés par le mixin `green-tokens()` de `config/_colors.scss` — une seule
source de vérité pour les deux thèmes.

Deux endroits dérogent volontairement et gardent `$green` :

- `config/_bootstrap_variables.scss` — Bootstrap a besoin d'une vraie couleur Sass. Ses
  composants verts sont réalignés sur `var(--green)` en mode clair dans
  `components/_theme.scss` (§ BOOTSTRAP — VERT PRIMAIRE)
- `pages/_about.scss` et `pages/_about2.scss` — la page « Qui sommes-nous ? » est
  100 % sombre par design et ne suit pas le thème

Les **mailers** gardent le hex `#1EDD88` : un client mail ne résout pas `var()` et n'a pas de thème.

### Overrides mode clair

`components/_theme.scss` est importé **en tout dernier** dans `application.scss`, ce qui lui
donne la priorité de cascade sur tout le reste. C'est là que vivent les overrides `[data-theme="light"]`
qui ne peuvent pas passer par un token — notamment les composants Bootstrap, dont le bloc `:root`
est déclaré après `config/`.

## Typographie — `config/_fonts.scss`

| Variable | Police | Usage |
|---|---|---|
| `$body-font` | Work Sans | Corps du texte (`1rem`) |
| `$headers-font` | Nunito | Titres h1–h6 |
| `$display-font` | Bebas Neue | Titres hero / display |

Tailles courantes : nav `0.9rem/500`, labels `0.75rem/700/uppercase`, sous-texte `0.875rem`.

## Boutons — toujours utiliser les partials existants

```erb
<%= render 'shared/btn_primary' %>   → .btn-cta-primary  (fond $green, texte #111)
<%= render 'shared/btn_secondary' %> → .btn-cta-secondary (fond dark, bordure $green)
```

Classes Bootstrap associées : `btn btn-primary btn-lg px-4 btn-cta-primary` / `btn btn-lg px-4 btn-cta-secondary`.

## Avatars

| Usage | Taille |
|---|---|
| Standard / profil | `40px` |
| Page profil large | `56px` |
| Navbar | `34px` (border 2px blanc) |
| Match card empilés | `26px` (overlap `-6px`) |
| Chat preview | `30px` |

## Responsive

| Breakpoint | Largeur |
|---|---|
| Desktop | `≥ 992px` |
| Tablette | `< 992px` |
| Mobile | `< 768px` |
| Petit téléphone | `< 576px` |

## Organisation SCSS

| Dossier | Contenu |
|---|---|
| `config/` | Variables (`_colors`, `_fonts`, `_bootstrap_variables`) |
| `components/` | Un fichier SCSS par composant |
| `pages/` | Un fichier SCSS par page |
