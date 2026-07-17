import { Controller } from "@hotwired/stimulus"

// Bracket viewer de la « Vue d'ensemble » (lecture seule) : zoom (boutons − / + et
// curseur, liés à la même valeur) + filtre par ronde (isole une colonne à la fois).
//
// Le zoom NE fait PAS de transform: scale (qui casserait le défilement et les zones
// de clic) : il pilote la variable CSS --bracket-zoom, et toutes les dimensions des
// colonnes/cartes sont exprimées en `em` → l'ensemble grandit/rétrécit proprement.
export default class extends Controller {
  static targets = ["scroll", "col", "slider", "chip"]
  static values = { zoom: { type: Number, default: 1 } }

  static MIN = 0.7
  static MAX = 1.5
  static STEP = 0.1

  connect() {
    this.#applyZoom()
  }

  zoomIn() {
    this.zoomValue = this.#clamp(this.zoomValue + this.constructor.STEP)
  }

  zoomOut() {
    this.zoomValue = this.#clamp(this.zoomValue - this.constructor.STEP)
  }

  setZoom(event) {
    this.zoomValue = Number(event.target.value)
  }

  // Réagit à tout changement de zoom (boutons OU curseur) → applique et resynchronise.
  zoomValueChanged() {
    this.#applyZoom()
  }

  // Isole la ronde cliquée (masque les autres colonnes). round = -1 → tout afficher.
  filter(event) {
    const round = event.params.round
    this.colTargets.forEach((col) => {
      col.toggleAttribute("hidden", round >= 0 && Number(col.dataset.round) !== round)
    })
    this.chipTargets.forEach((chip) => {
      chip.classList.toggle("is-active", Number(chip.dataset.bracketViewerRoundParam) === round)
    })
  }

  #applyZoom() {
    if (this.hasScrollTarget) {
      this.scrollTarget.style.setProperty("--bracket-zoom", this.zoomValue)
    }
    if (this.hasSliderTarget && Number(this.sliderTarget.value) !== this.zoomValue) {
      this.sliderTarget.value = this.zoomValue
    }
  }

  #clamp(value) {
    return Math.min(this.constructor.MAX, Math.max(this.constructor.MIN, Math.round(value * 10) / 10))
  }
}
