import { Controller } from "@hotwired/stimulus"

// Interactions légères du tableau de tournoi.
// Au survol d'un joueur, on met en évidence toutes ses cartes (son « parcours »)
// dans les rondes et le tableau final, pour suivre facilement un joueur.
export default class extends Controller {
  connect() {
    this.onOver = (event) => this.#highlight(event, true)
    this.onOut = (event) => this.#highlight(event, false)
    this.element.addEventListener("mouseover", this.onOver)
    this.element.addEventListener("mouseout", this.onOut)
  }

  disconnect() {
    this.element.removeEventListener("mouseover", this.onOver)
    this.element.removeEventListener("mouseout", this.onOut)
  }

  #highlight(event, on) {
    const player = event.target.closest(".tmatch-card__player")
    if (!player) return

    const name = player.querySelector(".tmatch-card__name")?.textContent?.trim()
    if (!name) return

    this.element.querySelectorAll(".tmatch-card__name").forEach((el) => {
      if (el.textContent.trim() === name) {
        el.closest(".tmatch-card__player").classList.toggle("tmatch-card__player--tracked", on)
      }
    })
  }
}
