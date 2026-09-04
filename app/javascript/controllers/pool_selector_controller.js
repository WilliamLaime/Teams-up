import { Controller } from "@hotwired/stimulus"

// Sélecteur de poules de l'onglet Matchs (cf. _pool_phase.html.erb) : des onglets
// ARIA qui basculent la visibilité des panneaux .pool-view, plus un bouton qui
// masque/affiche la colonne de classement.
//
// Deux états, tous deux MÉMORISÉS en sessionStorage :
//   • la poule affichée ;
//   • la présence du classement (quand il est masqué, les confrontations se
//     répartissent sur plus de colonnes — cf. .pool-view--full).
//
// Pourquoi mémoriser — chaque saisie de score répond par un
// turbo_stream.update("tournament_board") (cf. TournamentMatchesController
// #render_board) qui re-rend TOUT le board : sans mémoire, l'organisateur qui
// saisit les résultats de la poule C serait renvoyé sur la poule A (ou sur la
// sienne) à chaque score validé. Le contrôleur étant ré-instancié à chaque
// remplacement du DOM, `connect()` est exactement le moment où réappliquer l'état
// choisi par-dessus la présélection serveur. Même mécanique que
// journee_selector_controller.
//
// Clé par tournoi : deux tournois ouverts dans le même onglet ne se marchent pas
// sur les pieds.
export default class extends Controller {
  static targets = ["chip", "panel", "standings", "standingsToggle", "standingsLabel"]
  static values = { storageKey: String }

  connect() {
    this.restore()
  }

  // ── Choix de la poule ───────────────────────────────────────────────────────

  choose(event) {
    this.select(event.currentTarget.dataset.poolIndex)
    this.persist()
  }

  // Navigation aux flèches entre onglets, attendue du motif tablist (le clavier
  // ne doit pas obliger à tabuler à travers toutes les cartes d'une poule pour
  // atteindre la poule suivante).
  navigate(event) {
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key]
    if (!step) return

    event.preventDefault()
    const chips = this.chipTargets
    const current = chips.indexOf(event.currentTarget)
    // Modulo positif : reculer depuis le premier onglet revient au dernier.
    const next = chips[(current + step + chips.length) % chips.length]

    this.select(next.dataset.poolIndex)
    next.focus()
    this.persist()
  }

  // Bascule pure (aucune écriture en sessionStorage) : partagée par le clic, les
  // flèches et la restauration, pour que les trois chemins produisent le même état.
  select(poolIndex) {
    this.chipTargets.forEach((chip) => {
      const active = chip.dataset.poolIndex === poolIndex
      chip.setAttribute("aria-selected", active)
      // Roving tabindex : un seul onglet dans l'ordre de tabulation, les autres
      // s'atteignent aux flèches.
      chip.tabIndex = active ? 0 : -1
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.poolIndex !== poolIndex
    })
  }

  get selected() {
    const active = this.chipTargets.find((chip) => chip.getAttribute("aria-selected") === "true")
    return active ? active.dataset.poolIndex : null
  }

  // ── Colonne de classement ───────────────────────────────────────────────────

  toggleStandings() {
    this.showStandings(!this.standingsVisible)
    this.persist()
  }

  showStandings(visible) {
    this.standingsVisible = visible
    // La classe vit sur les PANNEAUX (pas sur le contrôleur) : c'est .pool-view
    // qui porte la grille « matchs | classement », donc c'est elle qui doit passer
    // en pleine largeur.
    this.panelTargets.forEach((panel) => panel.classList.toggle("pool-view--full", !visible))
    this.standingsTargets.forEach((aside) => { aside.hidden = !visible })

    if (this.hasStandingsToggleTarget) {
      this.standingsToggleTarget.setAttribute("aria-pressed", visible)
    }
    if (this.hasStandingsLabelTarget) {
      this.standingsLabelTarget.textContent = visible ? "Masquer le classement" : "Afficher le classement"
    }
  }

  // ── Persistance ─────────────────────────────────────────────────────────────

  persist() {
    if (!this.storageKeyValue) return

    sessionStorage.setItem(this.storageKeyValue, JSON.stringify({
      pool: this.selected,
      standings: this.standingsVisible
    }))
  }

  restore() {
    const stored = this.read()

    // Une poule mémorisée peut avoir disparu (tournoi régénéré, poules
    // reconstituées) : on ne la rejoue que si son onglet existe encore, sinon on
    // garde la présélection du serveur — ma poule, ou la première — qui est juste.
    const known = this.chipTargets.some((chip) => chip.dataset.poolIndex === stored.pool)
    if (known) this.select(stored.pool)

    // Le classement est visible par défaut côté serveur ; on ne le masque que si
    // l'utilisateur l'avait explicitement fermé.
    this.showStandings(stored.standings !== false)
  }

  read() {
    if (!this.storageKeyValue) return {}

    try {
      return JSON.parse(sessionStorage.getItem(this.storageKeyValue)) || {}
    } catch {
      // sessionStorage corrompu ou format d'une version précédente : on repart de
      // la présélection serveur plutôt que de casser tout le sélecteur.
      return {}
    }
  }
}
