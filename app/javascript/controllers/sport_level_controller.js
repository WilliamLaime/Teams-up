// Controller Stimulus : sport_level
// Gère la sélection visuelle des pills de niveau (Débutant / Intermédiaire / Avancé)
// Quand on clique une pill, elle devient verte (active) et les autres se désactivent

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // pill : chaque bouton de niveau
  // input : le champ hidden qui stocke la valeur sélectionnée
  static targets = ["pill", "input"]

  // Appelé au clic sur une pill
  select(event) {
    const clicked = event.currentTarget
    const value = clicked.dataset.value

    // Met à jour le champ hidden avec la valeur choisie
    this.inputTarget.value = value

    // Retire la classe active de toutes les pills du groupe
    this.pillTargets.forEach(pill => {
      pill.classList.remove("level-pill--active")
    })

    // Ajoute la classe active sur la pill cliquée
    clicked.classList.add("level-pill--active")
  }
}
