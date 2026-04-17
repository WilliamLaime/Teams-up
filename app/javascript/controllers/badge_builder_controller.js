// badge_builder_controller.js
// Gère le générateur de blason SVG interactif sur le formulaire d'équipe.
// Options : 5 formes de fond, 16 couleurs, 24 symboles emoji, logo personnalisé redimensionnable.
import { Controller } from "@hotwired/stimulus"

// ── Formes disponibles ────────────────────────────────────────────────────────
// Chaque forme est définie par :
//   clip  : path SVG utilisé comme clipPath du fond coloré (null = cercle)
//   inner : chemin légèrement réduit pour la bordure intérieure (null = cercle)
const SHAPES = {
  shield: {
    clip:  "M50,3 L92,18 L92,58 C92,78 72,92 50,98 C28,92 8,78 8,58 L8,18 Z",
    inner: "M50,6 L89,20 L89,58 C89,76 70,89 50,95 C30,89 11,76 11,58 L11,20 Z"
  },
  hexagon: {
    clip:  "M50,5 L93,28 L93,72 L50,95 L7,72 L7,28 Z",
    inner: "M50,8 L90,29.5 L90,70.5 L50,92 L10,70.5 L10,29.5 Z"
  },
  circle: {
    clip:  null, // utilise un <circle> à la place
    inner: null
  },
  diamond: {
    clip:  "M50,3 L97,50 L50,97 L3,50 Z",
    inner: "M50,7 L93,50 L50,93 L7,50 Z"
  },
  pentagon: {
    clip:  "M50,5 L97,36 L79,92 L21,92 L3,36 Z",
    inner: "M50,8 L94,38 L77,89 L23,89 L6,38 Z"
  }
}

export default class extends Controller {
  static targets = [
    "preview",          // Div où le SVG live est rendu
    "svgInput",         // Champ caché qui contient le SVG final
    "logoInput",        // Input file pour le logo personnalisé
    "logoSlider",       // Range input pour la taille du logo personnalisé
    "logoScaleDisplay", // Affichage textuel de la taille (ex: "70%")
    "logoControls"      // Conteneur du slider (affiché seulement si logo chargé)
  ]

  connect() {
    // Valeurs par défaut
    this.selectedShape = "shield"
    this.selectedColor = "#1EDD88"
    this.selectedEmoji = "⚽"
    this.selectedLogoDataUrl = null  // null = utilise l'emoji, sinon Data URL base64

    // Taille du logo personnalisé dans le SVG (0.3 à 1.1, défaut 0.7)
    this.logoScale = 0.7

    this._renderSVG()
  }

  // ── Sélections ───────────────────────────────────────────────────────────────

  selectShape(event) {
    this.selectedShape = event.currentTarget.dataset.shape
    this.element.querySelectorAll(".badge-shape-btn").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  selectColor(event) {
    this.selectedColor = event.currentTarget.dataset.color
    this.element.querySelectorAll(".badge-color-swatch").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  selectIcon(event) {
    this.selectedEmoji = event.currentTarget.dataset.iconEmoji
    this.element.querySelectorAll(".badge-icon-btn").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  // ── Logo personnalisé ────────────────────────────────────────────────────────

  // Lit le fichier en base64 Data URL et l'intègre dans le SVG à la place de l'emoji
  selectLogo(event) {
    const file = event.target.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (e) => {
      this.selectedLogoDataUrl = e.target.result
      // Affiche le slider de taille
      if (this.hasLogoControlsTarget) this.logoControlsTarget.style.display = "flex"
      this._renderSVG()
    }
    reader.readAsDataURL(file)
  }

  // Ajuste la taille du logo dans le SVG
  updateLogoScale(event) {
    this.logoScale = parseFloat(event.target.value)
    if (this.hasLogoScaleDisplayTarget) {
      this.logoScaleDisplayTarget.textContent = Math.round(this.logoScale * 100) + "%"
    }
    this._renderSVG()
  }

  // Efface le logo et revient à l'emoji sélectionné
  clearLogo() {
    this.selectedLogoDataUrl = null
    this.logoScale = 0.7
    if (this.hasLogoInputTarget)        this.logoInputTarget.value = ""
    if (this.hasLogoSliderTarget)       this.logoSliderTarget.value = "0.7"
    if (this.hasLogoControlsTarget)     this.logoControlsTarget.style.display = "none"
    if (this.hasLogoScaleDisplayTarget) this.logoScaleDisplayTarget.textContent = "70%"
    this._renderSVG()
  }

  // ── Rendu SVG ────────────────────────────────────────────────────────────────

  _renderSVG() {
    const color = this.selectedColor
    const emoji = this.selectedEmoji
    const shape = SHAPES[this.selectedShape] || SHAPES.shield

    // ─ Fond : forme colorée + bordure interne semi-transparente
    // On utilise fill="${color}" directement (pas de gradient via url(#id)) pour éviter
    // que le sanitizer Rails supprime la définition et laisse la forme transparente.
    let bgElements = ""

    if (shape.clip) {
      bgElements = `
        <path d="${shape.clip}" fill="${color}"/>
        <path d="${shape.inner}" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
      `
    } else {
      // Cercle
      bgElements = `
        <circle cx="50" cy="50" r="46" fill="${color}"/>
        <circle cx="50" cy="50" r="43" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
      `
    }

    // ─ Symbole : logo uploadé en base64 ou emoji
    let symbolElement
    if (this.selectedLogoDataUrl) {
      // Taille et centrage calculés depuis logoScale (0.3–1.1)
      const size   = this.logoScale * 100
      const offset = (100 - size) / 2
      symbolElement = `<image href="${this.selectedLogoDataUrl}" x="${offset}" y="${offset}" width="${size}" height="${size}" preserveAspectRatio="xMidYMid meet"/>`
    } else {
      symbolElement = `<text x="50" y="64" font-size="42" text-anchor="middle" dominant-baseline="auto">${emoji}</text>`
    }

    // ─ Assemblage final
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100" width="100" height="100">
      ${bgElements}
      ${symbolElement}
    </svg>`.trim()

    this.previewTarget.innerHTML = svg
    this.svgInputTarget.value    = svg
  }
}
