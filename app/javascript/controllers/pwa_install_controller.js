// Controller Stimulus : gère le bouton "Installer l'app" PWA
//
// Logique :
//   - Chrome/Edge : on attend l'événement "beforeinstallprompt" → bouton actif
//   - iOS (Safari) : pas de prompt natif → on affiche les instructions manuelles
//   - App déjà installée (mode standalone) → message "déjà installé"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Les "targets" sont les éléments HTML reliés au controller via data-pwa-install-target="..."
  static targets = ["button", "modal", "installView", "alreadyInstalledView", "installBtn", "iosInstructions"]

  connect() {
    // Stocke l'événement d'installation natif du navigateur (Chrome/Edge uniquement)
    this.installPrompt = null
    // Instance Bootstrap Modal
    this.bsModal = null

    // Écoute l'événement natif "beforeinstallprompt"
    // Il se déclenche quand l'app est installable (HTTPS + manifest valide + SW enregistré)
    this.boundBeforeInstall = this.onBeforeInstallPrompt.bind(this)
    this.boundAppInstalled  = this.onAppInstalled.bind(this)

    window.addEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.addEventListener("appinstalled",        this.boundAppInstalled)
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.removeEventListener("appinstalled",        this.boundAppInstalled)
  }

  // Appelé par le navigateur quand l'app est prête à être installée (Chrome/Edge)
  onBeforeInstallPrompt(event) {
    // Empêche Chrome d'afficher son propre prompt automatiquement
    event.preventDefault()
    // Sauvegarde l'événement pour l'utiliser quand l'utilisateur clique sur "Installer"
    this.installPrompt = event
  }

  // Détecte si l'utilisateur est sur iOS (Safari ne supporte pas beforeinstallprompt)
  isIos() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
           (navigator.userAgent.includes("Mac") && "ontouchend" in document)
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
      // L'app est déjà installée → affiche le message d'info
      this.showAlreadyInstalledView()
    } else {
      // L'app n'est pas encore installée → affiche la vue d'installation
      this.showInstallView()
    }

    this.bsModal.show()

    // Ré-initialise les icônes Lucide dans la modale (chargée dynamiquement)
    if (window.lucide) window.lucide.createIcons()
  }

  // Affiche la vue "installation disponible", adapte l'UI selon le navigateur
  showInstallView() {
    if (this.hasInstallViewTarget)          this.installViewTarget.style.display          = "block"
    if (this.hasAlreadyInstalledViewTarget) this.alreadyInstalledViewTarget.style.display = "none"

    if (this.isIos()) {
      // iOS : cacher le bouton natif, afficher les instructions manuelles
      if (this.hasInstallBtnTarget)        this.installBtnTarget.style.display        = "none"
      if (this.hasIosInstructionsTarget)   this.iosInstructionsTarget.style.display   = "block"
    } else if (this.installPrompt) {
      // Chrome/Edge avec prompt disponible : bouton actif, pas d'instructions iOS
      if (this.hasInstallBtnTarget)        this.installBtnTarget.style.display        = ""
      if (this.hasIosInstructionsTarget)   this.iosInstructionsTarget.style.display   = "none"
    } else {
      // Navigateur non supporté ou prompt pas encore reçu : bouton désactivé
      if (this.hasInstallBtnTarget) {
        this.installBtnTarget.style.display  = ""
        this.installBtnTarget.disabled       = true
        this.installBtnTarget.style.opacity  = "0.4"
        this.installBtnTarget.title          = "Installation non disponible sur ce navigateur"
      }
      if (this.hasIosInstructionsTarget) this.iosInstructionsTarget.style.display = "none"
    }
  }

  // Affiche la vue "déjà installé", cache la vue "installation"
  showAlreadyInstalledView() {
    if (this.hasInstallViewTarget)          this.installViewTarget.style.display          = "none"
    if (this.hasAlreadyInstalledViewTarget) this.alreadyInstalledViewTarget.style.display = "block"
  }

  // Appelé au clic sur "Installer" → déclenche le prompt natif Chrome/Edge
  async install() {
    // Si pas de prompt disponible, on ne fait rien (bouton désactivé visuellement)
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
    this.installPrompt = null
    if (this.bsModal) this.bsModal.hide()
  }
}
