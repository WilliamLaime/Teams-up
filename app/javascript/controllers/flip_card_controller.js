import { Controller } from "@hotwired/stimulus"

// ── Contrôleur Stimulus : carte recto/verso du profil ─────────────────────
// Usage dans la vue :
//   data-controller="flip-card"           → sur le wrapper extérieur (.profil-card-wrapper)
//   data-flip-card-target="inner"         → sur la div qui tourne
//   data-flip-card-target="ornament"      → sur l'ornement SVG au-dessus de la card
//   data-action="click->flip-card#flip"   → sur les boutons retourner

export default class extends Controller {
  // "inner" = la div qui reçoit la rotation CSS
  // "ornament" = l'ornement SVG qui s'anime en même temps (optionnel)
  static targets = ["inner", "ornament"]

  // Bascule la classe is-flipped → déclenche l'animation 3D via CSS
  // + anime l'ornement : scaleX(-1) pour un effet miroir synchronisé
  flip() {
    this.innerTarget.classList.toggle("is-flipped")

    // Si l'ornement existe, on le retourne en miroir avec la carte
    if (this.hasOrnamentTarget) {
      const isFlipped = this.innerTarget.classList.contains("is-flipped")
      this.ornamentTarget.style.transform = isFlipped
        ? "translateY(-50%) scaleX(-1)"  // miroir horizontal quand verso visible
        : "translateY(-50%) scaleX(1)"   // normal quand recto visible
    }
  }
}
