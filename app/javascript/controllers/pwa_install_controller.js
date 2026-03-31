// Controller Stimulus : gère le bouton "Installer l'app" PWA
//
// Logique :
//   - Le bouton est TOUJOURS visible (desktop) pour permettre l'install sur plusieurs appareils
//   - Au clic, on détecte si l'app est déjà installée sur CET appareil :
//       → Oui : on affiche l'état "déjà installé" dans la modale
//       → Non : on affiche l'état "installation" et on déclenche le prompt Chrome

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "modal", "installView", "alreadyInstalledView"]

  connect() {
    // Stocke l'événement d'installation natif du navigateur
    this.installPrompt = null
    // Instance Bootstrap Modal
    this.bsModal = null

    // Écoute l'événement natif "beforeinstallprompt"
    // Il se déclenche quand l'app est installable ET pas encore installée sur cet appareil
    this.boundBeforeInstall = this.onBeforeInstallPrompt.bind(this)
    this.boundAppInstalled  = this.onAppInstalled.bind(this)

    window.addEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.addEventListener("appinstalled",        this.boundAppInstalled)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.removeEventListener("appinstalled",        this.boundAppInstalled)
  }

  // Appelé par le navigateur quand l'app est prête à être installée
  onBeforeInstallPrompt(event) {
    // Empêche Chrome d'afficher son propre prompt automatiquement
    event.preventDefault()
    // Sauvegarde l'événement pour l'utiliser plus tard
    this.installPrompt = event
  }

  // Appelé au clic sur le bouton navbar
  openModal() {
    if (!this.hasModalTarget) return

    // Initialise la Bootstrap Modal si ce n'est pas déjà fait
    if (!this.bsModal) {
      this.bsModal = new bootstrap.Modal(this.modalTarget)
    }

    // Détecte si l'app tourne déjà en mode standalone (= installée sur cet appareil)
    const isAlreadyInstalled = window.matchMedia("(display-mode: standalone)").matches

    if (isAlreadyInstalled) {
      // L'app est déjà installée sur cet appareil → affiche le message d'info
      this.showAlreadyInstalledView()
    } else if (this.installPrompt) {
      // L'app est installable → affiche la modale d'installation
      this.showInstallView()
    } else {
      // Le navigateur n'a pas encore déclenché beforeinstallprompt
      // (ex: Safari, Firefox, ou conditions non remplies)
      // On affiche quand même la modale d'installation avec le bouton grisé
      this.showInstallView()
    }

    this.bsModal.show()

    // Ré-initialise les icônes Lucide dans la modale (chargée dynamiquement)
    if (window.lucide) window.lucide.createIcons()
  }

  // Affiche la vue "installation disponible", cache la vue "déjà installé"
  showInstallView() {
    if (this.hasInstallViewTarget)          this.installViewTarget.style.display          = "block"
    if (this.hasAlreadyInstalledViewTarget) this.alreadyInstalledViewTarget.style.display = "none"
  }

  // Affiche la vue "déjà installé", cache la vue "installation"
  showAlreadyInstalledView() {
    if (this.hasInstallViewTarget)          this.installViewTarget.style.display          = "none"
    if (this.hasAlreadyInstalledViewTarget) this.alreadyInstalledViewTarget.style.display = "block"
  }

  // Appelé au clic sur "Installer" dans la modale → déclenche le prompt natif Chrome
  async install() {
    if (!this.installPrompt) return

    // Ferme notre modale avant d'afficher le prompt natif
    if (this.bsModal) this.bsModal.hide()

    // Affiche le prompt d'installation du navigateur
    await this.installPrompt.prompt()

    // Attend la décision de l'utilisateur
    const { outcome } = await this.installPrompt.userChoice

    // L'événement ne peut être utilisé qu'une seule fois, on le réinitialise
    this.installPrompt = null
  }

  // Appelé quand l'app vient d'être installée avec succès
  onAppInstalled() {
    // On réinitialise l'événement (plus besoin de l'installation)
    this.installPrompt = null
    if (this.bsModal) this.bsModal.hide()
  }
}
