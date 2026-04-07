// cover_position_controller.js
// Permet à l'utilisateur de repositionner et zoomer l'image de bannière :
//   - Drag pour recadrer (object-position X% Y%)
//   - Slider de zoom (transform: scale)
//   - Aperçu live quand un nouveau fichier est sélectionné (FileReader)
//
// Les valeurs finales sont stockées dans deux champs cachés :
//   positionInput : "X% Y%"
//   zoomInput     : float (ex: 1.5)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles HTML pilotées par ce controller
  static targets = [
    "preview",        // Div conteneur de l'aperçu (avec overflow:hidden)
    "image",          // L'élément <img> dans l'aperçu
    "positionInput",  // Champ caché "X% Y%"
    "zoomInput",      // Champ caché zoom (float)
    "zoomSlider",     // Range input <input type="range"> pour le zoom
    "zoomValue",      // Texte affichant le zoom actuel (ex: "1.3×")
    "zoomRow",        // Ligne contenant le slider (affichée quand preview actif)
    "fileField"       // Input file pour la sélection d'une nouvelle image
  ]

  // Valeurs passées depuis le HTML via data-*-value
  static values = {
    initial:     { type: String, default: "50% 50%" },
    initialZoom: { type: Number, default: 1.0 }
  }

  connect() {
    // ─ Position courante (0-100 en %)
    const parts = this.initialValue.split(" ")
    this.posX = parseFloat(parts[0]) || 50
    this.posY = parseFloat(parts[1]) || 50

    // ─ Zoom courant (1.0 = pas de zoom, 2.0 = 2x)
    this.zoom = this.initialZoomValue || 1.0

    // ─ État du drag
    this.isDragging  = false
    this.startMouseX = 0
    this.startMouseY = 0
    this.startPosX   = this.posX
    this.startPosY   = this.posY

    // Applique la position et le zoom initiaux à l'image
    this._applyTransform()

    // Synchronise le slider de zoom avec la valeur initiale
    if (this.hasZoomSliderTarget) {
      this.zoomSliderTarget.value = this.zoom
    }
    this._updateZoomDisplay()

    // ─ Liaison des événements souris et touch (conserve le contexte this)
    this._onMouseDown  = this._startDrag.bind(this)
    this._onMouseMove  = this._drag.bind(this)
    this._onMouseUp    = this._stopDrag.bind(this)
    this._onTouchStart = this._startDragTouch.bind(this)
    this._onTouchMove  = this._dragTouch.bind(this)
    this._onTouchEnd   = this._stopDrag.bind(this)

    // Écoute les événements de drag sur l'aperçu
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

  // ── Aperçu live d'un nouveau fichier sélectionné ─────────────────────────────

  // Appelé quand l'user choisit une image via l'input file (action: "change->cover-position#previewFile")
  previewFile(event) {
    const file = event.target.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (e) => {
      // Affiche l'image dans le conteneur d'aperçu
      this.imageTarget.src = e.target.result
      this.imageTarget.style.display = "block"

      // Rend le conteneur d'aperçu visible
      this.previewTarget.style.display = "block"

      // Affiche le slider de zoom
      if (this.hasZoomRowTarget) this.zoomRowTarget.style.display = "flex"

      // Réinitialise la position au centre pour la nouvelle image
      this.posX = 50
      this.posY = 50
      this._applyTransform()
    }
    reader.readAsDataURL(file)
  }

  // ── Zoom ─────────────────────────────────────────────────────────────────────

  // Appelé quand l'user déplace le slider de zoom
  updateZoom(event) {
    this.zoom = parseFloat(event.target.value)
    this._applyTransform()
    this._updateZoomDisplay()
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

    // Sensibilité : déplacer sur toute la largeur = 100% de variation
    const deltaX = ((this.startMouseX - clientX) / rect.width)  * 100
    const deltaY = ((this.startMouseY - clientY) / rect.height) * 100

    // Clamp entre 0 et 100
    this.posX = Math.min(100, Math.max(0, this.startPosX + deltaX))
    this.posY = Math.min(100, Math.max(0, this.startPosY + deltaY))

    this._applyTransform()
  }

  // ── Application du transform à l'image ───────────────────────────────────────

  // Met à jour l'image (object-position + transform scale) et les champs cachés
  _applyTransform() {
    const posValue  = `${Math.round(this.posX)}% ${Math.round(this.posY)}%`
    const zoomValue = this.zoom || 1.0

    if (this.hasImageTarget) {
      // object-position pour le recadrage, transform pour le zoom
      // transform-origin calé sur le point focal pour un zoom naturel
      this.imageTarget.style.objectPosition = posValue
      this.imageTarget.style.transformOrigin = posValue
      this.imageTarget.style.transform = `scale(${zoomValue})`
    }

    // Stocke les valeurs dans les champs cachés soumis avec le formulaire
    if (this.hasPositionInputTarget) this.positionInputTarget.value = posValue
    if (this.hasZoomInputTarget)     this.zoomInputTarget.value     = zoomValue
  }

  // Met à jour le label textuel du zoom (ex: "1.3×")
  _updateZoomDisplay() {
    if (this.hasZoomValueTarget) {
      this.zoomValueTarget.textContent = (this.zoom || 1.0).toFixed(1) + "×"
    }
  }
}
