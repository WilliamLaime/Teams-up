# Teams-up — Design System

> Référence consultée **à la demande** pour les tâches UI / SCSS.
> Source : `app/assets/stylesheets/config/`.

## Couleurs — `config/_colors.scss`

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
