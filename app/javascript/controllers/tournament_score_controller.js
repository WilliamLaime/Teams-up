// Stimulus controller : tournament-score
// Pilote la modale de score partagée du tableau de tournoi (Lot 4).
// - open()   : lit les data-* de la carte cliquée (URL PATCH, best_of, cible, sets
//              existants, noms), construit une ligne d'inputs par set, préremplit, et
//              ouvre la modale Bootstrap. Mode « Détail » = lecture seule (submit masqué).
// - close()  : ferme la modale après un enregistrement réussi (turbo:submit-end).
//
// Le contrôleur vit HORS de #tournament_board : il survit aux remplacements Turbo Stream
// du tableau. Ses cibles situées dans le board (aucune ici) seraient de toute façon
// re-scannées par Stimulus après chaque update.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "rows", "title", "nameA", "nameB", "hint", "submit"]

  connect() {
    // ── Fix Bootstrap backdrop + Turbo Drive (cf. review_modal_controller) ──────
    // Bootstrap garde _isAppended = true après la 1re ouverture ; quand Turbo remplace
    // le <body>, le backdrop disparaît du DOM mais Bootstrap le croit encore présent.
    // dispose() AVANT le remplacement réinitialise le flag.
    this._handleTurboBeforeRender = () => {
      if (typeof bootstrap === "undefined") return
      const instance = bootstrap.Modal.getInstance(this.modalTarget)
      if (instance) instance.dispose()
    }
    document.addEventListener("turbo:before-render", this._handleTurboBeforeRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this._handleTurboBeforeRender)
  }

  // Ouvre la modale à partir des données de la carte (data-tournament-score-*-param).
  open(event) {
    const { url, mode, allowDraw, bestOf, target, sets, nameA, nameB, editable } = event.params
    const existing = Array.isArray(sets) ? sets : []
    const isScoreMode = mode === "score"
    const rows = isScoreMode ? 1 : Math.max(bestOf || 3, existing.length)

    if (url) this.formTarget.action = url
    this.nameATarget.textContent = nameA || "Joueur A"
    this.nameBTarget.textContent = nameB || "Joueur B"
    this.titleTarget.textContent = editable ? "Saisir le score" : "Détail du score"
    this.submitTarget.style.display = editable ? "" : "none"
    this.hintTarget.textContent = editable
      ? this.buildHint(isScoreMode, allowDraw, bestOf, target)
      : ""

    this.buildRows(rows, existing, editable, isScoreMode)
    this.modal.show()
  }

  buildHint(isScoreMode, allowDraw, bestOf, target) {
    if (!isScoreMode) return `Au meilleur des ${bestOf} sets · cible ${target} jeux/points par set.`

    return allowDraw ? "Score final du match (match nul autorisé)." : "Score final du match (pas de match nul)."
  }

  // Ferme la modale uniquement si l'enregistrement a réussi.
  close(event) {
    if (event?.detail?.success === false) return
    this.modal.hide()
  }

  // (Re)génère `count` lignes de sets, préremplies avec `existing` ([[a, b], …]).
  // `isScoreMode` : sport collectif à score final unique → 1 seule ligne, libellée
  // "Score final" plutôt que "Set 1".
  buildRows(count, existing, editable, isScoreMode = false) {
    this.rowsTarget.innerHTML = ""
    for (let i = 0; i < count; i++) {
      const pair = existing[i] || ["", ""]
      const row = document.createElement("div")
      row.className = "score-modal__set"
      row.innerHTML = `
        <span class="score-modal__set-label">${isScoreMode ? "Score final" : `Set ${i + 1}`}</span>
        <input type="number" min="0" inputmode="numeric" class="score-modal__input"
               name="tournament_match[games_a][]" value="${pair[0]}" ${editable ? "" : "readonly"}>
        <span class="score-modal__sep">–</span>
        <input type="number" min="0" inputmode="numeric" class="score-modal__input"
               name="tournament_match[games_b][]" value="${pair[1]}" ${editable ? "" : "readonly"}>
      `
      this.rowsTarget.appendChild(row)
    }
  }

  get modal() {
    return bootstrap.Modal.getOrCreateInstance(this.modalTarget)
  }
}
