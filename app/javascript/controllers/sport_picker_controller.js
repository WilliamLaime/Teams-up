// sport_picker_controller.js
// Dropdown custom pour sélectionner un sport dans le formulaire de match.
// Remplace le <select> natif pour pouvoir afficher des icônes images (ex: Padel PNG).
// Il met à jour un <input hidden> (sportInput dans match-form) et émet un event
// Stimulus "sport-picker:sport-selected" qui remonte jusqu'au form pour que
// match_form_controller#updateSport réagisse.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "dropdown", "item"]

  connect() {
    // Ferme le dropdown si on clique en dehors
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }

  // Ouvre ou ferme le dropdown au clic sur le trigger
  toggle(event) {
    event.stopPropagation()
    const dropdown = this.dropdownTarget
    dropdown.style.display = dropdown.style.display === "none" ? "block" : "none"
  }

  // Appelé quand l'utilisateur clique sur un sport dans la liste
  select(event) {
    event.stopPropagation()
    const btn = event.currentTarget
    const sportId = btn.dataset.sportId

    // 1. Met à jour l'input hidden (match[sport_id]) ciblé par match-form
    const hiddenInput = this.element.closest("form")
      .querySelector("[data-match-form-target='sportInput']")
    if (hiddenInput) {
      hiddenInput.value = sportId
    }

    // 2. Émet un événement Stimulus "sport-picker:sport-selected" qui remonte
    //    jusqu'au <form data-action="sport-picker:sport-selected->match-form#updateSport">
    //    → match_form_controller#updateSport est appelé de façon fiable
    this.dispatch("sport-selected", { bubbles: true, cancelable: false })

    // 2. Met à jour le bouton trigger avec l'icône + nom du sport sélectionné
    this.triggerTarget.innerHTML = btn.innerHTML

    // 3. Met à jour la classe active (fond vert sur l'item sélectionné)
    this.itemTargets.forEach(item => item.classList.remove("sport-picker-item--active"))
    btn.classList.add("sport-picker-item--active")

    // 4. Ferme le dropdown
    this.dropdownTarget.style.display = "none"
  }

  // Ferme le dropdown si on clique en dehors
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.style.display = "none"
    }
  }
}
