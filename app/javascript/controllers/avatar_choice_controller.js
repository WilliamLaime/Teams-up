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

  // Valeur transmise depuis la vue : nom du preset soumis avant une erreur de formulaire
  // data-avatar-choice-previous-preset-value="01" par exemple
  static values = { previousPreset: String }

  // Appelé automatiquement par Stimulus quand le controller est attaché au DOM
  connect() {
    // Si un preset avait été sélectionné avant l'erreur, on le restaure
    if (this.previousPresetValue) {
      // Bascule sur l'onglet "Avatars" pour montrer la sélection
      this.switchPanel(false)

      // Trouve l'item correspondant dans la grille et le marque comme sélectionné
      const item = this.avatarItemTargets.find(
        el => el.dataset.avatarName === this.previousPresetValue
      )
      if (item) {
        item.classList.add("avatar-item-selected")

        // Affiche la grande preview de l'avatar restauré
        const src = item.dataset.avatarSrc
        if (src) {
          this.presetPreviewTarget.src = src
          this.presetPreviewTarget.style.display = "block"
          // Cache le placeholder (icône smile)
          this.presetPlaceholderTarget.style.display = "none"
        }
      }
    }
  }

  // Bascule vers le panneau "Ma photo"
  showPhoto() {
    this.switchPanel(true)
    // Vide le preset pour ne pas envoyer les deux
    this.presetInputTarget.value = ""
  }

  // Bascule vers le panneau "Avatars prédéfinis"
  showAvatars() {
    this.switchPanel(false)
    // Vide le fichier uploadé pour ne pas envoyer les deux
    this.fileInputTarget.value = ""
  }

  // Affiche/cache les panneaux et onglets selon le paramètre showPhoto
  // "flex" et non "block" pour conserver le centrage CSS (display: flex sur .auth-panel)
  switchPanel(showPhoto) {
    this.photoPanelTarget.style.display = showPhoto ? "flex" : "none"
    this.avatarPanelTarget.style.display = showPhoto ? "none" : "flex"
    // classList.toggle(classe, condition) ajoute si true, retire si false
    this.photoTabTarget.classList.toggle("auth-tab-active", showPhoto)
    this.avatarTabTarget.classList.toggle("auth-tab-active", !showPhoto)
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
