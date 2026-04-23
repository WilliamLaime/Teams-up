import { Controller } from "@hotwired/stimulus"

// Contrôleur pour ajouter/supprimer des lieux favoris avec autocomplete
// Stratégie identique à place_search_controller.js :
//   1. Notre BDD Rails (/venues/search) → établissements sportifs officiels
//   2. Nominatim / OpenStreetMap        → clubs privés, nouvelles salles, etc.
// Les deux requêtes partent en même temps, les résultats sont fusionnés et dédoublonnés.
// Quand un résultat OSM est sélectionné, il est persisté en BDD via /venues/find_or_create.
// Ainsi un lieu trouvé ici sera retrouvable dans le formulaire "créer un match" (et inversement).
export default class extends Controller {
  static targets = ["searchInput", "resultsDropdown", "selectedVenues", "hiddenInput"]

  // Stocke les IDs des venues sélectionnées en mémoire
  selectedIds = []

  // Compteur de recherche : permet d'annuler les résultats d'une recherche
  // qui arriveraient après qu'une venue ait déjà été sélectionnée (race condition)
  _searchId = 0

  connect() {
    // Charge les IDs initiales depuis le champ caché (venues déjà sauvegardées)
    const hiddenValue = this.hiddenInputTarget.value
    this.selectedIds = hiddenValue ? hiddenValue.split(",").map(id => parseInt(id)).filter(Boolean) : []

    // Ferme le dropdown si on clique ailleurs sur la page
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
  }

  // ── RECHERCHE ───────────────────────────────────────────────────────────────

  // Appelé quand l'user tape dans le champ de recherche
  async search(event) {
    const query = this.searchInputTarget.value.trim()

    // Masque le dropdown si moins de 2 caractères
    if (query.length < 2) {
      this.resultsDropdownTarget.style.display = "none"
      this.resultsDropdownTarget.innerHTML = ""
      return
    }

    // Chaque recherche reçoit un ID unique.
    // Si une venue est sélectionnée pendant la recherche, _searchId est incrémenté
    // et les résultats qui arrivent après sont ignorés (évite la réouverture du dropdown).
    const searchId = ++this._searchId

    try {
      // Les deux sources partent en parallèle (Promise.all) pour de meilleures performances.
      const [dbVenues, osmVenues] = await Promise.all([
        this.fetchDbVenues(query),
        this.fetchNominatim(query)
      ])

      // Si une autre recherche ou une sélection a eu lieu entre-temps → on abandonne
      if (searchId !== this._searchId) return

      // Fusionne et dédoublonne les résultats (BDD prioritaire)
      const merged = this.mergeResults(dbVenues, osmVenues)
      this.displayResults(merged)
    } catch (error) {
      console.error("Erreur lors de la recherche :", error)
    }
  }

  // ── SOURCE 1 : Notre BDD Rails ──────────────────────────────────────────────
  async fetchDbVenues(query) {
    try {
      const response = await fetch(`/venues/search?q=${encodeURIComponent(query)}`, {
        headers: { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json" }
      })
      if (!response.ok) return []
      return await response.json()
    } catch {
      return []
    }
  }

  // ── SOURCE 2 : Nominatim / OpenStreetMap ────────────────────────────────────
  // Même logique que place_search_controller.js mais sans géolocalisation GPS
  // (le profil n'a pas besoin de tri par proximité).
  async fetchNominatim(query) {
    try {
      const params = new URLSearchParams({
        q:                 query,
        format:            "json",
        addressdetails:    "1",
        namedetails:       "1",
        limit:             "8",
        "accept-language": "fr",
        countrycodes:      "fr"
      })

      const response = await fetch(
        `https://nominatim.openstreetmap.org/search?${params.toString()}`,
        { headers: { "Accept-Language": "fr", "User-Agent": "TeamsUpApp/1.0" } }
      )
      if (!response.ok) return []

      const data = await response.json()

      // Filtre : uniquement les établissements sportifs (class="sport"/"leisure")
      const knownSportTypes = [
        "stadium", "fitness_centre", "pitch", "track", "swimming_pool",
        "golf_course", "tennis", "basketball", "padel", "squash", "boxing",
        "martial_arts", "gym", "dojo", "ice_rink", "shooting", "archery",
        "climbing", "cycling", "leisure_centre"
      ]
      const filtered = data.filter(r => {
        const cls = (r.class || "").toLowerCase()
        const typ = (r.type  || "").toLowerCase()
        return cls.includes("sport") || cls === "leisure" ||
               typ.includes("sport") || knownSportTypes.includes(typ)
      })

      // Convertit le format Nominatim vers le format unifié de la BDD
      return filtered.map(r => {
        const addr     = r.address || {}
        const name     = r.namedetails?.name || r.name || r.display_name.split(",")[0].trim()
        const road     = addr.road || addr.pedestrian || ""
        const postcode = addr.postcode || ""
        const city     = addr.city || addr.town || addr.village || addr.municipality || ""
        return {
          id:          null,   // Pas encore en BDD → sera créé à la sélection
          name:        name,
          sport_type:  r.type || r.class || "",
          address:     road,
          city:        city,
          postal_code: postcode,
          longitude:   parseFloat(r.lon),
          latitude:    parseFloat(r.lat),
          _source:     "osm"   // Marque les résultats Nominatim pour le badge "OSM"
        }
      })
    } catch {
      return []
    }
  }

  // ── FUSION DES DEUX SOURCES ─────────────────────────────────────────────────
  // BDD en premier. Nominatim complète avec ce qui manque.
  // Déduplication exacte sur nom + ville (insensible à la casse).
  mergeResults(dbVenues, osmVenues) {
    const seen = new Set()
    return [...dbVenues, ...osmVenues]
      .filter(v => {
        const key = v.name.toLowerCase().trim() + "|" + v.city.toLowerCase().trim()
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })
      .slice(0, 8)  // Maximum 8 résultats affichés
  }

  // ── AFFICHAGE DES RÉSULTATS ─────────────────────────────────────────────────
  displayResults(venues) {
    const dropdown = this.resultsDropdownTarget

    if (venues.length === 0) {
      dropdown.innerHTML = '<div style="padding:0.5rem; font-size:0.8rem; color:var(--theme-text-muted);">Aucune venue trouvée</div>'
      dropdown.style.display = "block"
      return
    }

    // Génère les items du dropdown avec les data-* nécessaires à addVenue
    dropdown.innerHTML = venues.map(venue => {
      // Badge "OSM" discret pour les résultats Nominatim non encore en BDD
      const sourceBadge = venue._source === "osm"
        ? `<span style="font-size:0.65rem; color:var(--theme-text-muted); margin-left:4px;">OSM</span>`
        : ""

      const icon = this.getSportIcon(venue.sport_type)

      return `
        <div style="padding:0.5rem; cursor:pointer; border-radius:6px; transition:background 0.15s; font-size:0.85rem;"
             onmouseover="this.style.background='rgba(30,221,136,0.1)'"
             onmouseout="this.style.background='transparent'"
             data-action="click->venue-search#addVenue"
             data-venue-id="${venue.id || ""}"
             data-venue-name="${this.escapeAttr(venue.name)}"
             data-venue-city="${this.escapeAttr(venue.city)}"
             data-venue-address="${this.escapeAttr(venue.address || '')}"
             data-venue-postal-code="${this.escapeAttr(venue.postal_code || '')}"
             data-venue-sport-type="${this.escapeAttr(venue.sport_type || '')}"
             data-venue-lat="${venue.latitude || ''}"
             data-venue-lon="${venue.longitude || ''}">
          <div class="d-flex align-items-start gap-2">
            <span>${icon}</span>
            <div>
              <div style="font-weight:600;">${this.escapeHtml(venue.name)}${sourceBadge}</div>
              <div style="font-size:0.75rem; color:var(--theme-text-muted);">
                ${this.escapeHtml(venue.sport_type || "")} · ${this.escapeHtml(venue.city)}
              </div>
            </div>
          </div>
        </div>
      `
    }).join("")

    dropdown.style.display = "block"
  }

  // ── AJOUT D'UNE VENUE AUX FAVORIS ──────────────────────────────────────────

  // Appelé quand l'user clique sur un résultat du dropdown
  async addVenue(event) {
    const el = event.currentTarget
    let venueId = el.dataset.venueId ? parseInt(el.dataset.venueId) : null
    const venueName = el.dataset.venueName
    const venueCity = el.dataset.venueCity

    if (!venueId) {
      // Résultat OSM : on persiste la venue en BDD d'abord pour avoir un vrai ID.
      // Cela permet à cette venue d'apparaître dans les résultats BDD la prochaine fois.
      const id = await this.findOrCreateVenue({
        name:        venueName,
        city:        venueCity,
        address:     el.dataset.venueAddress    || "",
        postal_code: el.dataset.venuePostalCode || "",
        sport_type:  el.dataset.venueSportType  || "",
        latitude:    el.dataset.venueLat        || "",
        longitude:   el.dataset.venueLon        || ""
      })
      if (!id) return  // Création échouée → on n'ajoute pas
      venueId = id
    }

    // Ne l'ajoute pas si déjà dans la liste
    if (this.selectedIds.includes(venueId)) {
      this.resultsDropdownTarget.style.display = "none"
      return
    }

    // Ajoute à la liste en mémoire et met à jour le champ caché
    this.selectedIds.push(venueId)
    this.updateHiddenInput()

    // Affiche le badge dans la liste des sélectionnées
    this.appendVenueBadge(venueId, venueName, venueCity)

    // Invalide toute recherche en cours (race condition : Nominatim pourrait réouvrir le dropdown)
    this._searchId++

    // Vide le champ de recherche et ferme le dropdown
    this.searchInputTarget.value = ""
    this.resultsDropdownTarget.style.display = "none"
    this.resultsDropdownTarget.innerHTML = ""
  }

  // ── SUPPRESSION D'UNE VENUE DES FAVORIS ────────────────────────────────────

  // Appelé quand l'user clique sur le ✕ d'un badge
  removeVenue(event) {
    event.preventDefault()
    const venueId = parseInt(event.currentTarget.dataset.venueId)

    // Supprime de la liste en mémoire et met à jour le champ caché
    this.selectedIds = this.selectedIds.filter(id => id !== venueId)
    this.updateHiddenInput()

    // Supprime le badge visuellement
    const badge = event.currentTarget.closest(".badge")
    if (badge) badge.remove()
  }

  // ── PERSISTANCE OSM → BDD ───────────────────────────────────────────────────

  // Persiste une venue Nominatim en BDD et retourne son ID Rails.
  // Identique à place_search_controller.js#findOrCreateVenue.
  async findOrCreateVenue(venueData) {
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch("/venues/find_or_create", {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept":       "application/json"
        },
        body: JSON.stringify(venueData)
      })
      if (!response.ok) return null
      const data = await response.json()
      return data.id || null
    } catch {
      return null
    }
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  // Met à jour le champ caché avec les IDs sélectionnées (séparés par des virgules)
  updateHiddenInput() {
    this.hiddenInputTarget.value = this.selectedIds.join(",")
  }

  // Ajoute un badge visuel pour une venue sélectionnée
  appendVenueBadge(venueId, venueName, venueCity) {
    const badge = document.createElement("div")
    badge.className = "badge"
    badge.style.cssText = `
      background-color: rgba(30, 221, 136, 0.2);
      color: #1EDD88;
      padding: 0.5rem 0.75rem;
      margin: 0.25rem;
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
      font-size: 0.85rem;
    `
    badge.innerHTML = `
      🏟️ ${this.escapeHtml(venueName)}
      <span style="color:var(--theme-text-muted);">(${this.escapeHtml(venueCity)})</span>
      <button type="button"
              class="venue-remove-btn"
              style="background:none; border:none; color:#1EDD88; cursor:pointer; padding:0; font-weight:bold;"
              data-action="click->venue-search#removeVenue"
              data-venue-id="${venueId}">
        ✕
      </button>
    `
    this.selectedVenuesTarget.appendChild(badge)
  }

  // Emoji selon le type de sport (identique à place_search_controller.js)
  getSportIcon(sportType) {
    if (!sportType) return "🏟️"
    const type = sportType.toLowerCase()
    if (type.includes("football") || type.includes("foot") || type.includes("pitch")) return "⚽"
    if (type.includes("tennis"))                                                       return "🎾"
    if (type.includes("basket"))                                                       return "🏀"
    if (type.includes("natation") || type.includes("piscine") || type.includes("pool")) return "🏊"
    if (type.includes("rugby"))                                                        return "🏉"
    if (type.includes("volley"))                                                       return "🏐"
    if (type.includes("gym") || type.includes("fitness"))                              return "💪"
    if (type.includes("boxe") || type.includes("combat") || type.includes("martial")) return "🥊"
    if (type.includes("golf"))                                                         return "⛳"
    if (type.includes("padel") || type.includes("squash"))                             return "🏓"
    if (type.includes("escalade"))                                                     return "🧗"
    if (type.includes("salle") || type.includes("gymnase") || type.includes("sports_centre")) return "🏋️"
    return "🏟️"
  }

  // Échappe les caractères spéciaux pour l'affichage HTML (anti-XSS)
  escapeHtml(text) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(String(text)))
    return div.innerHTML
  }

  // Échappe les caractères spéciaux pour les attributs HTML (data-*)
  escapeAttr(text) {
    return String(text).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
  }

  // Ferme le dropdown si on clique en dehors du composant
  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.resultsDropdownTarget.style.display = "none"
    }
  }
}
