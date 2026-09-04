import { Controller } from "@hotwired/stimulus"

// Animation de tirage au sort jouée au lancement d'un tournoi.
// Greffé (via le Turbo Stream de `start`, ou par `show` sur retour ?draw=1) sur le
// board en plus du contrôleur `bracket`. Il se retire lui-même à la fin :
// l'animation ne joue qu'une fois, jamais sur un simple rechargement.
//
// Deux mises en scène selon ce que le serveur a rendu :
//   • un overlay de poules est présent (formats à poules) → on révèle les poules
//     l'une après l'autre, avec leurs joueurs. Sur le board, les poules sont des
//     onglets dont une seule est visible : les animer en place ne montrerait
//     jamais la composition des autres.
//   • sinon → on « bat les cartes » de la première ronde puis on les révèle en
//     cascade (comportement historique, inchangé).
export default class extends Controller {
  static targets = ["overlay", "pool", "player"]

  connect() {
    this.timers = []

    // Respect de la préférence système : pas d'animation si mouvement réduit.
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#cleanup()
      return
    }

    if (this.hasOverlayTarget) {
      this.#revealPools()
      return
    }

    this.cards = Array.from(this.element.querySelectorAll(".tmatch-card"))
    if (this.cards.length === 0) {
      this.#cleanup()
      return
    }

    this.#shuffle()
  }

  disconnect() {
    this.#clearTimers()
  }

  // Sortie immédiate : bouton « Passer » et touche Échap. Une animation qu'on ne
  // peut pas interrompre bloquerait l'accès au contenu (RGAA 13.8).
  skip(event) {
    event?.preventDefault()
    this.#closeOverlay()
  }

  // ── Formats à poules : révélation poule par poule ────────────────────────────
  #revealPools() {
    const overlay = this.overlayTarget
    overlay.hidden = false
    // Le focus part sur « Passer » : sans cela, il resterait sur le bouton de
    // lancement, désormais retiré du DOM, et se perdrait sur le <body>.
    this.#defer(() => overlay.querySelector(".draw-overlay__skip")?.focus(), 0)

    this.escapeHandler = (event) => {
      if (event.key === "Escape") this.#closeOverlay()
    }
    document.addEventListener("keydown", this.escapeHandler)

    // Chaque poule apparaît, puis ses joueurs s'égrènent : c'est la révélation
    // successive qui donne au tirage sa valeur de suspense.
    const POOL_DELAY = 900
    const PLAYER_DELAY = 130
    let elapsed = 300

    this.poolTargets.forEach((pool) => {
      const players = Array.from(pool.querySelectorAll(".draw-overlay__player"))

      this.#defer(() => pool.classList.add("draw-overlay__pool--revealed"), elapsed)
      players.forEach((player, index) => {
        this.#defer(
          () => player.classList.add("draw-overlay__player--revealed"),
          elapsed + 200 + index * PLAYER_DELAY
        )
      })

      elapsed += POOL_DELAY + players.length * PLAYER_DELAY
    })

    this.#defer(() => this.#closeOverlay(), elapsed + 700)
  }

  #closeOverlay() {
    if (this.closed) return
    this.closed = true

    this.#clearTimers()
    if (this.escapeHandler) {
      document.removeEventListener("keydown", this.escapeHandler)
      this.escapeHandler = null
    }

    if (this.hasOverlayTarget) this.overlayTarget.remove()
    this.#cleanup()
  }

  // ── Autres formats : battage puis cascade sur les cartes du board ────────────
  // Phase 1 : les cartes tremblent brièvement (effet « battage »).
  #shuffle() {
    this.cards.forEach((card) => card.classList.add("tmatch-card--shuffling"))

    this.#defer(() => {
      this.cards.forEach((card) => card.classList.remove("tmatch-card--shuffling"))
      this.#reveal()
    }, 700)
  }

  // Phase 2 : révélation en cascade des appariements.
  #reveal() {
    this.cards.forEach((card, index) => {
      card.classList.add("tmatch-card--hidden")
      this.#defer(() => {
        card.classList.add("tmatch-card--revealed")
        card.classList.remove("tmatch-card--hidden")
      }, index * 120)
    })

    // Une fois la dernière carte révélée, on retire le contrôleur (nettoyage).
    this.#defer(() => this.#cleanup(), this.cards.length * 120 + 400)
  }

  // ── Utilitaires ──────────────────────────────────────────────────────────────
  // Tous les timers sont mémorisés pour être annulés à la sortie : sans cela, un
  // « Passer » (ou une navigation Turbo) laisserait la suite de l'animation
  // s'exécuter sur des nœuds déjà retirés.
  #defer(callback, delay) {
    this.timers.push(setTimeout(callback, delay))
  }

  #clearTimers() {
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers = []
  }

  // Retire l'attribut pour que l'animation ne rejoue pas (reconnexion Turbo, etc.).
  #cleanup() {
    if (this.hasOverlayTarget) this.overlayTarget.remove()

    const controllers = (this.element.getAttribute("data-controller") || "")
      .split(/\s+/)
      .filter((name) => name && name !== "tournament-draw")
    this.element.setAttribute("data-controller", controllers.join(" "))
  }
}
