import { Controller } from "@hotwired/stimulus"

// Contrôleur Stimulus pour la modale de notifications.
// Permet de marquer toutes les notifications comme lues sans quitter la page
// et sans fermer le dropdown Bootstrap.
export default class extends Controller {

  // Cibles DOM que ce contrôleur va manipuler :
  //   markAllBtn  → le bouton "Tout lire"
  static targets = ["markAllBtn"]

  // Appelé quand le formulaire "Tout lire" est soumis
  markAllRead(event) {
    // Empêche la navigation habituelle (redirige vers /notifications)
    event.preventDefault()

    // Récupère l'URL du formulaire (générée par button_to dans le partial)
    const form = event.target
    const url  = form.action

    // Jeton CSRF obligatoire pour les requêtes PATCH avec Rails
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
        // Succès : met à jour l'interface sans fermer le dropdown
        this.#updateUI()
      }
    })
    .catch(error => {
      console.error("Erreur lors du marquage comme lu :", error)
    })
  }

  // Empêche le click de remonter jusqu'au gestionnaire Bootstrap
  // qui fermerait le dropdown en voyant un click à l'intérieur
  stopClickPropagation(event) {
    event.stopPropagation()
  }

  // Appelé quand le formulaire de suppression (poubelle) est soumis
  deleteNotif(event) {
    // Empêche la navigation habituelle (redirige vers /notifications)
    event.preventDefault()

    const form  = event.target
    const url   = form.action
    const token = document.querySelector('meta[name="csrf-token"]').content

    // Trouve le wrapper de la notification (parent du bouton poubelle)
    // pour le supprimer du DOM après succès
    const wrapper = form.closest(".notif-item-wrapper")

    // Envoie la requête DELETE en arrière-plan
    fetch(url, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": token,
        "Accept": "application/json"
      }
    })
    .then(response => {
      if (response.ok) {
        // Supprime la notification du DOM sans fermer le dropdown
        wrapper?.remove()

        // Met à jour le badge (décrémente de 1 si la notif était non lue)
        this.#updateBadge()

        // Si plus aucune notification dans la liste, affiche l'état vide
        this.#checkEmptyState()
      }
    })
    .catch(error => {
      console.error("Erreur lors de la suppression :", error)
    })
  }

  // ─── Méthodes privées ──────────────────────────────────────────────────────

  // Recompte les non lues restantes et met à jour (ou supprime) le badge
  #updateBadge() {
    const badge = document.querySelector("#notifDropdown .badge")
    if (!badge) return

    // Compte les wrappers non lus encore présents dans le dropdown
    const remaining = this.element.querySelectorAll(".notif-unread-item").length

    if (remaining === 0) {
      // Plus de non lues → supprime le badge et le bouton "Tout lire"
      badge.remove()
      if (this.hasMarkAllBtnTarget) {
        this.markAllBtnTarget.closest("form")?.remove()
      }
    } else {
      // Met à jour le compteur dans le badge
      badge.textContent = remaining
    }
  }

  // Affiche le message "Aucune notification" si la liste est vide
  #checkEmptyState() {
    const list = this.element.querySelector(".notif-list")
    if (!list) return

    const items = list.querySelectorAll(".notif-item-wrapper")
    if (items.length === 0) {
      // Remplace la liste par le message vide
      list.outerHTML = `
        <div class="text-center py-3" style="color:var(--theme-text-muted);">
          <i data-lucide="inbox" style="width:22px;height:22px;"></i>
          <div class="small mt-1">Aucune notification</div>
        </div>
      `
      // Re-initialise Lucide pour afficher l'icône inbox
      if (window.lucide) window.lucide.createIcons()
    }
  }

  // ─── Méthode privée : mise à jour visuelle après "Tout lire" ──────────────
  #updateUI() {
    // 1. Supprime le badge rouge sur la cloche (en dehors du dropdown-menu)
    //    Le badge est dans le bouton #notifDropdown, on le cherche dans tout le doc
    const badge = document.querySelector("#notifDropdown .badge")
    if (badge) badge.remove()

    // 2. Supprime le bouton "Tout lire" (et son formulaire parent)
    if (this.hasMarkAllBtnTarget) {
      const form = this.markAllBtnTarget.closest("form")
      if (form) form.remove()
    }

    // 3. Met à jour chaque notification non lue visuellement
    //    On utilise querySelectorAll sur le dropdown-menu (this.element)
    //    pour trouver tous les wrappers avec la classe "notif-unread-item"
    this.element.querySelectorAll(".notif-unread-item").forEach(item => {

      // Remplace l'icône bell-dot (non lue) par check-circle (lue)
      const icon = item.querySelector("[data-lucide='bell-dot']")
      if (icon) {
        icon.setAttribute("data-lucide", "check-circle")
        icon.style.color = "var(--theme-text-muted)" // Icône discrète selon le thème
        icon.classList.remove("text-primary")
      }

      // Retire le fond vert de la notification (classe CSS "unread")
      const btn = item.querySelector(".notif-item")
      if (btn) btn.classList.remove("unread")

      // Passe le texte en grisé (même style que les notifications déjà lues)
      const msgDiv = item.querySelector(".notif-msg")
      if (msgDiv) {
        msgDiv.style.color = "var(--theme-text-muted)" // Texte atténué selon le thème
        msgDiv.classList.remove("fw-semibold")
      }
    })

    // 4. Re-initialise Lucide pour afficher les nouvelles icônes check-circle
    if (window.lucide) {
      window.lucide.createIcons()
    }
  }
}
