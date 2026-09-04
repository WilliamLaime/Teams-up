// invite_search_controller.js
// Autocomplete pour le formulaire d'invitation d'équipe (et de co-organisateur de tournoi).
// Cherche les joueurs dès 3 caractères tapés, affiche un dropdown, et remplit un champ
// caché avec l'identifiant signé (sgid) de la personne sélectionnée.
//
// SÉCURITÉ — deux règles à ne pas casser dans ce fichier :
//   1. L'endpoint ne renvoie JAMAIS d'email : on transporte un `signed_id` Rails
//      (signé, à usage et durée de vie limités) au lieu de l'adresse de la personne.
//   2. Les noms des joueurs sont des données saisies par les utilisateurs : ils sont
//      insérés via `textContent` / `dataset`, jamais par `innerHTML`. Une interpolation
//      dans du HTML permettrait à quelqu'un qui met `"><img src=x onerror=…>` dans son
//      prénom d'exécuter du JS chez tous les capitaines qui le voient (XSS stocké).
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
    // On remplit le champ caché (soumis) avec l'identifiant signé du joueur
    this.hiddenTarget.value = item.dataset.sgid
    // On met le nom complet dans le champ visible
    this.inputTarget.value  = item.dataset.label
    // Notifie les autres contrôleurs (ex: tournament-form met à jour son récap).
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
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

  // Génère le dropdown à partir des résultats.
  // Construction par nœuds DOM (pas d'innerHTML) : voir la note SÉCURITÉ en haut du fichier.
  _renderDropdown(users) {
    this.dropdownTarget.replaceChildren()

    if (users.length === 0) {
      const empty = document.createElement("div")
      empty.className   = "invite-search-empty"
      empty.textContent = "Aucun joueur trouvé"
      this.dropdownTarget.appendChild(empty)
    } else {
      users.forEach(u => {
        const firstName = u.first_name || ""
        const lastName  = u.last_name  || ""

        const item = document.createElement("button")
        item.type            = "button"
        item.className       = "invite-search-item"
        item.dataset.sgid    = u.sgid
        item.dataset.label   = `${firstName} ${lastName}`.trim()

        const first = document.createElement("span")
        first.className   = "invite-search-name"
        first.textContent = firstName

        const last = document.createElement("span")
        last.className   = "invite-search-lastname"
        last.textContent = lastName

        item.append(first, last)

        // `already_organizer` : la personne co-organise déjà ce tournoi. On la
        // montre quand même, grisée — la masquer donnait un « Aucun joueur trouvé »
        // impossible à distinguer d'une faute de frappe, et l'organisateur n'avait
        // aucun moyen de comprendre pourquoi il ne trouvait pas quelqu'un.
        if (u.already_organizer) {
          item.disabled  = true
          item.className = "invite-search-item invite-search-item--disabled"

          const badge = document.createElement("span")
          badge.className   = "invite-search-badge"
          badge.textContent = "déjà co-organisateur"
          item.appendChild(badge)
        } else {
          item.dataset.action = "click->invite-search#select"
        }

        this.dropdownTarget.appendChild(item)
      })
    }

    this.dropdownTarget.style.display = "block"
  }

  _closeDropdown() {
    this.dropdownTarget.replaceChildren()
    this.dropdownTarget.style.display = "none"
  }
}
