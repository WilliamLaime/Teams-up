// Controller Stimulus : sport_select
// Gère la sélection visuelle des sports dans le formulaire d'inscription
// Gère aussi le carrousel "Niveau & Rôle par sport" (une card, flèches gauche/droite)

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "item", "checkbox", "error", "showMore", "showLess",
    // Carrousel niveau/rôle
    "levelRow",       // une div cachée par sport, contient les champs
    "levelsSection",  // la section entière (cachée si aucun sport)
    "carouselName",   // span affichant le nom du sport actuel
    "carouselIcon",   // span affichant l'icône du sport actuel
    "carouselCounter",// span affichant "2 / 3"
    "prevBtn",        // bouton flèche gauche
    "nextBtn"         // bouton flèche droite
  ]

  connect() {
    // Index du sport actuellement affiché dans le carrousel
    this.currentIndex = 0
    this.syncCarousel()
  }

  // Clic sur un sport dans la grille
  toggle(event) {
    const item = event.currentTarget
    const checkbox = item.querySelector("input[type='checkbox']")

    checkbox.checked = !checkbox.checked
    item.classList.toggle("sport-select-item--selected", checkbox.checked)

    this.updateError()

    // Si on décoche le sport qui était affiché, on recale l'index
    const selectedRows = this.getSelectedRows()
    if (this.currentIndex >= selectedRows.length) {
      this.currentIndex = Math.max(0, selectedRows.length - 1)
    }

    this.syncCarousel()
  }

  // Retourne les levelRow des sports actuellement sélectionnés
  getSelectedRows() {
    const selectedIds = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.closest("[data-sport-id]")?.dataset.sportId)
      .filter(Boolean)

    return this.levelRowTargets.filter(row => selectedIds.includes(row.dataset.sportId))
  }

  // Met à jour tout le carrousel selon l'état actuel
  syncCarousel() {
    if (!this.hasLevelsSectionTarget) return

    const selectedRows = this.getSelectedRows()

    // Cache la section si aucun sport sélectionné
    this.levelsSectionTarget.style.display = selectedRows.length > 0 ? "block" : "none"
    if (selectedRows.length === 0) return

    // Cache toutes les rows, puis affiche uniquement la courante
    this.levelRowTargets.forEach(row => row.style.display = "none")
    const currentRow = selectedRows[this.currentIndex]
    if (currentRow) currentRow.style.display = "block"

    // Lit le label (icône + nom) depuis l'élément .sport-carousel-label du levelRow
    // → évite de stocker du HTML dans un data-attribut (problème d'échappement)
    const label = currentRow?.querySelector(".sport-carousel-label")
    if (this.hasCarouselNameTarget && this.hasCarouselIconTarget && label) {
      // On injecte le contenu du label dans la zone d'en-tête du carrousel
      this.carouselIconTarget.innerHTML = ""
      this.carouselNameTarget.innerHTML = ""
      // Clone les enfants du label dans les deux cibles
      label.childNodes.forEach(node => {
        const clone = node.cloneNode(true)
        // Premier enfant = icône, dernier = span nom
        if (node.nodeName === "SPAN" && node.textContent.trim()) {
          this.carouselNameTarget.appendChild(clone)
        } else {
          this.carouselIconTarget.appendChild(clone)
        }
      })
      // Ré-initialise Lucide si l'icône est un SVG Lucide
      if (typeof lucide !== "undefined") lucide.createIcons()
    }
    if (this.hasCarouselCounterTarget) {
      // Affiche le compteur uniquement s'il y a plus d'un sport
      this.carouselCounterTarget.textContent = selectedRows.length > 1
        ? `${this.currentIndex + 1} / ${selectedRows.length}`
        : ""
    }

    // Les flèches sont toujours actives (navigation en boucle)
    if (this.hasPrevBtnTarget) {
      this.prevBtnTarget.style.opacity = "1"
      this.prevBtnTarget.disabled = false
    }
    if (this.hasNextBtnTarget) {
      this.nextBtnTarget.style.opacity = "1"
      this.nextBtnTarget.disabled = false
    }
  }

  // Flèche gauche — sport précédent (boucle : retourne au dernier si on est au premier)
  prevSport() {
    const selectedRows = this.getSelectedRows()
    this.currentIndex = (this.currentIndex - 1 + selectedRows.length) % selectedRows.length
    this.syncCarousel()
  }

  // Flèche droite — sport suivant (boucle : retourne au premier si on est au dernier)
  nextSport() {
    const selectedRows = this.getSelectedRows()
    this.currentIndex = (this.currentIndex + 1) % selectedRows.length
    this.syncCarousel()
  }

  // Révèle tous les sports cachés (bouton "voir plus")
  showMore() {
    this.itemTargets.forEach(item => item.classList.remove("sport-select-item--hidden"))
    if (this.hasShowMoreTarget) this.showMoreTarget.style.display = "none"
    if (this.hasShowLessTarget) this.showLessTarget.style.display = "inline-flex"
  }

  // Replie la liste (bouton "voir moins")
  showLess() {
    this.itemTargets.forEach((item, index) => {
      if (index >= 4) item.classList.add("sport-select-item--hidden")
    })
    if (this.hasShowLessTarget) this.showLessTarget.style.display = "none"
    if (this.hasShowMoreTarget) this.showMoreTarget.style.display = "inline-flex"
  }

  // Affiche/masque le message d'erreur
  updateError() {
    const hasSelection = this.checkboxTargets.some(cb => cb.checked)
    if (this.hasErrorTarget) {
      this.errorTarget.classList.toggle("d-none", hasSelection)
    }
  }

  // Empêche la soumission si aucun sport n'est sélectionné
  validate(event) {
    const hasSelection = this.checkboxTargets.some(cb => cb.checked)
    if (!hasSelection) {
      event.preventDefault()
      if (this.hasErrorTarget) {
        this.errorTarget.classList.remove("d-none")
        this.errorTarget.scrollIntoView({ behavior: "smooth", block: "center" })
      }
    }
  }
}
