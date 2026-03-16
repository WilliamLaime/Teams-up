// sport_filter_controller.js
// Gère le dropdown personnalisé pour le filtre de sport (multi-sélection).
// Calqué sur level_filter_controller.js pour une UX cohérente.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "label", "checkbox"]

  connect() {
    // Ferme le dropdown si on clique en dehors
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)
    // Ferme ce dropdown si un autre s'ouvre (custom event "filter:opened")
    this.handleOtherOpened = this.handleOtherOpened.bind(this)
    document.addEventListener("filter:opened", this.handleOtherOpened)
    // Met à jour le label si des sports sont déjà dans l'URL
    this.updateLabel()
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
    document.removeEventListener("filter:opened", this.handleOtherOpened)
  }

  // Ouvre ou ferme le dropdown au clic sur le trigger
  toggle(event) {
    event.stopPropagation()
    const dropdown = this.dropdownTarget
    if (dropdown.style.display === "none") {
      // Prévient les autres dropdowns de se fermer
      document.dispatchEvent(new CustomEvent("filter:opened", { detail: { source: this } }))
      dropdown.style.display = "flex"
      dropdown.style.flexDirection = "column"
    } else {
      dropdown.style.display = "none"
    }
  }

  // Ferme ce dropdown si un autre filtre vient de s'ouvrir
  handleOtherOpened(event) {
    if (event.detail.source !== this) {
      this.dropdownTarget.style.display = "none"
    }
  }

  // Ferme le dropdown si on clique ailleurs
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.style.display = "none"
    }
  }

  // Appelé à chaque checkbox cochée/décochée — met à jour le label
  change() {
    this.updateLabel()
  }

  // Coche toutes les checkboxes si au moins une est décochée, sinon toutes les décoche
  selectAll(event) {
    event.stopPropagation()
    const allChecked = this.checkboxTargets.every(cb => cb.checked)
    this.checkboxTargets.forEach(cb => cb.checked = !allChecked)
    this.updateLabel()
  }

  // Soumet le formulaire et ferme le dropdown
  apply(event) {
    event.stopPropagation()
    this.dropdownTarget.style.display = "none"
    this.element.closest("form").requestSubmit()
  }

  // Met à jour le label du trigger selon les cases cochées
  updateLabel() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)

    if (checked.length === 0) {
      // Aucun sport sélectionné → label par défaut
      this.labelTarget.innerHTML = "Sport"
    } else if (checked.length === 1) {
      // Un seul sport : utilise data-label-html pour afficher l'icône image si besoin
      this.labelTarget.innerHTML = checked[0].dataset.labelHtml
    } else {
      // Plusieurs sports → compteur
      this.labelTarget.innerHTML = `${checked.length} sports`
    }
  }
}
