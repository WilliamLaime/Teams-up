// level_filter_controller.js
// Gère le dropdown personnalisé pour le filtre de niveau (multi-sélection).
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
    // Met à jour le label si des niveaux sont déjà dans l'URL
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
    // On contrôle directement le style inline — pas de conflit CSS possible
    if (dropdown.style.display === "none") {
      // Prévient les autres dropdowns de se fermer
      document.dispatchEvent(new CustomEvent("filter:opened", { detail: { source: this } }))
      dropdown.style.display = "flex"
      dropdown.style.flexDirection = "column"
      // Réinitialise le flag de modification à l'ouverture
      this.dirty = false
    } else {
      // Ferme et soumet si une checkbox a changé
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme ce dropdown si un autre filtre vient de s'ouvrir
  handleOtherOpened(event) {
    if (event.detail.source !== this) {
      // Soumet si une checkbox a changé avant de fermer
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown si on clique ailleurs sur la page
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      // Soumet si une checkbox a changé avant de fermer
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown et soumet le formulaire si quelque chose a changé
  closeAndSubmitIfDirty() {
    this.dropdownTarget.style.display = "none"
    if (this.dirty) {
      this.dirty = false
      this.element.closest("form").requestSubmit()
    }
  }

  // Appelé à chaque checkbox cochée/décochée — met à jour le label et marque comme modifié
  change() {
    this.updateLabel()
    // Marque que l'utilisateur a changé une sélection
    this.dirty = true
  }

  // Soumet le formulaire et ferme le dropdown — appelé par le bouton "Appliquer"
  apply(event) {
    event.stopPropagation()
    this.dropdownTarget.style.display = "none"
    this.element.closest("form").requestSubmit()
  }

  // Met à jour le texte du trigger selon les cases cochées
  updateLabel() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)

    if (checked.length === 0) {
      this.labelTarget.textContent = "Niveau"
    } else if (checked.length === 1) {
      this.labelTarget.textContent = checked[0].value
    } else {
      this.labelTarget.textContent = `${checked.length} niveaux`
    }
  }
}
