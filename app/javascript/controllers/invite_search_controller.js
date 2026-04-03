// invite_search_controller.js
// Autocomplete pour le formulaire d'invitation d'équipe.
// Cherche les joueurs dès 3 caractères tapés, affiche un dropdown,
// et remplit un champ caché avec l'email de la personne sélectionnée.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hidden", "dropdown"]
  // URL de l'endpoint de recherche JSON (ex: /teams/1/team_invitations/search)
  static values  = { url: String }

  connect() {
    this._debounceTimer = null
    // Ferme le dropdown si on clique en dehors
    this._outsideClick = this._closeDropdown.bind(this)
    document.addEventListener("click", this._outsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick)
  }

  // Appelé à chaque frappe dans le champ visible
  search() {
    clearTimeout(this._debounceTimer)
    const q = this.inputTarget.value.trim()

    // Si le champ est vidé, on réinitialise aussi le champ caché
    if (q.length < 3) {
      if (q.length === 0) this.hiddenTarget.value = ""
      this._closeDropdown()
      return
    }

    // Debounce 300ms pour éviter une requête à chaque frappe
    this._debounceTimer = setTimeout(() => this._fetch(q), 300)
  }

  // Appelé quand l'user clique sur un résultat dans le dropdown
  select(event) {
    const item = event.currentTarget
    // On remplit le champ caché (soumis) avec l'email unique
    this.hiddenTarget.value = item.dataset.email
    // On met le nom complet dans le champ visible
    this.inputTarget.value  = item.dataset.label
    this._closeDropdown()
  }

  // Requête fetch vers l'endpoint de recherche
  _fetch(q) {
    fetch(`${this.urlValue}?q=${encodeURIComponent(q)}`, {
      headers: { Accept: "application/json" }
    })
      .then(r => r.json())
      .then(users => this._renderDropdown(users))
      .catch(() => this._closeDropdown())
  }

  // Génère le HTML du dropdown à partir des résultats
  _renderDropdown(users) {
    if (users.length === 0) {
      this.dropdownTarget.innerHTML = `<div class="invite-search-empty">Aucun joueur trouvé</div>`
    } else {
      this.dropdownTarget.innerHTML = users.map(u => {
        const label = `${u.first_name} ${u.last_name}`
        return `
          <button type="button"
                  class="invite-search-item"
                  data-action="click->invite-search#select"
                  data-email="${u.email}"
                  data-label="${label}">
            <span class="invite-search-name">${u.first_name}</span>
            <span class="invite-search-lastname">${u.last_name}</span>
          </button>
        `
      }).join("")
    }
    this.dropdownTarget.style.display = "block"
  }

  _closeDropdown() {
    this.dropdownTarget.innerHTML     = ""
    this.dropdownTarget.style.display = "none"
  }
}
