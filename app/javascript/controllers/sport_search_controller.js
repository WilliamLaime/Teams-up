// sport_search_controller.js
// Filtre les sports dans le dropdown de la navbar en temps réel.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "input"  : le champ de recherche
  // "item"   : chaque ligne de sport dans le dropdown
  static targets = ["input", "item"]

  // Appelé à chaque frappe dans le champ de recherche
  filter() {
    // Récupère la valeur saisie, en minuscules et sans espaces superflus
    const query = this.inputTarget.value.toLowerCase().trim()

    this.itemTargets.forEach(item => {
      // Récupère le nom du sport stocké dans data-sport-name
      const name = item.dataset.sportName.toLowerCase()

      // Affiche l'item si son nom contient la recherche, sinon le cache
      item.style.display = name.includes(query) ? "" : "none"
    })
  }

  // Empêche le dropdown Bootstrap de se fermer quand on clique dans le champ
  stopPropagation(event) {
    event.stopPropagation()
  }
}
