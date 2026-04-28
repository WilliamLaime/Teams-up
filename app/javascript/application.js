// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import * as bootstrap from "bootstrap"

// Ré-initialise les icônes Lucide après chaque mise à jour d'un turbo_frame ou turbo:render
// (ex: le bouton ami se met à jour en live → les nouveaux <i data-lucide="..."> doivent être convertis en SVG)
// RGAA 4.8 — masquer tous les SVG Lucide des lecteurs d'écran avec aria-hidden=true
// Car les icônes décoratives ne doivent pas être annoncées aux utilisateurs de technologies d'assistance
document.addEventListener("turbo:frame-render", () => {
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// RGAA 4.8 — re-render Lucide après turbo:render (réponses 422, streams, etc.)
document.addEventListener("turbo:render", () => {
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// Initialise les tooltips Bootstrap sur chaque navigation Turbo
// Turbo remplace le DOM sans recharger la page — on doit donc ré-initialiser à chaque fois
document.addEventListener("turbo:load", () => {
  // Sélectionne tous les éléments avec l'attribut data-bs-toggle="tooltip"
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipElements.forEach(el => new bootstrap.Tooltip(el))

  // RGAA 4.8 — masquer les SVG Lucide au chargement initial
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// ── Gestion hcaptcha + Turbo Drive ──────────────────────────────────────────
//
// Problème : hcaptcha charge son script avec "async defer".
// Turbo Drive ne ré-exécute pas les scripts déjà chargés lors des navigations.
// Résultat : l'auto-render hcaptcha ne se déclenche pas → widget invisible sur mobile.
//
// Solution en 2 étapes :
//   1. Avant la mise en cache Turbo → vider le widget pour éviter qu'un token
//      expiré soit restauré depuis le snapshot (même si no-cache est activé)
//   2. Après chaque navigation Turbo → forcer le re-render manuellement

document.addEventListener("turbo:before-cache", () => {
  // Vide les widgets hcaptcha avant que Turbo prenne un snapshot de la page.
  // Sans ça, le snapshot contient un iframe avec un token invalide.
  document.querySelectorAll(".h-captcha").forEach(el => {
    el.innerHTML = ""
  })
})

// Fonction partagée : re-rend les widgets hcaptcha vides présents dans la page.
// Un widget déjà rendu contient un <iframe> — on ne re-rend que les divs vides
// pour éviter de créer des doublons.
function rerenderHcaptchaWidgets() {
  if (typeof hcaptcha === "undefined") return

  document.querySelectorAll(".h-captcha").forEach(el => {
    if (!el.querySelector("iframe")) {
      hcaptcha.render(el)
    }
  })
}

// turbo:load → navigation classique (lien, retour arrière, redirection)
document.addEventListener("turbo:load", rerenderHcaptchaWidgets)

// turbo:render → AUSSI déclenché après une réponse 422 (erreur de formulaire).
// turbo:load ne se déclenche PAS dans ce cas, c'est pour ça que le widget
// disparaissait après une erreur et ne réapparaissait qu'au rechargement complet.
document.addEventListener("turbo:render", rerenderHcaptchaWidgets)

// ── Dispose toutes les modales Bootstrap avant que Turbo remplace le body ──────
//
// Problème : Bootstrap garde un flag interne _isAppended=true. Si le body est
// remplacé par Turbo sans dispose(), le backdrop ne se ré-insère plus lors de la
// prochaine ouverture de modale.
//
// Solution : Dispose toutes les modales actives avant turbo:before-render
document.addEventListener("turbo:before-render", () => {
  document.querySelectorAll(".modal").forEach(el => {
    const instance = bootstrap.Modal.getInstance(el)
    if (instance) instance.dispose()
  })
})
