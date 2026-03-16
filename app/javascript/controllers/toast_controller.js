// Contrôleur Stimulus pour les notifications toast
// Gère l'apparition, la disparition automatique et la fermeture manuelle
import { Controller } from "@hotwired/stimulus"

// Durées en millisecondes — centralisées ici pour faciliter les ajustements
const APPEAR_DELAY       = 10    // délai avant l'animation d'entrée (laisse le DOM se mettre en place)
const AUTO_CLOSE_DELAY   = 4000  // durée avant fermeture automatique
const HIDE_ANIMATION_DELAY = 300 // durée de l'animation CSS de sortie avant suppression du DOM

export default class extends Controller {
  connect() {
    // Déclenche l'animation d'entrée après un court délai
    setTimeout(() => {
      this.element.classList.add("flash-toast--visible")
    }, APPEAR_DELAY)

    // Auto-fermeture après AUTO_CLOSE_DELAY
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, AUTO_CLOSE_DELAY)
  }

  disconnect() {
    // Nettoie le timer si l'élément est retiré du DOM avant la fin
    clearTimeout(this.timeout)
  }

  // Ferme le toast : animation de sortie puis suppression du DOM
  dismiss() {
    this.element.classList.remove("flash-toast--visible")
    this.element.classList.add("flash-toast--hiding")

    // Supprime l'élément après la fin de l'animation CSS
    setTimeout(() => {
      this.element.remove()
    }, HIDE_ANIMATION_DELAY)
  }
}
