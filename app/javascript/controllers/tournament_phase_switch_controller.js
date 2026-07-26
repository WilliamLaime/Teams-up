import { Controller } from "@hotwired/stimulus"

// Bascule entre les 2 grandes phases du board (round-robin vs tableau final),
// façon onglets « stage » lolesports — cf. commentaire de _phase_nav.html.erb.
// Jamais plus de 2 états, et la valeur par défaut (value: default, recalculée
// côté serveur à chaque rendu) pointe toujours vers la phase "en cours" → rien
// d'important n'est perdu après un re-render Turbo Stream.
export default class extends Controller {
  static targets = ["section", "pill"]
  static values = { default: String }

  connect() {
    this.show(this.defaultValue)
  }

  select(event) {
    this.show(event.currentTarget.dataset.phase)
  }

  show(phase) {
    this.sectionTargets.forEach((section) => { section.hidden = section.dataset.phase !== phase })
    this.pillTargets.forEach((pill) => { pill.classList.toggle("is-active", pill.dataset.phase === phase) })
  }
}
