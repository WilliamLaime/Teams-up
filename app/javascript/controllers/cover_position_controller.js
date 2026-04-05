// cover_position_controller.js
// Permet à l'utilisateur de repositionner manuellement l'image de bannière
// en la glissant dans un aperçu interactif.
//
// Fonctionnement :
// - L'aperçu affiche l'image avec object-fit:cover
// - En glissant la souris (ou le doigt) sur l'aperçu, on déplace l'image
//   en faisant varier object-position (X% Y%)
// - La valeur est stockée dans un champ caché soumis avec le formulaire

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles HTML pilotées par ce controller
  static targets = [
    "preview",        // Div conteneur de l'aperçu (avec overflow:hidden)
    "image",          // L'élément <img> dans l'aperçu
    "positionInput",  // Champ caché qui recevra la valeur "X% Y%"
    "hint"            // Texte d'indication affiché sous l'aperçu
  ]

  // Valeurs passées depuis l'HTML
  static values = {
    // Position initiale au chargement (ex: "60% 30%" ou "50% 50%" par défaut)
    initial: { type: String, default: "50% 50%" }
  }

  connect() {
    // Coordonnées de position actuelles (0-100)
    const parts = this.initialValue.split(" ")
    this.posX = parseFloat(parts[0]) || 50
    this.posY = parseFloat(parts[1]) || 50

    // État du drag
    this.isDragging  = false
    this.startMouseX = 0
    this.startMouseY = 0
    this.startPosX   = this.posX
    this.startPosY   = this.posY

    // Applique la position initiale à l'image
    this._applyPosition()

    // Liaison des événements souris et touch (conserve le contexte this)
    this._onMouseDown  = this._startDrag.bind(this)
    this._onMouseMove  = this._drag.bind(this)
    this._onMouseUp    = this._stopDrag.bind(this)
    this._onTouchStart = this._startDragTouch.bind(this)
    this._onTouchMove  = this._dragTouch.bind(this)
    this._onTouchEnd   = this._stopDrag.bind(this)

    // Écoute les événements sur l'aperçu
    this.previewTarget.addEventListener("mousedown",  this._onMouseDown)
    this.previewTarget.addEventListener("touchstart", this._onTouchStart, { passive: false })
    document.addEventListener("mousemove",  this._onMouseMove)
    document.addEventListener("mouseup",    this._onMouseUp)
    document.addEventListener("touchmove",  this._onTouchMove, { passive: false })
    document.addEventListener("touchend",   this._onTouchEnd)
  }

  disconnect() {
    // Nettoyage des écouteurs pour éviter les fuites mémoire
    this.previewTarget.removeEventListener("mousedown",  this._onMouseDown)
    this.previewTarget.removeEventListener("touchstart", this._onTouchStart)
    document.removeEventListener("mousemove",  this._onMouseMove)
    document.removeEventListener("mouseup",    this._onMouseUp)
    document.removeEventListener("touchmove",  this._onTouchMove)
    document.removeEventListener("touchend",   this._onTouchEnd)
  }

  // ── Drag souris ──────────────────────────────────────────────────────────────

  _startDrag(event) {
    event.preventDefault()
    this.isDragging  = true
    this.startMouseX = event.clientX
    this.startMouseY = event.clientY
    this.startPosX   = this.posX
    this.startPosY   = this.posY
    this.previewTarget.style.cursor = "grabbing"
  }

  _drag(event) {
    if (!this.isDragging) return
    this._updatePosition(event.clientX, event.clientY)
  }

  // ── Drag touch ───────────────────────────────────────────────────────────────

  _startDragTouch(event) {
    event.preventDefault()
    const touch       = event.touches[0]
    this.isDragging   = true
    this.startMouseX  = touch.clientX
    this.startMouseY  = touch.clientY
    this.startPosX    = this.posX
    this.startPosY    = this.posY
  }

  _dragTouch(event) {
    if (!this.isDragging) return
    event.preventDefault()
    const touch = event.touches[0]
    this._updatePosition(touch.clientX, touch.clientY)
  }

  _stopDrag() {
    if (!this.isDragging) return
    this.isDragging = false
    this.previewTarget.style.cursor = "grab"
  }

  // ── Calcul de la nouvelle position ───────────────────────────────────────────

  // Convertit le delta de souris en delta de % et applique les limites 0-100
  _updatePosition(clientX, clientY) {
    const rect = this.previewTarget.getBoundingClientRect()

    // Sensibilité : déplacer de toute la largeur de l'aperçu = 100% de variation
    const deltaX = ((this.startMouseX - clientX) / rect.width)  * 100
    const deltaY = ((this.startMouseY - clientY) / rect.height) * 100

    // Clamp entre 0 et 100
    this.posX = Math.min(100, Math.max(0, this.startPosX + deltaX))
    this.posY = Math.min(100, Math.max(0, this.startPosY + deltaY))

    this._applyPosition()
  }

  // ── Mise à jour du DOM et du champ caché ─────────────────────────────────────

  _applyPosition() {
    const value = `${Math.round(this.posX)}% ${Math.round(this.posY)}%`

    // Met à jour le style de l'image dans l'aperçu
    if (this.hasImageTarget) {
      this.imageTarget.style.objectPosition = value
    }

    // Stocke la valeur dans le champ caché
    if (this.hasPositionInputTarget) {
      this.positionInputTarget.value = value
    }
  }
}
