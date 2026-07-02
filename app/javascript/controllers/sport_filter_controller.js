// sport_filter_controller.js
// Gère le dropdown de filtre sport — multi-sélection (checkboxes).
// L'utilisateur coche un ou plusieurs sports puis clique "Appliquer"
// (ou ferme le dropdown, ce qui soumet si la sélection a changé).
// Dispatche "sport:changed" pour que level_filter_controller reconstruise ses options.
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
    // Met à jour le label selon les sports déjà cochés (URL / défaut)
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
      document.dispatchEvent(new CustomEvent("filter:opened", { detail: { source: this } }))
      dropdown.style.display = "flex"
      dropdown.style.flexDirection = "column"
      // Réinitialise le flag de modification à l'ouverture
      this.dirty = false
    } else {
      // Ferme et soumet si une case a changé
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme ce dropdown si un autre filtre vient de s'ouvrir
  handleOtherOpened(event) {
    if (event.detail.source !== this) {
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown si on clique ailleurs sur la page
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown et soumet le formulaire si la sélection a changé
  closeAndSubmitIfDirty() {
    this.dropdownTarget.style.display = "none"
    if (this.dirty) {
      this.dirty = false
      this.element.closest("form").requestSubmit()
    }
  }

  // Appelé à chaque case cochée/décochée — met à jour le label, prévient
  // le filtre de niveaux et marque la sélection comme modifiée
  change() {
    this.updateLabel()
    this._dispatchSportChanged()
    this.dirty = true
  }

  // Soumet le formulaire et ferme le dropdown — appelé par le bouton "Appliquer"
  apply(event) {
    event.stopPropagation()
    this.dropdownTarget.style.display = "none"
    this.element.closest("form").requestSubmit()
  }

  // Dispatche "sport:changed" avec les IDs de tous les sports cochés
  _dispatchSportChanged() {
    const sportIds = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => parseInt(cb.value, 10))
    document.dispatchEvent(new CustomEvent("sport:changed", { detail: { sportIds } }))
  }

  // Met à jour le texte/icône du trigger selon les cases cochées
  updateLabel() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)

    if (checked.length === 0) {
      // Aucun sport → label par défaut
      this.labelTarget.innerHTML = "Sport"
    } else if (checked.length === this.checkboxTargets.length) {
      // Tous les sports cochés → "Tous les sports"
      this.labelTarget.innerHTML = "Tous les sports"
    } else if (checked.length === 1) {
      // Un seul sport : affiche son icône via data-label-html
      this.labelTarget.innerHTML = checked[0].dataset.labelHtml
    } else {
      // Plusieurs sports (mais pas tous)
      this.labelTarget.innerHTML = `${checked.length} sports`
    }
  }
}
