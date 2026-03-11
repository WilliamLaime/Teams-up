// Stimulus controller pour le chat de match
// Rôles :
//   1. Auto-scroll vers le bas à chaque nouveau message
//   2. Appliquer le style "chat-message--mine" sur les messages de l'utilisateur connecté
//   3. Envoyer le message avec la touche Entrée
//   4. Gérer l'indicateur "X est en train d'écrire..." via ActionCable

import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  // Valeurs lues depuis les data-attributes HTML
  static values = {
    currentUserId: Number, // data-chat-current-user-id-value
    matchId: Number        // data-chat-match-id-value (sur le modal)
  }

  // Cibles HTML surveillées par ce controller
  static targets = ["messages", "input", "form", "submit", "typing", "typingName"]

  // Appelé quand le controller est connecté au DOM
  connect() {
    this.applyMineStyles()
    this.scrollToBottom()
    this.observeNewMessages()
  }

  // Appelé quand le controller est déconnecté (navigation, etc.)
  disconnect() {
    if (this.observer) this.observer.disconnect()
    if (this.subscription) this.subscription.unsubscribe()
    this.clearTypingTimeout()
  }

  // ── ActionCable : s'abonner au canal de frappe ──────────────────────────────

  // Appelé quand le modal Bootstrap est affiché (événement shown.bs.modal)
  onModalOpen() {
    this.scrollToBottom()
    if (this.hasInputTarget) this.inputTarget.focus()

    // On s'abonne au canal de frappe seulement quand le modal est ouvert
    // pour éviter des connexions inutiles si l'utilisateur ne l'ouvre jamais
    if (!this.subscription && this.hasMatchIdValue) {
      this.subscribeToTypingChannel()
    }
  }

  // Crée l'abonnement ActionCable au canal MatchChatChannel
  subscribeToTypingChannel() {
    const consumer = createConsumer()

    this.subscription = consumer.subscriptions.create(
      { channel: "MatchChatChannel", match_id: this.matchIdValue },
      {
        // Quand on reçoit un signal de frappe d'un autre utilisateur
        received: (data) => {
          // On n'affiche pas l'indicateur si c'est notre propre frappe
          if (data.user_id !== this.currentUserIdValue) {
            this.showTypingIndicator(data.user_name)
          }
        }
      }
    )
  }

  // Appelé à chaque frappe dans le champ de saisie (data-action="input->chat#onTyping")
  onTyping() {
    // Envoie le signal "typing" au serveur via ActionCable
    if (this.subscription) {
      this.subscription.perform("typing")
    }
  }

  // ── Indicateur de frappe ───────────────────────────────────────────────────

  showTypingIndicator(userName) {
    if (!this.hasTypingTarget) return

    // Met à jour le nom affiché et rend l'indicateur visible
    if (this.hasTypingNameTarget) this.typingNameTarget.textContent = userName
    this.typingTarget.style.display = "flex"

    // Réinitialise le timer : cache l'indicateur après 3 secondes sans signal
    this.clearTypingTimeout()
    this.typingTimeout = setTimeout(() => {
      this.typingTarget.style.display = "none"
    }, 3000)
  }

  clearTypingTimeout() {
    if (this.typingTimeout) clearTimeout(this.typingTimeout)
  }

  // ── Scroll et styles ───────────────────────────────────────────────────────

  // Observe les nouveaux messages ajoutés par Turbo Stream
  observeNewMessages() {
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            this.applyMineStyleTo(node)
          }
        })
      })
      this.scrollToBottom()
    })

    if (this.hasMessagesTarget) {
      this.observer.observe(this.messagesTarget, { childList: true })
    }
  }

  // Applique le style "mine" sur tous les messages existants
  applyMineStyles() {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.querySelectorAll(".chat-message").forEach((msg) => {
      this.applyMineStyleTo(msg)
    })
  }

  // Applique le style "mine" sur un seul message si l'auteur correspond
  applyMineStyleTo(element) {
    const userId = parseInt(element.dataset.userId, 10)
    if (userId === this.currentUserIdValue) {
      element.classList.remove("chat-message--theirs")
      element.classList.add("chat-message--mine")
      const senderName = element.querySelector(".chat-sender-name")
      if (senderName) senderName.style.display = "none"
    }
  }

  // Scroll vers le bas de la zone de messages
  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  // ── Raccourci clavier ──────────────────────────────────────────────────────

  // Envoie le message avec Entrée (sans Shift)
  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.querySelector("form").requestSubmit()
    }
  }
}
