import { Controller } from "@hotwired/stimulus"

// Contrôleur d'autocomplétion pour le champ "Ville préférée" du profil.
// Stratégie : requête Nominatim (OpenStreetMap) filtrée sur les villes françaises.
// Différence vs venue_search_controller : on cherche des VILLES (pas des établissements),
// on ne persiste rien en BDD, et on remplit un simple champ texte (pas de badges multi-sélection).
export default class extends Controller {
  static targets = ["input", "dropdown"]

  // Identifiant de la dernière recherche (anti race-condition)
  _searchId = 0

  // Timer pour le debounce (évite une requête à chaque frappe)
  _debounceTimer = null

  connect() {
    // Ferme le dropdown si on clique ailleurs sur la page
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
    clearTimeout(this._debounceTimer)
  }

  // ── RECHERCHE (déclenchée par keyup sur l'input) ────────────────────────────

  search(event) {
    const query = this.inputTarget.value.trim()

    // Masque le dropdown si moins de 2 caractères
    if (query.length < 2) {
      this.closeDropdown()
      return
    }

    // Debounce : attend 300ms sans frappe avant de lancer la requête
    clearTimeout(this._debounceTimer)
    this._debounceTimer = setTimeout(() => this.fetchCities(query), 300)
  }

  // ── REQUÊTE NOMINATIM ───────────────────────────────────────────────────────

  async fetchCities(query) {
    const searchId = ++this._searchId

    try {
      const params = new URLSearchParams({
        q:                 query,
        format:            "json",
        addressdetails:    "1",
        namedetails:       "1",
        limit:             "6",
        "accept-language": "fr",
        countrycodes:      "fr",   // Uniquement la France
        featuretype:       "city"  // Préfère les résultats de type ville
      })

      const response = await fetch(
        `https://nominatim.openstreetmap.org/search?${params.toString()}`,
        { headers: { "Accept-Language": "fr", "User-Agent": "TeamUpApp/1.0" } }
      )

      if (!response.ok) return

      const data = await response.json()

      // Si une autre frappe a eu lieu entre-temps, on abandonne ces résultats
      if (searchId !== this._searchId) return

      // Filtre : garde uniquement les résultats de type ville/commune/territoire
      const cityTypes = ["city", "town", "village", "municipality", "administrative", "suburb"]
      const filtered = data.filter(r => {
        const type = (r.type  || "").toLowerCase()
        const cls  = (r.class || "").toLowerCase()
        return cityTypes.includes(type) || cls === "boundary" || cls === "place"
      })

      // Tri par importance décroissante (champ Nominatim 0→1) : les grandes villes en premier
      const sorted = filtered.sort((a, b) => (b.importance || 0) - (a.importance || 0))

      // Déduplication : on ne garde qu'un résultat par nom de ville (insensible à la casse)
      const seen = new Set()
      const cities = sorted.filter(r => {
        const addr = r.address || {}
        const name = r.namedetails?.name || r.name || r.display_name.split(",")[0].trim()
        const key  = name.toLowerCase().trim()
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })

      this.displayResults(cities)
    } catch (error) {
      console.error("Erreur autocomplétion ville :", error)
    }
  }

  // ── AFFICHAGE DES SUGGESTIONS ───────────────────────────────────────────────

  displayResults(cities) {
    const dropdown = this.dropdownTarget

    if (cities.length === 0) {
      dropdown.innerHTML = `
        <div style="padding:0.5rem 0.75rem; font-size:0.8rem; color:var(--theme-text-muted);">
          Aucune ville trouvée
        </div>
      `
      dropdown.style.display = "block"
      return
    }

    // Construit les items du dropdown
    dropdown.innerHTML = cities.map(city => {
      const addr       = city.address || {}
      // Nom principal de la ville
      const name       = city.namedetails?.name || city.name || city.display_name.split(",")[0].trim()
      // Département pour différencier les homonymes (ex: "Lyon" → "Métropole de Lyon")
      const department = addr.county || addr.state || ""
      const deptHtml   = department
        ? `<span style="font-size:0.75rem; color:var(--theme-text-muted); margin-left:0.4rem;">${this.escapeHtml(department)}</span>`
        : ""

      return `
        <div style="padding:0.5rem 0.75rem; cursor:pointer; border-radius:6px; transition:background 0.15s; font-size:0.85rem;"
             onmouseover="this.style.background='rgba(30,221,136,0.1)'"
             onmouseout="this.style.background='transparent'"
             data-action="click->city-search#selectCity"
             data-city-name="${this.escapeAttr(name)}">
          <span style="font-weight:600;">📍 ${this.escapeHtml(name)}</span>
          ${deptHtml}
        </div>
      `
    }).join("")

    dropdown.style.display = "block"
  }

  // ── SÉLECTION D'UNE VILLE ──────────────────────────────────────────────────

  // Appelé quand l'utilisateur clique sur une suggestion
  selectCity(event) {
    const cityName = event.currentTarget.dataset.cityName
    // Remplit le champ texte avec le nom de la ville sélectionnée
    this.inputTarget.value = cityName
    // Ferme le dropdown et invalide les recherches en cours
    this._searchId++
    this.closeDropdown()

    // Sur la page des matchs, le formulaire a un bouton submit caché (#filter-submit-btn).
    // Si présent, on soumet automatiquement dès la sélection (comme la date ou le niveau).
    // Sur le profil/edit, ce bouton n'existe pas → pas d'envoi automatique.
    const submitBtn = this.inputTarget.closest("form")?.querySelector("#filter-submit-btn")
    if (submitBtn) submitBtn.click()
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  closeDropdown() {
    this.dropdownTarget.style.display = "none"
    this.dropdownTarget.innerHTML = ""
  }

  // Ferme le dropdown si on clique en dehors du composant
  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }

  // Échappe les caractères spéciaux pour l'affichage HTML (anti-XSS)
  escapeHtml(text) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(String(text || "")))
    return div.innerHTML
  }

  // Échappe les caractères spéciaux pour les attributs HTML (data-*)
  escapeAttr(text) {
    return String(text || "").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
  }
}
