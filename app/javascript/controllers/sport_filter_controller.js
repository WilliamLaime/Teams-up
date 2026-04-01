// sport_filter_controller.js
// Gère le dropdown de filtre sport — sélection unique (radio buttons).
// Auto-soumet le formulaire dès qu'un radio est sélectionné.
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
    // Met à jour le label si un sport est déjà dans l'URL
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

  // Ferme le dropdown si on clique ailleurs (sans soumettre — le submit a déjà eu lieu)
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.style.display = "none"
    }
  }

  // Appelé quand l'utilisateur clique un radio — ferme immédiatement et soumet
  change() {
    this.updateLabel()
    // Informe le filtre de niveaux que le sport a changé (mise à jour visuelle instantanée)
    this._dispatchSportChanged()
    // Ferme le dropdown et soumet le formulaire directement
    this.dropdownTarget.style.display = "none"
    this.element.closest("form").requestSubmit()
  }

  // Dispatche "sport:changed" avec l'ID du sport sélectionné (ou [] si "Tous")
  _dispatchSportChanged() {
    const selected = this.checkboxTargets.find(cb => cb.checked)
    // Si la valeur est vide ("Tous les sports") ou absente → sportIds = []
    const sportIds = selected?.value ? [parseInt(selected.value, 10)] : []
    document.dispatchEvent(new CustomEvent("sport:changed", { detail: { sportIds } }))
  }

  // Met à jour le label du trigger selon le radio coché
  updateLabel() {
    const selected = this.checkboxTargets.find(cb => cb.checked)

    if (!selected || !selected.value) {
      // Aucun sport ou "Tous les sports" → label par défaut
      this.labelTarget.innerHTML = "Sport"
    } else {
      // Un sport sélectionné : affiche son icône via data-label-html
      this.labelTarget.innerHTML = selected.dataset.labelHtml
    }
  }
}
