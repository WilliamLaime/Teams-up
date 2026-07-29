import { Controller } from "@hotwired/stimulus"

// Sélecteur de journée (championnat / poules) : menu déroulant CUSTOM (pas un
// <select> natif, dont le rendu une fois ouvert est imposé par l'OS/le
// navigateur et ne peut pas être habillé) — une seule colonne
// (.round-ribbon__page) reste visible à la fois, cf. _round_ribbon.html.erb
// (local `paginated`). L'état initial (journée en cours visible, reste masqué)
// est déjà posé côté serveur via l'attribut `hidden` : ce contrôleur ne fait que
// basculer au clic, pas d'affichage initial à gérer ici.
export default class extends Controller {
  static targets = ["picker", "toggle", "label", "menu", "option", "column"]

  connect() {
    this.boundClose = this.closeOnOutsideClick.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
  }

  toggle() {
    if (this.menuTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.boundClose)
  }

  close() {
    this.menuTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.boundClose)
  }

  // "Ailleurs" = en dehors du picker (bouton + menu) précisément, pas de tout
  // le round-ribbon : celui-ci contient aussi les cartes de match affichées
  // (liens vers les profils, boutons de score...), qu'un clic doit fermer le
  // menu sans jamais intercepter (pas de preventDefault/stopPropagation ici,
  // la navigation Turbo suit son cours normalement).
  closeOnOutsideClick(event) {
    if (!this.pickerTarget.contains(event.target)) this.close()
  }

  choose(event) {
    const option = event.currentTarget
    const roundNumber = option.dataset.roundNumber

    this.labelTarget.textContent = option.textContent
    this.optionTargets.forEach((o) => {
      const active = o === option
      o.classList.toggle("is-active", active)
      o.setAttribute("aria-selected", active ? "true" : "false")
    })
    this.columnTargets.forEach((column) => {
      column.hidden = column.dataset.roundNumber !== roundNumber
    })
    this.close()
  }
}
