import { Controller } from "@hotwired/stimulus"

// Animation de tirage au sort jouée au lancement d'un tournoi.
// Greffé (via le Turbo Stream de `start`) sur le board en plus du contrôleur
// `bracket`. Il « bat les cartes » de la première ronde puis les révèle en
// cascade, avant de se retirer lui-même (l'animation ne joue qu'une fois).
export default class extends Controller {
  connect() {
    // Respect de la préférence système : pas d'animation si mouvement réduit.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#cleanup()
      return
    }

    this.cards = Array.from(this.element.querySelectorAll(".tmatch-card"))
    if (this.cards.length === 0) {
      this.#cleanup()
      return
    }

    this.#shuffle()
  }

  // Phase 1 : les cartes tremblent brièvement (effet « battage »).
  #shuffle() {
    this.cards.forEach((card) => card.classList.add("tmatch-card--shuffling"))

    setTimeout(() => {
      this.cards.forEach((card) => card.classList.remove("tmatch-card--shuffling"))
      this.#reveal()
    }, 700)
  }

  // Phase 2 : révélation en cascade des appariements.
  #reveal() {
    this.cards.forEach((card, index) => {
      card.classList.add("tmatch-card--hidden")
      setTimeout(() => {
        card.classList.add("tmatch-card--revealed")
        card.classList.remove("tmatch-card--hidden")
      }, index * 120)
    })

    // Une fois la dernière carte révélée, on retire le contrôleur (nettoyage).
    setTimeout(() => this.#cleanup(), this.cards.length * 120 + 400)
  }

  // Retire l'attribut pour que l'animation ne rejoue pas (reconnexion Turbo, etc.).
  #cleanup() {
    const controllers = (this.element.getAttribute("data-controller") || "")
      .split(/\s+/)
      .filter((name) => name && name !== "tournament-draw")
    this.element.setAttribute("data-controller", controllers.join(" "))
  }
}
