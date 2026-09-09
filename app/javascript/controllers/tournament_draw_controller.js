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
//     jamais la composition des autres. L'overlay ne se ferme PAS de lui-même à la
//     fin : il attend un clic sur « Voir les poules ». C'est le seul écran qui
//     montre la composition complète du tirage, on laisse donc le temps de la lire.
//   • sinon → on « bat les cartes » de la première ronde puis on les révèle en
//     cascade (comportement historique, inchangé).
export default class extends Controller {
  static targets = ["overlay", "pool", "player", "skip", "continue"]

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

  // « Passer l'animation » : on saute le SUSPENSE, pas le résultat. Tout se révèle
  // d'un coup et l'overlay reste ouvert sur le tirage complet — sortir d'ici, c'est
  // le rôle du CTA et d'Échap. Une animation qu'on ne peut pas abréger bloquerait
  // l'accès au contenu (RGAA 13.8).
  skip(event) {
    event?.preventDefault()
    if (this.closed) return

    this.#clearTimers()
    this.poolTargets.forEach((pool) => pool.classList.add("draw-overlay__pool--revealed"))
    this.playerTargets.forEach((player) => player.classList.add("draw-overlay__player--revealed"))
    this.#finish()
  }

  // Bouton « Voir les poules », affiché quand l'animation est terminée. Même effet
  // que `skip` — deux noms parce que l'intention n'est pas la même côté vue.
  close(event) {
    event?.preventDefault()
    this.#closeOverlay()
  }

  // ── Formats à poules : révélation poule par poule ────────────────────────────
  #revealPools() {
    const overlay = this.overlayTarget
    overlay.hidden = false
    // Le focus part sur « Passer » : sans cela, il resterait sur le bouton de
    // lancement, désormais retiré du DOM, et se perdrait sur le <body>.
    this.#defer(() => { if (this.hasSkipTarget) this.skipTarget.focus() }, 0)

    // Échap ferme pour de bon : c'est la sortie de secours attendue d'un dialogue.
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

    // Fin de l'animation : on permute les boutons au lieu de fermer. La fermeture
    // devient une décision de l'utilisateur (ou Échap).
    this.#defer(() => this.#finish(), elapsed + 400)
  }

  // Le bouton « Passer » n'a plus rien à passer : il laisse la place au CTA, qui
  // reçoit le focus (il était sur « Passer », qu'on masque).
  #finish() {
    if (this.closed) return

    if (this.hasSkipTarget) this.skipTarget.hidden = true
    if (this.hasContinueTarget) {
      this.continueTarget.hidden = false
      this.continueTarget.focus()
    }
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
