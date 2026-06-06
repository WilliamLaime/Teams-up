// Controller Stimulus : gère le bouton "Installer l'app" PWA
//
// La modale (#pwaInstallModal) est placée en dehors du <nav> pour éviter le
// stacking context de sticky-top (z-index:1030) qui bloquerait le backdrop Bootstrap.
// Le controller accède donc à la modale et ses éléments internes par ID, pas par targets.
//
// Logique :
//   - Chrome/Edge : beforeinstallprompt capturé dans le layout → bouton actif
//   - iOS (Safari) : pas de prompt natif → instructions manuelles
//   - App déjà installée (mode standalone) → message "déjà installé"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Seul le bouton navbar est enfant du controller
  static targets = ["button"]

  // ── Accesseurs vers les éléments de la modale (hors scope du controller) ──
  get modal()              { return document.getElementById("pwaInstallModal") }
  get installView()        { return document.getElementById("pwaInstallView") }
  get alreadyInstalledView() { return document.getElementById("pwaAlreadyInstalledView") }
  get installBtn()         { return document.getElementById("pwaInstallBtn") }
  get iosInstructions()    { return document.getElementById("pwaIosInstructions") }

  connect() {
    // Récupère le prompt capturé tôt par le script inline du layout.
    // beforeinstallprompt ne se déclenche qu'une fois par session — on ne peut pas
    // se fier à un écouteur Stimulus qui est réinitialisé à chaque navigation Turbo.
    this.installPrompt = window._pwaInstallPrompt || null

    this.bsModal = null

    this.boundBeforeInstall = this.onBeforeInstallPrompt.bind(this)
    this.boundAppInstalled  = this.onAppInstalled.bind(this)
    this.boundInstallClick  = this.install.bind(this)
    this.boundModalShow     = this.onModalShow.bind(this)

    window.addEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.addEventListener("appinstalled",        this.boundAppInstalled)

    // Écoute l'ouverture Bootstrap (quelle que soit la source : bouton navbar ou drawer mobile)
    if (this.modal) {
      this.modal.addEventListener("show.bs.modal", this.boundModalShow)
    }

    // Le bouton "Installer" est hors scope Stimulus → on l'attache manuellement
    if (this.installBtn) {
      this.installBtn.addEventListener("click", this.boundInstallClick)
    }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.boundBeforeInstall)
    window.removeEventListener("appinstalled",        this.boundAppInstalled)
    if (this.modal)      this.modal.removeEventListener("show.bs.modal", this.boundModalShow)
    if (this.installBtn) this.installBtn.removeEventListener("click", this.boundInstallClick)
  }

  // Capturé par le layout en avance — ici en complément si l'event arrive après connect()
  onBeforeInstallPrompt(event) {
    event.preventDefault()
    this.installPrompt = event
    window._pwaInstallPrompt = event
  }

  // Déclenché par Bootstrap à l'ouverture de la modale (bouton navbar OU drawer mobile)
  onModalShow() {
    const isAlreadyInstalled = window.matchMedia("(display-mode: standalone)").matches
    if (isAlreadyInstalled) {
      this.showAlreadyInstalledView()
    } else {
      this.showInstallView()
    }
    if (window.lucide) window.lucide.createIcons()
  }

  isIos() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
           (navigator.userAgent.includes("Mac") && "ontouchend" in document)
  }

  // Clic sur le bouton navbar → ouvre la modale Bootstrap
  openModal() {
    if (!this.modal) return

    if (!this.bsModal) {
      this.bsModal = new bootstrap.Modal(this.modal)
    }

    this.bsModal.show()
  }

  showInstallView() {
    if (this.installView)          this.installView.style.display          = "block"
    if (this.alreadyInstalledView) this.alreadyInstalledView.style.display = "none"

    if (this.isIos()) {
      if (this.installBtn)      this.installBtn.style.display      = "none"
      if (this.iosInstructions) this.iosInstructions.style.display = "block"
    } else if (this.installPrompt) {
      if (this.installBtn)      this.installBtn.style.display      = ""
      if (this.iosInstructions) this.iosInstructions.style.display = "none"
    } else {
      // Navigateur non supporté ou prompt pas encore reçu
      if (this.installBtn) {
        this.installBtn.style.display  = ""
        this.installBtn.disabled       = true
        this.installBtn.style.opacity  = "0.4"
        this.installBtn.title          = "Installation non disponible sur ce navigateur"
      }
      if (this.iosInstructions) this.iosInstructions.style.display = "none"
    }
  }

  showAlreadyInstalledView() {
    if (this.installView)          this.installView.style.display          = "none"
    if (this.alreadyInstalledView) this.alreadyInstalledView.style.display = "block"
  }

  // Clic sur "Installer" → déclenche le prompt natif Chrome/Edge
  async install() {
    if (!this.installPrompt) return

    if (this.bsModal) this.bsModal.hide()

    await this.installPrompt.prompt()
    const { outcome } = await this.installPrompt.userChoice

    this.installPrompt = null
    window._pwaInstallPrompt = null
  }

  onAppInstalled() {
    this.installPrompt = null
    window._pwaInstallPrompt = null
    if (this.bsModal) this.bsModal.hide()
  }
}
