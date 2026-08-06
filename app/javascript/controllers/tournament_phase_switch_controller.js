import { Controller } from "@hotwired/stimulus"

// Bascule entre les grandes phases du board (round-robin, barrages, tableau
// final), façon onglets « stage » lolesports — cf. _phase_nav.html.erb.
// Générique par construction : l'appariement se fait sur `dataset.phase`, donc
// ajouter une phase côté serveur (barrages, consolante, classement…) ne demande
// AUCUNE modification ici.
//
// ── Pourquoi sessionStorage ────────────────────────────────────────────────────
// Enregistrer un score répond par un turbo_stream.update("tournament_board")
// (cf. TournamentMatchesController#render_board) : le board entier est remplacé,
// ce contrôleur se reconnecte et retombe sur `defaultValue`, c'est-à-dire la phase
// la PLUS AVANCÉE (cf. default_board_phase). Saisir un score en consolante
// renvoyait donc au tableau final à chaque validation — insupportable quand on
// saisit une série de résultats. La phase choisie est mémorisée par tournoi et
// rejouée au connect ; `defaultValue` ne sert plus qu'au premier affichage.
export default class extends Controller {
  static targets = ["section", "pill"]
  static values = { default: String, storageKey: String }

  connect() {
    this.show(this.stored() || this.defaultValue)
  }

  select(event) {
    const phase = event.currentTarget.dataset.phase
    this.show(phase)
    this.persist(phase)
  }

  // Phase mémorisée, à condition qu'elle existe TOUJOURS dans ce board : une
  // phase peut disparaître (correction d'un score qui détruit l'aval), et on
  // masquerait alors toutes les sections.
  stored() {
    if (!this.hasStorageKeyValue) return null

    const phase = sessionStorage.getItem(this.storageKeyValue)
    return this.pillTargets.some((pill) => pill.dataset.phase === phase) ? phase : null
  }

  persist(phase) {
    if (this.hasStorageKeyValue) sessionStorage.setItem(this.storageKeyValue, phase)
  }

  show(phase) {
    this.sectionTargets.forEach((section) => { section.hidden = section.dataset.phase !== phase })
    this.pillTargets.forEach((pill) => { pill.classList.toggle("is-active", pill.dataset.phase === phase) })
  }
}
