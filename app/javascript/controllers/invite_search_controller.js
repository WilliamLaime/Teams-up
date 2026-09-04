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
  // url     : endpoint de recherche JSON (ex: /teams/1/team_invitations/search)
  // suggest : opt-in. Quand il est vrai, le champ interroge aussi l'endpoint SANS
  //           terme de recherche (au focus, ou quand on efface) pour afficher des
  //           suggestions. Faux par défaut : l'endpoint des invitations d'équipe
  //           répond [] sur une requête vide, un dropdown vide s'ouvrirait pour rien.
  static values  = { url: String, suggest: Boolean }

  connect() {
    this._debounceTimer = null
    // Ferme le dropdown si on clique en dehors.
    // Le test `contains` est indispensable depuis l'ouverture au focus : sans lui,
    // le clic qui donne le focus au champ refermait aussitôt le dropdown qu'il
    // venait d'ouvrir. Un clic sur un résultat, lui, referme via #select.
    this._outsideClick = (event) => {
      if (this.element.contains(event.target)) return

      this._closeDropdown()
    }
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
      // En mode suggestions, moins de 3 caractères ne ferme pas le dropdown : on
      // redemande la liste par défaut (inscrits + amis), comme au focus.
      if (this.suggestValue) {
        this._debounceTimer = setTimeout(() => this._fetch(""), 300)
      } else {
        this._closeDropdown()
      }
      return
    }

    // Debounce 300ms pour éviter une requête à chaque frappe
    this._debounceTimer = setTimeout(() => this._fetch(q), 300)
  }

  // Appelé au focus du champ (data-action="focus->invite-search#showSuggestions").
  // Ouvre le dropdown sur les suggestions par défaut sans attendre une frappe —
  // c'est ce qui donne à l'organisateur une piste sur qui il peut nommer.
  showSuggestions() {
    if (!this.suggestValue) return
    if (this.dropdownTarget.childElementCount > 0) return

    this._fetch(this.inputTarget.value.trim())
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
      // En mode suggestions, un dropdown vide veut souvent dire « pas encore d'amis
      // ni d'inscrits », pas « ta recherche n'a rien donné ». On oriente vers la
      // recherche libre plutôt que de laisser croire à un échec.
      empty.textContent = this.suggestValue && this.inputTarget.value.trim().length < 3
        ? "Tape un nom pour chercher un autre joueur."
        : "Aucun joueur trouvé"
      this.dropdownTarget.appendChild(empty)
    } else {
      // En-tête inséré à chaque changement de groupe (« Inscrits au tournoi », puis
      // « Tes amis »). Le serveur renvoie les résultats DÉJÀ triés par groupe : on se
      // contente de détecter la rupture, sans regrouper nous-mêmes.
      let currentGroup = null

      users.forEach(u => {
        const group = u.group || null
        if (group !== currentGroup) {
          currentGroup = group
          if (group) {
            const heading = document.createElement("div")
            heading.className   = "invite-search-heading"
            heading.textContent = group
            this.dropdownTarget.appendChild(heading)
          }
        }

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
