import { Controller } from "@hotwired/stimulus"

// Bascule entre les grandes phases du board (round-robin, barrages, tableau
// final), façon onglets « stage » lolesports — cf. _phase_nav.html.erb.
// Générique par construction : l'appariement se fait sur `dataset.phase`, donc
// ajouter une phase côté serveur (barrages, consolante, classement…) ne demande
// AUCUNE modification ici. La valeur par défaut (value: default, recalculée côté
// serveur à chaque rendu, cf. default_board_phase) pointe toujours vers la phase
// la plus avancée → rien d'important n'est perdu après un re-render Turbo Stream.
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
