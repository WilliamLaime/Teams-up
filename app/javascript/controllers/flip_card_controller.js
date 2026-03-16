import { Controller } from "@hotwired/stimulus"

// ── Contrôleur Stimulus : carte recto/verso du profil ─────────────────────
// Usage dans la vue :
//   data-controller="flip-card"           → sur le wrapper extérieur
//   data-flip-card-target="inner"         → sur la div qui tourne
//   data-action="click->flip-card#flip"   → sur les boutons retourner

export default class extends Controller {
  // "inner" = la div qui reçoit la rotation CSS
  static targets = ["inner"]

  // Bascule la classe is-flipped → déclenche l'animation 3D via CSS
  flip() {
    this.innerTarget.classList.toggle("is-flipped")
  }
}
