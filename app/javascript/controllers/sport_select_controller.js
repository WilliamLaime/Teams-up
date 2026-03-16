// Controller Stimulus : sport_select
// Gère la sélection visuelle des sports dans le formulaire d'inscription
// Chaque bouton représente un sport — clic = sélectionné/désélectionné

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "checkbox", "error", "showMore", "showLess"]

  // Appelé quand l'utilisateur clique sur un bouton sport
  toggle(event) {
    const item = event.currentTarget
    const checkbox = item.querySelector("input[type='checkbox']")

    // Inverse l'état coché/décoché
    checkbox.checked = !checkbox.checked

    // Ajoute/retire la classe CSS "selected" pour l'effet visuel
    item.classList.toggle("sport-select-item--selected", checkbox.checked)

    this.updateError()
  }

  // Révèle tous les sports cachés, cache "voir plus" et affiche "voir moins"
  showMore() {
    // Retire la classe qui cache les sports après le 4ème
    this.itemTargets.forEach(item => {
      item.classList.remove("sport-select-item--hidden")
    })
    // Cache "voir plus", affiche "voir moins"
    if (this.hasShowMoreTarget) this.showMoreTarget.style.display = "none"
    if (this.hasShowLessTarget) this.showLessTarget.style.display = "inline-flex"
  }

  // Replie la liste : cache les sports au-delà du 4ème, cache "voir moins", affiche "voir plus"
  showLess() {
    this.itemTargets.forEach((item, index) => {
      if (index >= 4) item.classList.add("sport-select-item--hidden")
    })
    if (this.hasShowLessTarget) this.showLessTarget.style.display = "none"
    if (this.hasShowMoreTarget) this.showMoreTarget.style.display = "inline-flex"
  }

  // Affiche/masque le message d'erreur selon si un sport est sélectionné
  updateError() {
    const hasSelection = this.checkboxTargets.some(cb => cb.checked)
    if (this.hasErrorTarget) {
      this.errorTarget.classList.toggle("d-none", hasSelection)
    }
  }

  // Empêche la soumission si aucun sport n'est sélectionné
  validate(event) {
    const hasSelection = this.checkboxTargets.some(cb => cb.checked)
    if (!hasSelection) {
      event.preventDefault()
      if (this.hasErrorTarget) {
        this.errorTarget.classList.remove("d-none")
        this.errorTarget.scrollIntoView({ behavior: "smooth", block: "center" })
      }
    }
  }
}
