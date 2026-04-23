// Stimulus controller : star_rating
// Gère la sélection des étoiles dans un formulaire d'avis
// Usage : data-controller="star-rating" sur le <form>
//   - data-star-rating-target="stars" sur le conteneur des <span> étoiles
//   - data-star-rating-target="input" sur le <input hidden> pour la note
//   - data-star-rating-target="submit" sur le bouton de soumission (désactivé tant que pas de note)
//   - data-action="click->star-rating#select" + data-value="1..5" sur chaque étoile

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Déclare les targets (éléments du DOM qu'on manipule)
  static targets = ["stars", "input", "submit"]

  connect() {
    // Désactive le bouton de soumission tant qu'aucune étoile n'est sélectionnée
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.style.opacity = "0.5"
    }
  }

  // Appelé au clic sur une étoile
  // event.currentTarget.dataset.value = la note cliquée (1 à 5)
  select(event) {
    const value = parseInt(event.currentTarget.dataset.value)

    // Met à jour la valeur du champ caché (envoyée avec le formulaire)
    if (this.hasInputTarget) {
      this.inputTarget.value = value
    }

    // Met en couleur les étoiles jusqu'à la note sélectionnée
    const allStars = this.starsTarget.querySelectorAll("span")
    allStars.forEach((star, index) => {
      if (index < value) {
        star.style.color = "#1EDD88"  // étoile pleine
      } else {
        star.style.color = "var(--theme-text-muted)"  // étoile vide — couleur selon le thème
      }
    })

    // Active le bouton de soumission et applique l'état "prêt" (couleur hover)
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
      this.submitTarget.style.opacity = "1"
      this.submitTarget.classList.add("btn-cta-primary--rated")
    }
  }
}
