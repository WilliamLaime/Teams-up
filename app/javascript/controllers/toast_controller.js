// Contrôleur Stimulus pour les notifications toast
// Gère l'apparition, la disparition automatique et la fermeture manuelle
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Déclenche l'animation d'entrée après un court délai (laisse le DOM se mettre en place)
    setTimeout(() => {
      this.element.classList.add("flash-toast--visible")
    }, 10)

    // Auto-fermeture après 4 secondes
    this.timeout = setTimeout(() => {
      this.dismiss()
    }, 4000)
  }

  disconnect() {
    // Nettoie le timer si l'élément est retiré du DOM avant la fin
    clearTimeout(this.timeout)
  }

  // Ferme le toast : animation de sortie puis suppression du DOM
  dismiss() {
    this.element.classList.remove("flash-toast--visible")
    this.element.classList.add("flash-toast--hiding")

    // Supprime l'élément après la fin de l'animation CSS (300ms)
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
