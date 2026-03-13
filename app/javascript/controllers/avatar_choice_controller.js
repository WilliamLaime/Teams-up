import { Controller } from "@hotwired/stimulus"

// Controller Stimulus pour gérer le choix entre photo personnelle et avatar prédéfini
export default class extends Controller {
  static targets = [
    "photoTab",        // Bouton onglet "Ma photo"
    "avatarTab",       // Bouton onglet "Avatars"
    "photoPanel",      // Panneau upload photo
    "avatarPanel",     // Panneau grille avatars
    "fileInput",       // Input file (photo personnelle)
    "presetInput",     // Input caché → nom du fichier preset choisi
    "avatarItem",      // Chaque miniature dans la grille
    "presetPreview",   // <img> qui affiche la grande preview de l'avatar sélectionné
    "presetPlaceholder" // Icône placeholder affiché avant toute sélection
  ]

  // Bascule vers le panneau "Ma photo"
  showPhoto() {
    // "flex" et non "block" pour conserver le centrage CSS (display: flex sur .auth-panel)
    this.photoPanelTarget.style.display = "flex"
    this.avatarPanelTarget.style.display = "none"

    this.photoTabTarget.classList.add("auth-tab-active")
    this.avatarTabTarget.classList.remove("auth-tab-active")

    // Vide le preset pour ne pas envoyer les deux
    this.presetInputTarget.value = ""
  }

  // Bascule vers le panneau "Avatars prédéfinis"
  showAvatars() {
    this.photoPanelTarget.style.display = "none"
    this.avatarPanelTarget.style.display = "flex"

    this.avatarTabTarget.classList.add("auth-tab-active")
    this.photoTabTarget.classList.remove("auth-tab-active")

    // Vide le fichier uploadé pour ne pas envoyer les deux
    this.fileInputTarget.value = ""
  }

  // Appelé quand l'utilisateur clique sur un avatar dans la grille
  selectAvatar(event) {
    const item = event.currentTarget

    // Retire le style "sélectionné" de tous les avatars
    this.avatarItemTargets.forEach(el => el.classList.remove("avatar-item-selected"))

    // Applique le style "sélectionné" sur celui cliqué
    item.classList.add("avatar-item-selected")

    // Stocke le nom du fichier dans l'input caché (ex: "01", "3", "12")
    this.presetInputTarget.value = item.dataset.avatarName

    // Affiche la grande preview de l'avatar sélectionné
    // data-avatar-src contient le chemin asset calculé côté Rails
    const src = item.dataset.avatarSrc
    if (src) {
      this.presetPreviewTarget.src = src
      this.presetPreviewTarget.style.display = "block"
      // Cache le placeholder (icône smile) maintenant qu'un avatar est choisi
      this.presetPlaceholderTarget.style.display = "none"
    }
  }
}
