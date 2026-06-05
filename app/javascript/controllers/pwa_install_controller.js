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
    // Lit le prompt capturé globalement dans application.js (résiste aux reconnexions Turbo).
    // beforeinstallprompt ne se déclenche qu'une seule fois par session, donc on ne peut pas
    // se fier à un écouteur local qui serait réinitialisé à chaque navigation Turbo.
    this.installPrompt = window._pwaInstallPrompt || null

    // Instance Bootstrap Modal
    this.bsModal = null

    this.boundBeforeInstall = this.onBeforeInstallPrompt.bind(this)
    this.boundAppInstalled  = this.onAppInstalled.bind(this)
    this.boundModalShow     = this.onModalShow.bind(this)

    window.addEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.addEventListener("appinstalled",        this.boundAppInstalled)

    // Écoute l'ouverture Bootstrap de la modale — permet au bouton du drawer mobile
    // d'ouvrir la modale directement (data-bs-toggle) tout en déclenchant la logique
    // d'état (iOS / Chrome / déjà installé).
    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("show.bs.modal", this.boundModalShow)
    }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.removeEventListener("appinstalled",        this.boundAppInstalled)
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener("show.bs.modal", this.boundModalShow)
    }
  }

  // Appelé par le navigateur quand l'app est prête à être installée (Chrome/Edge)
  onBeforeInstallPrompt(event) {
    // Empêche Chrome d'afficher son propre prompt automatiquement
    event.preventDefault()
    // Sauvegarde dans l'instance ET globalement (pour survivre aux reconnexions Turbo)
    this.installPrompt = event
    window._pwaInstallPrompt = event
  }

  // Appelé automatiquement par Bootstrap à l'ouverture de la modale (quelle que soit la source)
  onModalShow() {
    const isAlreadyInstalled = window.matchMedia("(display-mode: standalone)").matches
    if (isAlreadyInstalled) {
      this.showAlreadyInstalledView()
    } else {
      this.showInstallView()
    }
    if (window.lucide) window.lucide.createIcons()
  }

  // Détecte si l'utilisateur est sur iOS (Safari ne supporte pas beforeinstallprompt)
  isIos() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
           (navigator.userAgent.includes("Mac") && "ontouchend" in document)
  }

  // Appelé au clic sur le bouton navbar — l'état est initialisé par onModalShow (show.bs.modal)
  openModal() {
    if (!this.hasModalTarget) return

    if (!this.bsModal) {
      this.bsModal = new bootstrap.Modal(this.modalTarget)
    }

    this.bsModal.show()
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

    // L'événement ne peut être utilisé qu'une seule fois, on vide l'instance ET le global
    this.installPrompt = null
    window._pwaInstallPrompt = null
  }

  // Appelé quand l'app vient d'être installée avec succès
  onAppInstalled() {
    this.installPrompt = null
    window._pwaInstallPrompt = null
    if (this.bsModal) this.bsModal.hide()
  }
}
