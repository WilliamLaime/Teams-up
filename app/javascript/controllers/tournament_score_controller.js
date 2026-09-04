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
//                   Le rendu est INCRÉMENTAL : les lignes déjà affichées ne sont
//                   jamais recréées ni réécrites (cf. le bloc « Rendu des lignes de
//                   sets » plus bas, qui explique quel bug cela corrige).
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
  static targets = [
    "modal", "form", "rows", "title", "nameA", "nameB", "hint", "submit",
    "tally", "tallyA", "tallyB", "serverErrors"
  ]

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
    // Règles du sport, telles que le serveur les appliquera (Sport#scoring_rules) :
    // on les garde pour valider côté client AVANT l'envoi. Le serveur reste la
    // source de vérité — TournamentMatch#valid_set? refuse de toute façon un set
    // invalide ; ce contrôle-ci ne fait que le dire tout de suite.
    this.rules = { target, winByTwo, cap, allowDraw }

    if (url) this.formTarget.action = url
    this.nameATarget.textContent = nameA || "Joueur A"
    this.nameBTarget.textContent = nameB || "Joueur B"
    // « Gérer le score » : même libellé que le bouton qui ouvre la modale (cf.
    // _tmatch_actions), qu'un score soit déjà saisi ou non — la modale fait les
    // deux, deux titres pour la même fenêtre ne renseignaient sur rien.
    this.titleTarget.textContent = editable ? "Gérer le score" : "Détail du score"
    this.submitTarget.style.display = editable ? "" : "none"
    this.hintTarget.textContent = editable
      ? this.buildHint(allowDraw, target, winByTwo, cap)
      : ""

    // Erreurs serveur d'une saisie précédente : elles ne concernent pas ce match.
    this.serverErrorsTarget.innerHTML = ""

    this.resetRows(existing)
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
  // Pas de refreshErrors() ici : la validation reste au blur (cf. rowAttrs), sinon
  // les messages des autres lignes clignoteraient en pleine frappe.
  refreshRows() {
    const sets = this.currentSets()
    this.syncRows(sets)
    this.updateTally(sets)
  }

  // Sets gagnés par chaque joueur : [gagnés par A, gagnés par B].
  // Un set ne compte que s'il est RÉELLEMENT gagné selon les règles du sport :
  //   • les deux scores saisis (« 11 – vide » est encore en cours) ;
  //   • et le score est valide — au ping-pong, 11 points, ou plus de 11 avec
  //     2 points d'écart. Un 11-10 ou un 12-2 ne fait donc monter personne :
  //     ce set n'est pas terminé (ou n'a pas pu se produire).
  setWins(sets) {
    const wins = [0, 0]

    sets.forEach(([a, b]) => {
      if (a === "" || b === "") return
      if (this.setError(a, b)) return
      if (Number(a) > Number(b)) wins[0] += 1
      else if (Number(b) > Number(a)) wins[1] += 1
    })

    return wins
  }

  // Compteur de sets sous les lignes de saisie : 0 – 0 au départ, incrémenté dès
  // qu'un set est complet. Le joueur en tête est mis en avant (classe is-leading).
  updateTally(sets) {
    // Sport à score final unique : pas de sets à compter.
    this.tallyTarget.hidden = this.isScoreMode
    if (this.isScoreMode) return

    const [winsA, winsB] = this.setWins(sets)

    this.tallyATarget.textContent = winsA
    this.tallyBTarget.textContent = winsB
    this.tallyATarget.classList.toggle("is-leading", winsA > winsB)
    this.tallyBTarget.classList.toggle("is-leading", winsB > winsA)
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
  // sont retirées).
  //
  // Un set À MOITIÉ rempli (« 11 – vide ») est en cours de saisie : il ne vaut pas
  // encore une victoire, et surtout il ne justifie PAS de ligne d'appoint — c'est lui
  // l'appoint. Sinon, taper 11 au 3e set d'un 2-0 ferait apparaître un 4e set qui
  // disparaîtrait dès le score adverse saisi (le match étant alors gagné 3-0).
  rowCount(sets) {
    if (this.isScoreMode) return 1

    const wins = this.setWins(sets)
    let complete = 0 // sets aux deux scores saisis
    let pending = 0  // sets à un seul score saisi (en cours de frappe)

    sets.forEach(([a, b]) => {
      if (a === "" && b === "") return
      if (a === "" || b === "") pending += 1
      else complete += 1
    })

    // Match décidé : on n'affiche que les sets réellement joués (au moins setsToWin).
    if (Math.max(...wins) >= this.setsToWin) return Math.max(complete + pending, this.setsToWin)

    // Une ligne d'appoint seulement si aucun set n'est en cours de saisie.
    const needed = complete + (pending > 0 ? pending : 1)
    return Math.min(Math.max(this.setsToWin, needed), this.bestOf)
  }

  // ── Rendu des lignes de sets ────────────────────────────────────────────────
  // ⚠️ Ce bloc a été écrit deux fois. La 1re version reconstruisait TOUTES les
  // lignes à chaque frappe (`rowsTarget.innerHTML = ""`) puis rendait le focus à
  // l'input qui l'avait. L'élément refocalisé était bien le bon, mais un input
  // fraîchement créé replace son CARET en position 0 : taper « 13 » quand le 1er
  // chiffre complète un set (donc fait apparaître une ligne) écrivait « 31 » — le
  // « 3 » s'insérait DEVANT le « 1 ». Et `setSelectionRange()` ne pouvait pas
  // réparer ça : il lève InvalidStateError sur un `<input type="number">`.
  //
  // D'où le rendu INCRÉMENTAL ci-dessous : on n'ajoute et ne retire que des lignes
  // EN FIN de liste, et on ne réécrit JAMAIS la valeur d'une ligne conservée. Le
  // champ en cours de frappe n'est donc jamais recréé ni réécrit — son caret est
  // intact par construction, et aucun focus() programmatique n'est nécessaire.

  // Rendu COMPLET, pour une nouvelle carte : seul endroit qui détruit des lignes.
  // Légitime ici, et seulement ici — la modale n'est pas encore visible, et le match,
  // le sport et le mode changent (des N lignes de sets à 1 ligne « Score final »,
  // par exemple, ce que syncRows refuserait de faire sur des lignes remplies).
  resetRows(sets) {
    this.rowsTarget.innerHTML = ""
    this.syncRows(sets)
    this.refreshErrors() // réaffiche les erreurs d'un score déjà enregistré
    this.updateTally(sets)
  }

  // Réconciliation : amène le nombre de lignes à rowCount(sets) SANS toucher aux
  // lignes conservées. Appelé à chaque frappe — cf. l'avertissement ci-dessus.
  syncRows(sets) {
    const count = this.rowCount(sets)

    // 1) Retrait de l'excédent, en partant de la fin. Le `break` est essentiel :
    //    il garantit qu'on ne laisse jamais de trou au milieu de la liste, ce qui
    //    désynchroniserait les libellés « Set N » et l'ordre des games_a[]/games_b[]
    //    envoyés au serveur.
    const rows = this.rowElements()
    for (let i = rows.length - 1; i >= count; i--) {
      if (!this.isRemovableRow(rows[i])) break
      rows[i].remove()
    }

    // 2) Ajout des lignes manquantes, en fin de liste.
    const attrs = this.rowAttrs()
    for (let i = this.rowElements().length; i < count; i++) {
      this.rowsTarget.appendChild(this.buildRow(i, sets[i], attrs))
    }
  }

  rowElements() {
    return Array.from(this.rowsTarget.querySelectorAll(".score-modal__set"))
  }

  // Une ligne ne se retire que si elle est VIDE et ne contient pas le focus.
  // Vide : sinon un 4e set déjà saisi disparaîtrait en vidant le set 1 (ce que
  // faisait l'ancienne version, silencieusement). Sans le focus : on n'arrache pas
  // le champ sous les doigts de l'utilisateur — la ligne sera élaguée à son blur
  // (cf. validateSet).
  isRemovableRow(row) {
    if (row.contains(document.activeElement)) return false

    return Array.from(row.querySelectorAll("input")).every((input) => input.value === "")
  }

  // Attributs communs aux inputs générés. Seul endroit qui connaît le mode lecture
  // seule et isScoreMode.
  // data-action posé en ATTRIBUT : Stimulus observe le DOM et branche tout seul les
  // inputs injectés (inutile — et nuisible — d'ajouter des listeners à la main).
  // Uniquement en saisie de sets : en lecture seule ou en mode :score, rien à
  // recalculer.
  // `blur->…#validateSet` : le message d'erreur n'apparaît qu'une fois le champ
  // quitté. Valider à la frappe accuserait « 1 » d'être un score invalide alors
  // que l'utilisateur est en train de taper « 11 ».
  rowAttrs() {
    const actions = [
      this.editable && !this.isScoreMode ? "input->tournament-score#refreshRows" : "",
      this.editable ? "blur->tournament-score#validateSet" : ""
    ].filter(Boolean).join(" ")

    return [this.editable ? "" : "readonly", actions ? `data-action="${actions}"` : ""].join(" ")
  }

  // Une ligne de set, prête à être insérée.
  // isScoreMode : sport collectif à score final unique → 1 seule ligne, libellée
  // "Score final" plutôt que "Set 1".
  buildRow(index, pair, attrs = this.rowAttrs()) {
    const [a, b] = pair || ["", ""]
    const row = document.createElement("div")
    row.className = "score-modal__set"
    row.innerHTML = `
      <span class="score-modal__set-label">${this.isScoreMode ? "Score final" : `Set ${index + 1}`}</span>
      ${this.stepperHtml("games_a", a, attrs)}
      <span class="score-modal__sep">–</span>
      ${this.stepperHtml("games_b", b, attrs)}
      <p class="score-modal__error" hidden></p>
    `
    return row
  }

  // ── Validation d'un set ─────────────────────────────────────────────────────
  // Miroir EXACT de TournamentMatch#valid_set? (+ le refus du set nul). Le serveur
  // reste l'autorité ; ce contrôle évite juste l'aller-retour et dit précisément
  // ce qui cloche, au moment où le champ est quitté.

  // Message d'erreur d'une paire de scores, ou null si elle est valide.
  // Une paire incomplète n'est pas « invalide » : elle est en cours de saisie.
  setError(a, b) {
    if (a === "" || b === "") return null

    const hi = Math.max(Number(a), Number(b))
    const lo = Math.min(Number(a), Number(b))
    const { target, winByTwo, cap } = this.rules

    if (hi === lo) return "Un set ne peut pas se terminer sur une égalité."
    if (target && hi < target) return `Le gagnant du set doit atteindre ${target} points.`
    if (cap && hi > cap) return `Le set ne peut pas dépasser ${cap} points.`

    // Sport non configuré (pas de règle des 2 points) : atteindre la cible suffit.
    if (!winByTwo) return null

    if (hi === target) {
      if (lo > target - 2) {
        return cap
          ? `À ${hi}-${lo}, il faut 2 points d'écart (ou atteindre ${cap}).`
          : `À ${hi}-${lo}, il faut 2 points d'écart : le set continue.`
      }
      return null
    }

    if (cap && hi === cap) return null // au plafond, 1 point d'écart suffit

    // Au-delà de la cible, on est en prolongation : elle se conclut à 2 points
    // d'écart, jamais plus — un set ne continue pas après avoir été gagné.
    if (hi - lo !== 2) {
      if (hi - lo < 2) return `À ${hi}-${lo}, il faut 2 points d'écart : le set continue.`

      // Écart de plus de 2 au-delà de la cible : impossible, mais le score correct
      // dépend du perdant. En dessous de target-1 (ex. 12-2), la prolongation n'a
      // jamais eu lieu : le set s'était terminé à 11-2. Au-delà, il s'agit d'une
      // prolongation qui aurait dû s'arrêter 2 points plus tôt (ex. 15-11 → 13-11).
      return lo <= target - 2
        ? `Score impossible : le set était déjà gagné à ${target}-${lo}.`
        : `Score impossible : au-delà de ${target}, le set se termine dès 2 points d'écart (${lo + 2}-${lo}).`
    }

    return null
  }

  validateSet(event) {
    // showError AVANT l'élagage : il a besoin du closest(".score-modal__set") du
    // champ quitté, que refreshRows peut justement retirer.
    this.showError(event.currentTarget.closest(".score-modal__set"))
    // Élague une ligne vide conservée uniquement parce qu'elle avait le focus
    // (cf. isRemovableRow). Pas de récursion : refreshRows ne déclenche aucun blur.
    if (this.editable && !this.isScoreMode) this.refreshRows()
  }

  // Réaffiche les erreurs de toutes les lignes — appelé après une reconstruction
  // des lignes, qui efface les messages déjà posés.
  refreshErrors() {
    this.rowsTarget.querySelectorAll(".score-modal__set").forEach((row) => this.showError(row))
  }

  showError(row) {
    if (!row) return false

    const [a, b] = row.querySelectorAll("input")
    const message = this.setError(a.value, b.value)
    const slot = row.querySelector(".score-modal__error")

    row.classList.toggle("is-invalid", Boolean(message))
    if (slot) {
      slot.textContent = message || ""
      slot.hidden = !message
    }
    return Boolean(message)
  }

  // Dernier filet avant l'envoi : un set peut être invalide sans avoir jamais été
  // quitté (validation au blur), typiquement si on clique droit sur « Enregistrer ».
  validateForm(event) {
    const rows = Array.from(this.rowsTarget.querySelectorAll(".score-modal__set"))
    const invalid = rows.map((row) => this.showError(row)).some(Boolean)
    if (invalid) event.preventDefault()
  }

  // Un champ de score avec ses boutons − / +. Les flèches natives de
  // <input type="number"> sont minuscules, dessinées par l'OS et invisibles sur
  // fond sombre : on les masque en CSS et on les remplace par deux vrais boutons,
  // utilisables au doigt. En lecture seule (Détail) il n'y a rien à incrémenter.
  stepperHtml(field, value, attrs) {
    const buttons = this.editable
      ? {
          minus: '<button type="button" class="score-modal__step" tabindex="-1" aria-label="Retirer un point" data-step="-1" data-action="click->tournament-score#step">−</button>',
          plus: '<button type="button" class="score-modal__step" tabindex="-1" aria-label="Ajouter un point" data-step="1" data-action="click->tournament-score#step">+</button>'
        }
      : { minus: "", plus: "" }

    return `
      <div class="score-modal__stepper">
        ${buttons.minus}
        <input type="number" min="0" inputmode="numeric" class="score-modal__input"
               name="tournament_match[${field}][]" value="${value ?? ""}" ${attrs}>
        ${buttons.plus}
      </div>
    `
  }

  // − / + sur un champ de score. Un champ vide vaut 0 : « + » y écrit 1, « − » ne
  // fait rien (descendre sous zéro n'existe pas, et repasser un champ vide à 0
  // le ferait compter comme un set joué).
  step(event) {
    const button = event.currentTarget
    const input = button.parentElement.querySelector("input")
    const delta = Number(button.dataset.step)

    if (delta < 0 && (input.value === "" || Number(input.value) <= 0)) return

    input.value = Math.max(0, (Number(input.value) || 0) + delta)
    this.refreshRows() // une ligne de set peut apparaître ou disparaître
    // Les boutons − / + ne déclenchent aucun `blur` : sans cet appel, un 12-2
    // construit uniquement à la souris n'affichait son erreur qu'à l'envoi.
    this.refreshErrors()
  }

  get modal() {
    return bootstrap.Modal.getOrCreateInstance(this.modalTarget)
  }
}
