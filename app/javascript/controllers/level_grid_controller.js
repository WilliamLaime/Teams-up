// level_grid_controller.js
// Gère la modale "Grilles de niveaux" :
//   - Onglets par sport (tab) avec panneau de contenu associé (panel)
//   - preselectSport() : appelé depuis les boutons "?" pour ouvrir sur le bon sport

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  // Au chargement : affiche le premier onglet par défaut
  connect() {
    const firstTab = this.tabTargets[0]
    if (firstTab) this._activate(firstTab.dataset.sportId)
  }

  // Clic sur un onglet sport
  selectTab(event) {
    this._activate(event.currentTarget.dataset.sportId)
  }

  // Appelé par les boutons "?" depuis n'importe quelle page.
  // Si le bouton a un data-sport-id → pré-sélectionne ce sport.
  // Sinon (ex: index sans sport actif) → reste sur l'onglet courant.
  preselectSport(event) {
    // Cas 1 : le bouton porte un sport-id statique (profil form, show match)
    const staticId = event.currentTarget.dataset.sportId
    if (staticId) {
      this._activate(staticId)
      return
    }

    // Cas 2 : formulaire match — le sport peut changer dynamiquement.
    // On lit la valeur live du hidden field sport du formulaire.
    const sportInput = document.querySelector('[data-match-form-target="sportInput"]')
    if (sportInput?.value) {
      this._activate(sportInput.value)
    }
    // Sinon → le connect() a déjà activé le premier onglet, rien à faire
  }

  // ── Méthode privée : affiche le panneau du sport et surligne l'onglet ──
  _activate(sportId) {
    const id = String(sportId)

    // Si le sport n'a pas d'onglet dans la modale (ex: sport collectif),
    // on revient au premier onglet disponible plutôt que d'afficher un panneau vide.
    const availableIds = this.tabTargets.map(t => t.dataset.sportId)
    const resolvedId   = availableIds.includes(id) ? id : (availableIds[0] ?? id)

    // Onglets : surligner l'actif
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.sportId === resolvedId
      tab.style.borderBottom = isActive ? "2px solid #1EDD88" : "2px solid transparent"
      tab.style.color        = isActive ? "#1EDD88"           : "var(--theme-text-muted)" // Couleur selon le thème
    })

    // Panneaux : afficher le bon, cacher les autres
    this.panelTargets.forEach(panel => {
      panel.style.display = panel.dataset.sportId === resolvedId ? "" : "none"
    })
  }
}
