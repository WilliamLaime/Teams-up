// Stimulus controller : tournament-score
// Pilote la modale de score partagée du tableau de tournoi (Lot 4).
// - open()        : lit les data-* de la carte cliquée (URL PATCH, règles du sport,
//                   sets existants, noms), construit les lignes d'inputs, préremplit,
//                   et ouvre la modale Bootstrap. Mode « Détail » = lecture seule.
// - refreshRows() : (Lot 7) recalcule le nombre de lignes À CHAQUE SAISIE. On part du
//                   minimum de sets nécessaires (3 au ping-pong en poule, 4 en phase
//                   finale) et on n'ajoute une ligne QUE si le match n'est pas encore
//                   décidé — un 2-1 fait apparaître un 4e set, un 3-0 n'en propose
//                   aucun. Évite les 5 (ou 7) lignes vides affichées d'emblée.
// - close()       : ferme la modale après un enregistrement réussi (turbo:submit-end).
//
// Le nombre de sets à gagner vient du serveur (data-...-sets-to-win-param, dérivé de
// TournamentMatch#scoring_rules qui connaît la phase) : le JS ne redéfinit aucune règle,
// et la validation de score reste faite côté modèle (source de vérité).
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
    const { url, mode, allowDraw, bestOf, setsToWin, target, winByTwo, cap, sets, nameA, nameB, editable } = event.params
    const existing = Array.isArray(sets) ? sets : []

    // Contexte de la carte courante, relu par refreshRows() à chaque frappe.
    this.isScoreMode = mode === "score"
    this.bestOf = bestOf || 3
    this.setsToWin = setsToWin || Math.floor(this.bestOf / 2) + 1
    this.editable = editable

    if (url) this.formTarget.action = url
    this.nameATarget.textContent = nameA || "Joueur A"
    this.nameBTarget.textContent = nameB || "Joueur B"
    this.titleTarget.textContent = editable ? "Saisir le score" : "Détail du score"
    this.submitTarget.style.display = editable ? "" : "none"
    this.hintTarget.textContent = editable
      ? this.buildHint(allowDraw, target, winByTwo, cap)
      : ""

    this.renderRows(existing)
    this.modal.show()
  }

  // Rappel de la règle réellement appliquée par le serveur (cf. Sport#scoring_rules).
  buildHint(allowDraw, target, winByTwo, cap) {
    if (this.isScoreMode) {
      return allowDraw ? "Score final du match (match nul autorisé)." : "Score final du match (pas de match nul)."
    }

    const parts = [`${this.setsToWin} sets gagnants (au meilleur des ${this.bestOf})`]
    if (target) {
      // « 11 points, 2 points d'écart » : au-delà de 10-10 il faut deux points d'avance.
      parts.push(winByTwo ? `set en ${target} points avec 2 points d'écart` : `set en ${target} points`)
    }
    if (cap) parts.push(`${cap} points maximum (tie-break)`)

    return `${parts.join(" · ")}.`
  }

  // Ferme la modale uniquement si l'enregistrement a réussi.
  close(event) {
    if (event?.detail?.success === false) return
    this.modal.hide()
  }

  // Recalcule les lignes après une saisie, en conservant ce qui est déjà tapé.
  refreshRows() {
    this.renderRows(this.currentSets(), { keepFocus: true })
  }

  // Sets actuellement dans le DOM, y compris les lignes incomplètes (on ne veut pas
  // effacer un « 11 » en attente de son adversaire) : [[a, b], …] en chaînes.
  currentSets() {
    return Array.from(this.rowsTarget.querySelectorAll(".score-modal__set")).map((row) => {
      const [a, b] = row.querySelectorAll("input")
      return [a.value, b.value]
    })
  }

  // Nombre de lignes à afficher : au minimum les sets nécessaires pour gagner, plus
  // une ligne d'appoint tant que personne n'a atteint setsToWin — plafonné à bestOf.
  // Ex. ping-pong en poule (3 sets gagnants, best_of 5) : 3 lignes au départ ; à 1-1
  // toujours 3 ; à 2-1 une 4e apparaît ; à 3-1 on s'arrête (les lignes en trop, vides,
  // sont retirées). Un set incomplet compte comme « en cours » : sa ligne reste.
  rowCount(sets) {
    if (this.isScoreMode) return 1

    let wins = [0, 0]
    let playedRows = 0

    sets.forEach(([a, b]) => {
      if (a === "" && b === "") return

      playedRows += 1
      if (a !== "" && b !== "") {
        const scoreA = Number(a)
        const scoreB = Number(b)
        if (scoreA > scoreB) wins[0] += 1
        else if (scoreB > scoreA) wins[1] += 1
      }
    })

    // Match décidé : on n'affiche que les sets réellement joués (au moins setsToWin).
    if (Math.max(...wins) >= this.setsToWin) return Math.max(playedRows, this.setsToWin)

    return Math.min(Math.max(this.setsToWin, playedRows + 1), this.bestOf)
  }

  // (Re)construit les lignes de sets, préremplies avec `sets` ([[a, b], …]).
  // Ne recrée les inputs que si leur nombre change, pour ne pas perdre le focus /
  // le curseur pendant la frappe (refreshRows est appelé à chaque `input`).
  renderRows(sets, { keepFocus = false } = {}) {
    const count = this.rowCount(sets)
    const existingRows = this.rowsTarget.querySelectorAll(".score-modal__set").length
    if (keepFocus && existingRows === count) return

    const active = document.activeElement
    const activeIndex = keepFocus ? Array.from(this.rowsTarget.querySelectorAll("input")).indexOf(active) : -1

    // data-action sur les inputs générés : Stimulus observe le DOM et les branche
    // tout seul, y compris injectés (inutile d'ajouter des listeners à la main).
    // Uniquement en saisie de sets : en lecture seule ou en mode :score, rien à
    // recalculer.
    const attrs = [this.editable ? "" : "readonly", this.editable && !this.isScoreMode ? 'data-action="input->tournament-score#refreshRows"' : ""].join(" ")

    this.rowsTarget.innerHTML = ""
    for (let i = 0; i < count; i++) {
      const pair = sets[i] || ["", ""]
      const row = document.createElement("div")
      row.className = "score-modal__set"
      // isScoreMode : sport collectif à score final unique → 1 seule ligne, libellée
      // "Score final" plutôt que "Set 1".
      row.innerHTML = `
        <span class="score-modal__set-label">${this.isScoreMode ? "Score final" : `Set ${i + 1}`}</span>
        <input type="number" min="0" inputmode="numeric" class="score-modal__input"
               name="tournament_match[games_a][]" value="${pair[0] ?? ""}" ${attrs}>
        <span class="score-modal__sep">–</span>
        <input type="number" min="0" inputmode="numeric" class="score-modal__input"
               name="tournament_match[games_b][]" value="${pair[1] ?? ""}" ${attrs}>
      `
      this.rowsTarget.appendChild(row)
    }

    // Les lignes ont été recréées : on rend le focus à l'input qui l'avait (son index
    // est stable, on n'ajoute/retire qu'en fin de liste).
    if (activeIndex >= 0) this.rowsTarget.querySelectorAll("input")[activeIndex]?.focus()
  }

  get modal() {
    return bootstrap.Modal.getOrCreateInstance(this.modalTarget)
  }
}
