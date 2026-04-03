// badge_builder_controller.js
// Gère le générateur de blason SVG interactif sur le formulaire d'équipe.
// Deux modes : "upload" (fichier image) ou "generator" (SVG généré côté client).
// Options : 5 formes de fond, 16 couleurs, 24 symboles emoji.
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
    "tabUpload",       // Bouton onglet "Uploader une image"
    "tabGenerator",    // Bouton onglet "Générateur"
    "panelUpload",     // Panneau upload
    "panelGenerator",  // Panneau générateur
    "preview",         // Div où le SVG live est rendu
    "svgInput",        // Champ caché qui contient le SVG final
    "fileInput"        // Input file pour l'upload
  ]

  connect() {
    // Valeurs par défaut
    this.selectedShape = "shield"
    this.selectedColor = "#1EDD88"
    this.selectedEmoji = "⚽"

    // Si un SVG est déjà enregistré, basculer sur le générateur
    if (this.hasSvgInputTarget && this.svgInputTarget.value) {
      this.showGenerator()
    }

    this._renderSVG()
  }

  // ── Onglets ──────────────────────────────────────────────────────────────────

  showUpload() {
    this.panelUploadTarget.style.display    = "block"
    this.panelGeneratorTarget.style.display = "none"
    this.tabUploadTarget.classList.add("active")
    this.tabGeneratorTarget.classList.remove("active")
    // Vide le SVG pour ne pas envoyer les deux
    this.svgInputTarget.value = ""
  }

  showGenerator() {
    this.panelUploadTarget.style.display    = "none"
    this.panelGeneratorTarget.style.display = "block"
    this.tabUploadTarget.classList.remove("active")
    this.tabGeneratorTarget.classList.add("active")
    // Vide l'input file pour ne pas envoyer les deux
    if (this.hasFileInputTarget) this.fileInputTarget.value = ""
    this._renderSVG()
  }

  // ── Sélections ───────────────────────────────────────────────────────────────

  // Appelé quand l'user clique sur une forme
  selectShape(event) {
    this.selectedShape = event.currentTarget.dataset.shape
    this.element.querySelectorAll(".badge-shape-btn").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  // Appelé quand l'user clique sur une couleur de fond
  selectColor(event) {
    this.selectedColor = event.currentTarget.dataset.color
    this.element.querySelectorAll(".badge-color-swatch").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  // Appelé quand l'user clique sur un symbole
  selectIcon(event) {
    this.selectedEmoji = event.currentTarget.dataset.iconEmoji
    this.element.querySelectorAll(".badge-icon-btn").forEach(el => el.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this._renderSVG()
  }

  // ── Rendu SVG ────────────────────────────────────────────────────────────────

  // Génère le SVG complet : forme + fond coloré + bordure intérieure + emoji
  _renderSVG() {
    const color  = this.selectedColor
    const emoji  = this.selectedEmoji
    const shape  = SHAPES[this.selectedShape] || SHAPES.shield

    // ─ Éléments de fond (forme + dégradé subtil + bordure interne)
    let bgElements = ""

    if (shape.clip) {
      // Forme avec path SVG (bouclier, hexagone, diamant, pentagone)
      bgElements = `
        <defs>
          <linearGradient id="bg-grad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%"   stop-color="${color}" stop-opacity="1"/>
            <stop offset="100%" stop-color="${color}" stop-opacity="0.75"/>
          </linearGradient>
        </defs>
        <path d="${shape.clip}" fill="url(#bg-grad)"/>
        <path d="${shape.inner}" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
      `
    } else {
      // Cercle
      bgElements = `
        <defs>
          <linearGradient id="bg-grad" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%"   stop-color="${color}" stop-opacity="1"/>
            <stop offset="100%" stop-color="${color}" stop-opacity="0.75"/>
          </linearGradient>
        </defs>
        <circle cx="50" cy="50" r="46" fill="url(#bg-grad)"/>
        <circle cx="50" cy="50" r="43" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="2"/>
      `
    }

    // ─ Assemblage SVG final
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
      ${bgElements}
      <text x="50" y="64" font-size="42" text-anchor="middle" dominant-baseline="auto">${emoji}</text>
    </svg>`.trim()

    // Affiche le preview et stocke dans le champ caché
    this.previewTarget.innerHTML = svg
    this.svgInputTarget.value    = svg
  }
}
