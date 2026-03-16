// Controller Stimulus pour le chat sticky global
// Rôles :
//   1. Ouvrir / fermer le panneau
//   2. Changer l'icône du bouton
//   3. Mettre en surbrillance la conversation active dans la sidebar
//   4. Afficher / masquer le badge de notification sur le bouton

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "panel",     // div.sticky-chat-panel
    "button",    // bouton rond vert
    "iconOpen",  // icône message-circle (état fermé)
    "iconClose", // icône x (état ouvert)
    "badge"      // petit rond vert "à cheval" sur le bouton (badge non-lu)
  ]

  connect() {
    this.isOpen = false

    // Options de l'observer stockées pour pouvoir reconnecter après lucide.createIcons()
    this._observerOptions = {
      subtree: true,       // surveille tous les descendants
      childList: true,     // détecte ajouts/suppressions de nœuds
      attributes: true,    // détecte changements d'attributs (ex: display)
      attributeFilter: ["style", "class"]
    }

    // Vérifie immédiatement si des messages non lus existent dans la sidebar
    this.updateBadge()

    // MutationObserver : surveille les changements dans le container
    // (Turbo Streams ajoutent/retirent des .sticky-chat-unread-dot en temps réel)
    this._observer = new MutationObserver((mutations) => {
      this.updateBadge()

      // Si Turbo Stream a injecté de nouveaux nœuds (ex: item sidebar remplacé),
      // il faut ré-initialiser Lucide — les nouveaux <i data-lucide="..."> ne sont
      // pas convertis en SVG automatiquement après un remplacement Turbo Stream
      const hasNewNodes = mutations.some(m => m.addedNodes.length > 0)
      if (hasNewNodes && typeof lucide !== "undefined") {
        // IMPORTANT : on déconnecte l'observer AVANT d'appeler lucide.createIcons()
        // car createIcons() remplace les <i> par des <svg>, ce qui ajouterait de nouveaux
        // nœuds et déclencherait une boucle infinie → page freeze
        this._observer.disconnect()
        lucide.createIcons()
        // On reconnecte l'observer après la mise à jour des icônes
        this._observer.observe(this.element, this._observerOptions)
      }
    })
    this._observer.observe(this.element, this._observerOptions)
  }

  disconnect() {
    // Nettoyage : on arrête l'observation quand le controller est détruit
    if (this._observer) this._observer.disconnect()
  }

  // ── Mettre à jour la visibilité du badge sur le bouton ────────────────────
  // Le badge est visible s'il existe au moins un .sticky-chat-unread-dot
  // dans la liste des conversations (ET que le panneau est fermé)
  updateBadge() {
    if (!this.hasBadgeTarget) return

    // Cherche s'il existe des points de notification dans la sidebar
    const hasUnread = this.element.querySelectorAll(".sticky-chat-unread-dot").length > 0

    // Affiche le badge seulement si panneau fermé ET messages non lus
    this.badgeTarget.style.display = (hasUnread && !this.isOpen) ? "block" : "none"
  }

  // ── Basculer ouvert / fermé ──────────────────────────────────────────────
  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  // ── Ouvrir le panneau ─────────────────────────────────────────────────────
  open() {
    this.setState(true)
  }

  // ── Fermer le panneau ─────────────────────────────────────────────────────
  close() {
    this.setState(false)
  }

  // ── Applique l'état ouvert/fermé (évite la duplication entre open et close) ──
  setState(isOpen) {
    this.isOpen = isOpen
    // Ajoute ou retire la classe CSS selon l'état
    this.panelTarget.classList.toggle("sticky-chat-panel--open", isOpen)
    this.updateIcons(isOpen)
    // Réinitialise les icônes Lucide dans le panneau après ouverture
    if (isOpen && typeof lucide !== "undefined") lucide.createIcons()
    // Met à jour le badge (caché si ouvert, visible si fermé + non-lus)
    this.updateBadge()
  }

  // ── Met à jour l'icône du bouton (message-circle ↔ croix) ─────────────────
  updateIcons(isOpen) {
    if (this.hasIconOpenTarget)  this.iconOpenTarget.style.display  = isOpen ? "none"  : "block"
    if (this.hasIconCloseTarget) this.iconCloseTarget.style.display = isOpen ? "block" : "none"
  }

  // ── Sélectionner une conversation (highlight dans la sidebar) ─────────────
  // Appelé par data-action="click->sticky-chat#selectConvo" sur chaque lien
  selectConvo(event) {
    // Retire la classe active sur tous les liens de conversation
    this.element.querySelectorAll(".sticky-chat-convo-link").forEach(link => {
      link.classList.remove("sticky-chat-convo-link--active")
    })
    // Ajoute la classe active sur le lien cliqué
    event.currentTarget.classList.add("sticky-chat-convo-link--active")
  }
}
