import { Controller } from "@hotwired/stimulus"

// Contrôleur Stimulus pour la PAGE des notifications (/notifications).
// Permet de marquer toutes les notifications comme lues sans recharger la page.
export default class extends Controller {

  // Cibles DOM :
  //   markAllBtn → le bouton "Tout lire"
  //   badge      → le compteur "X non lues" dans le titre
  static targets = ["markAllBtn", "badge"]

  // Appelé quand le formulaire "Tout lire" est soumis
  markAllRead(event) {
    // Empêche la navigation habituelle (redirige vers /notifications)
    event.preventDefault()

    const form  = event.target
    const url   = form.action
    const token = document.querySelector('meta[name="csrf-token"]').content

    // Envoie la requête PATCH en arrière-plan, sans recharger la page
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": token,
        "Accept": "application/json"
      }
    })
    .then(response => {
      if (response.ok) {
        this.#updateUI()
      }
    })
    .catch(error => {
      console.error("Erreur lors du marquage comme lu :", error)
    })
  }

  // ─── Méthode privée : mise à jour visuelle ────────────────────────────────
  #updateUI() {
    // 1. Supprime le badge "X non lues" dans le titre
    if (this.hasBadgeTarget) this.badgeTarget.remove()

    // 2. Supprime le bouton "Tout lire"
    if (this.hasMarkAllBtnTarget) {
      this.markAllBtnTarget.closest("form")?.remove()
    }

    // 3. Met à jour chaque notification non lue visuellement
    this.element.querySelectorAll(".notif-page-item.is-unread").forEach(btn => {

      // Passe la classe de "non lue" à "lue"
      btn.classList.remove("is-unread")
      btn.classList.add("is-read")

      // Remplace l'icône bell-dot par check-circle
      const icon = btn.querySelector("[data-lucide='bell-dot']")
      if (icon) {
        icon.setAttribute("data-lucide", "check-circle")
        icon.style.color = "rgba(255,255,255,0.3)"
        icon.classList.remove("text-primary")
      }

      // Passe le texte du message en style "lu"
      const msg = btn.querySelector(".notif-page-message")
      if (msg) {
        msg.classList.remove("unread")
        msg.classList.add("read")
      }

      // Supprime le point vert "nouveau"
      const dot = btn.querySelector(".notif-page-dot")
      if (dot) dot.remove()
    })

    // 4. Re-initialise Lucide pour afficher les nouvelles icônes check-circle
    if (window.lucide) window.lucide.createIcons()
  }
}
