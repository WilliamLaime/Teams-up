import { Controller } from "@hotwired/stimulus"

// Filtre de journées (championnat / poules) : menu déroulant CUSTOM (pas un
// <select> natif, dont le rendu une fois ouvert est imposé par l'OS/le
// navigateur et ne peut pas être habillé) qui pilote la visibilité des colonnes
// .round-ribbon__page, cf. _round_ribbon.html.erb (local `paginated`).
//
// MULTI-SÉLECTION : on affiche une journée, plusieurs, ou toutes. Invariant —
// au moins une journée reste toujours cochée : décocher la dernière donnerait un
// ruban vide, état sans signification dont l'utilisateur ne pourrait sortir que
// par tâtonnement. Le clic sur la seule journée cochée est donc ignoré.
//
// MÉMORISATION — le serveur présélectionne toujours la 1re journée non terminée.
// Or la saisie d'un score répond par un turbo_stream.update("tournament_board")
// (cf. TournamentMatchesController#render_board) qui re-rend le ruban de zéro :
// sans mémoire, consulter la Journée 1 puis corriger un score y ramènerait
// brutalement à la journée en cours. On garde donc la sélection en
// sessionStorage (par tournoi + phase) et on la rejoue au `connect` — le
// contrôleur est ré-instancié à chaque remplacement du DOM, c'est exactement le
// moment où l'état serveur doit être écrasé.
export default class extends Controller {
  static targets = ["picker", "toggle", "label", "menu", "option", "allOption", "column"]
  static values = { storageKey: String }

  connect() {
    this.boundClose = this.closeOnOutsideClick.bind(this)
    this.restore()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
  }

  // ── Sélection ──────────────────────────────────────────────────────────────

  // La vérité, c'est l'état des cases : on la lit dans le DOM plutôt que de la
  // dupliquer dans une propriété qui pourrait diverger.
  get selected() {
    return this.optionTargets.filter((o) => o.checked).map((o) => o.dataset.roundNumber)
  }

  // Le menu reste OUVERT après un clic : en multi-sélection, le refermer à chaque
  // case imposerait un aller-retour par journée ajoutée.
  choose(event) {
    const next = this.selected

    // Décocher la dernière case est refusé (cf. l'invariant plus haut) : la case
    // est déjà décochée par le navigateur, on la remet.
    if (next.length === 0) {
      event.currentTarget.checked = true
      return
    }

    this.apply(next)
    this.persist(next)
  }

  // Raccourci « tout / rien » : décocher la case globale revient à la seule
  // journée en cours (celle que le serveur avait présélectionnée) plutôt qu'à
  // rien du tout — voir l'invariant.
  toggleAll(event) {
    const all = this.optionTargets.map((o) => o.dataset.roundNumber)
    const next = event.currentTarget.checked ? all : [this.defaultNumber()]

    this.apply(next)
    this.persist(next)
  }

  // Journée présélectionnée par le serveur, mémorisée au tout premier rendu :
  // les cases bougent ensuite au gré des clics, elle ne peut donc plus être
  // relue depuis le DOM après coup.
  defaultNumber() {
    if (!this.serverDefault) {
      const checked = this.optionTargets.find((o) => o.checked)
      this.serverDefault = (checked || this.optionTargets[0]).dataset.roundNumber
    }
    return this.serverDefault
  }

  // Bascule pure (aucune écriture en sessionStorage) : partagée par le clic, le
  // raccourci et la restauration, pour que les trois chemins produisent le même état.
  apply(numbers) {
    this.optionTargets.forEach((o) => { o.checked = numbers.includes(o.dataset.roundNumber) })
    this.columnTargets.forEach((column) => {
      column.hidden = !numbers.includes(column.dataset.roundNumber)
    })
    if (this.hasAllOptionTarget) {
      // `indeterminate` (le trait, pas la coche) quand la sélection est partielle :
      // c'est exactement ce que la case globale décrit alors.
      this.allOptionTarget.checked = numbers.length === this.optionTargets.length
      this.allOptionTarget.indeterminate = numbers.length > 0 && !this.allOptionTarget.checked
    }
    this.labelTarget.textContent = this.labelFor(numbers)
  }

  labelFor(numbers) {
    if (numbers.length === this.optionTargets.length) return "Toutes les journées"
    if (numbers.length === 1) {
      const option = this.optionTargets.find((o) => o.dataset.roundNumber === numbers[0])
      return option ? option.dataset.roundTitle : ""
    }
    return `${numbers.length} journées`
  }

  persist(numbers) {
    if (this.storageKeyValue) sessionStorage.setItem(this.storageKeyValue, numbers.join(","))
  }

  restore() {
    this.defaultNumber() // fige la présélection serveur AVANT de la recouvrir
    const stored = this.storageKeyValue && sessionStorage.getItem(this.storageKeyValue)

    // Des journées mémorisées peuvent avoir disparu (tournoi régénéré, correction
    // de score) : on ne garde que celles qui existent encore, et si plus rien ne
    // subsiste on retombe sur la présélection du serveur, qui est juste.
    const known = this.optionTargets.map((o) => o.dataset.roundNumber)
    const numbers = (stored || "").split(",").filter((n) => known.includes(n))

    // apply() est appelé même sans rien à restaurer : c'est lui qui synchronise
    // la case « Toutes les journées » et le libellé du bouton avec l'état serveur.
    this.apply(numbers.length > 0 ? numbers : this.selected)
  }

  // ── Ouverture / fermeture du menu ───────────────────────────────────────────

  toggle() {
    if (this.menuTarget.hidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.boundClose)
  }

  close() {
    this.menuTarget.hidden = true
    this.toggleTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.boundClose)
  }

  // "Ailleurs" = en dehors du picker (bouton + menu) précisément, pas de tout
  // le round-ribbon : celui-ci contient aussi les cartes de match affichées
  // (liens vers les profils, boutons de score...), qu'un clic doit fermer le
  // menu sans jamais intercepter (pas de preventDefault/stopPropagation ici,
  // la navigation Turbo suit son cours normalement).
  closeOnOutsideClick(event) {
    if (!this.pickerTarget.contains(event.target)) this.close()
  }
}
