// Controller Stimulus pour le chat global (modale navbar)
// Rôles :
//   1. Switcher les onglets Matchs / Messages (pas Bootstrap Tab — conflit turbo-permanent)
//   2. Mettre à jour le badge vert sur l'icône navbar après chaque navigation Turbo
//   3. Mettre à jour les badges verts sur chaque onglet
//   4. Mettre en surbrillance la conversation active dans la sidebar
//   5. Ré-initialiser les icônes Lucide après les mises à jour Turbo Stream
//   6. Ouvrir automatiquement la modale si un trigger broadcast est reçu

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    // Badge initial au chargement de la page
    this.updateBadge()

    // Après chaque navigation Turbo, la navbar est recréée dans le DOM.
    // Le badge #chat-navbar-badge repart à display:none → il faut le remettre à jour.
    // On stocke la référence pour pouvoir l'enlever dans disconnect().
    this._handleTurboRender = () => this.updateBadge()
    document.addEventListener("turbo:render", this._handleTurboRender)

    // Options de l'observer stockées pour pouvoir reconnecter après lucide.createIcons()
    this._observerOptions = {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["style", "class"]
    }

    // MutationObserver : surveille les changements dans le container
    // (Turbo Streams ajoutent/retirent des .sticky-chat-unread-dot en temps réel)
    this._observer = new MutationObserver((mutations) => {
      this.updateBadge()

      // Vérifie si le trigger d'ouverture auto a été activé
      const trigger = document.getElementById("sticky-chat-open-trigger")
      if (trigger && trigger.textContent.trim() !== "") {
        const modal = document.getElementById("global-chat-modal")
        if (modal && typeof bootstrap !== "undefined") {
          bootstrap.Modal.getOrCreateInstance(modal).show()
        }
        trigger.textContent = ""
      }

      // Si Turbo Stream a injecté de nouveaux nœuds, ré-initialise Lucide
      const hasNewNodes = mutations.some(m => m.addedNodes.length > 0)
      if (hasNewNodes && typeof lucide !== "undefined") {
        // Déconnecte d'abord pour éviter la boucle infinie (createIcons → mutation → createIcons…)
        this._observer.disconnect()
        lucide.createIcons()
        this._observer.observe(this.element, this._observerOptions)
      }
    })
    this._observer.observe(this.element, this._observerOptions)

    // Ré-initialise Lucide quand la modale s'ouvre
    const modal = document.getElementById("global-chat-modal")
    if (modal) {
      modal.addEventListener("shown.bs.modal", () => {
        if (typeof lucide !== "undefined") lucide.createIcons()
      })
    }
  }

  disconnect() {
    if (this._observer) this._observer.disconnect()
    // Retire le listener turbo:render pour éviter les fuites mémoire
    document.removeEventListener("turbo:render", this._handleTurboRender)
  }

  // ── Switcher entre les onglets Matchs et Messages ─────────────────────────
  // Appelé par data-action="click->sticky-chat#switchTab" sur chaque bouton onglet.
  // On gère tout manuellement car Bootstrap Tab entre en conflit avec data-turbo-permanent.
  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab // "matchs" ou "messages"

    // Met à jour la classe "active" sur les boutons d'onglet
    this.element.querySelectorAll(".sticky-chat-tab").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.tab === tabName)
    })

    // Affiche le bon pane, cache les autres
    this.element.querySelectorAll(".sticky-chat-pane").forEach(pane => {
      pane.classList.toggle("sticky-chat-pane--active", pane.id === `tab-${tabName}`)
    })
  }

  // ── Mettre à jour tous les badges de notification ─────────────────────────
  // Appelé à l'init, après chaque mutation DOM et après chaque navigation Turbo.
  updateBadge() {
    // ── Badge onglet "Matchs" ──────────────────────────────────────────────
    const matchsPane = document.getElementById("tab-matchs")
    const hasUnreadMatchs = matchsPane
      ? matchsPane.querySelectorAll(".sticky-chat-unread-dot").length > 0
      : false

    const badgeMatchs = document.getElementById("badge-tab-matchs")
    if (badgeMatchs) badgeMatchs.style.display = hasUnreadMatchs ? "inline-block" : "none"

    // ── Badge onglet "Messages" ────────────────────────────────────────────
    const messagesPane = document.getElementById("tab-messages")
    const hasUnreadMessages = messagesPane
      ? messagesPane.querySelectorAll(".sticky-chat-unread-dot").length > 0
      : false

    const badgeMessages = document.getElementById("badge-tab-messages")
    if (badgeMessages) badgeMessages.style.display = hasUnreadMessages ? "inline-block" : "none"

    // ── Badge global sur l'icône navbar (#chat-navbar-badge) ──────────────
    // Visible dès qu'il y a des non-lus dans l'un ou l'autre onglet.
    // On requête par ID (pas de target Stimulus) car la navbar est en dehors
    // du scope de ce controller.
    const navBadge = document.getElementById("chat-navbar-badge")
    if (navBadge) {
      navBadge.style.display = (hasUnreadMatchs || hasUnreadMessages) ? "block" : "none"
    }
  }

  // ── Sélectionner une conversation (highlight dans la sidebar) ─────────────
  // Appelé par data-action="click->sticky-chat#selectConvo" sur chaque lien.
  selectConvo(event) {
    this.element.querySelectorAll(".sticky-chat-convo-link").forEach(link => {
      link.classList.remove("sticky-chat-convo-link--active")
    })
    event.currentTarget.classList.add("sticky-chat-convo-link--active")
  }
}
