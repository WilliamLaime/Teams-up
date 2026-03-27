// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import * as bootstrap from "bootstrap"

// Ré-initialise les icônes Lucide après chaque mise à jour d'un turbo_frame
// (ex: le bouton ami se met à jour en live → les nouveaux <i data-lucide="..."> doivent être convertis en SVG)
document.addEventListener("turbo:frame-render", () => {
  if (window.lucide) window.lucide.createIcons()
})

// Initialise les tooltips Bootstrap sur chaque navigation Turbo
// Turbo remplace le DOM sans recharger la page — on doit donc ré-initialiser à chaque fois
document.addEventListener("turbo:load", () => {
  // Sélectionne tous les éléments avec l'attribut data-bs-toggle="tooltip"
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipElements.forEach(el => new bootstrap.Tooltip(el))
})
