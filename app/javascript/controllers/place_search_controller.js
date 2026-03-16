// Controller Stimulus — recherche de lieux pour le formulaire de match
//
// Stratégie : deux sources combinées en parallèle pour une couverture maximale
//   1. Notre BDD Rails (/venues/search) → 328 000 établissements sportifs officiels
//   2. Nominatim / OpenStreetMap        → clubs privés, nouvelles salles, gyms, etc.
//
// Les deux requêtes partent en même temps, les résultats sont fusionnés et dédoublonnés.
// Notre BDD est prioritaire, Nominatim complète avec ce qui manque.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "input"    → le champ texte visible (lieu saisi par l'user)
  // "dropdown" → le div qui affiche les suggestions
  // "venueId"  → champ caché stockant l'id de l'établissement sélectionné (si en BDD)
  static targets = ["input", "dropdown", "venueId"]

  connect() {
    this.timeout = null   // Pour le debounce (évite une requête à chaque frappe)

    // Restaure le GPS depuis sessionStorage (persiste lors des navigations Turbo).
    // sessionStorage est lié à l'onglet → vidé à la fermeture, pas à la navigation.
    const savedLat = sessionStorage.getItem("place_search_lat")
    const savedLon = sessionStorage.getItem("place_search_lon")
    this.userLat = savedLat ? parseFloat(savedLat) : null
    this.userLon = savedLon ? parseFloat(savedLon) : null

    // Ferme le dropdown si on clique ailleurs
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
    clearTimeout(this.timeout)
  }

  // Appelé au focus sur le champ → affiche "Ma position" en attendant la saisie
  showDefault() {
    const query = this.inputTarget.value.trim()
    if (query.length >= 3) return  // Ne remplace pas des résultats déjà affichés

    // Demande le GPS silencieusement en arrière-plan dès que l'user clique sur le champ.
    // Si la permission est déjà accordée, le navigateur répond en < 100ms → le GPS sera
    // disponible bien avant les 350ms de debounce quand l'user tapera.
    // Si non accordée, l'user peut toujours cliquer "Ma position" manuellement.
    if (!this.userLat && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.userLat = position.coords.latitude
          this.userLon = position.coords.longitude
          // Sauvegarde en sessionStorage pour les prochaines visites
          sessionStorage.setItem("place_search_lat", this.userLat)
          sessionStorage.setItem("place_search_lon", this.userLon)
        },
        () => {} // Erreur silencieuse : l'user peut utiliser "Ma position" manuellement
      )
    }

    this.showMyPositionOption()
  }

  // Appelé à chaque frappe → déclenche la recherche combinée après 350ms
  search() {
    clearTimeout(this.timeout)

    const query = this.inputTarget.value.trim()

    // L'utilisateur retape → il n'a plus de venue sélectionné
    if (this.hasVenueIdTarget) this.venueIdTarget.value = ""

    if (query.length < 3) {
      this.showMyPositionOption()
      return
    }

    // Debounce : attend 350ms après la dernière frappe
    this.timeout = setTimeout(() => {
      this.searchCombined(query)
    }, 350)
  }

  // Lance les deux recherches en parallèle et fusionne les résultats
  async searchCombined(query) {
    // Promise.all → les deux requêtes partent simultanément (pas l'une après l'autre)
    // Si l'une échoue, on utilise quand même l'autre grâce au "catch" sur chacune
    const [dbVenues, nominatimVenues] = await Promise.all([
      this.fetchDbVenues({ q: query }),
      this.fetchNominatim(query, this.userLat, this.userLon)
    ])

    // Fusionne : DB en premier, Nominatim complète avec ce qui manque
    const merged = this.mergeResults(dbVenues, nominatimVenues)
    this.showResults(merged, query)
  }

  // Affiche uniquement "Ma position" (quand < 3 caractères saisis)
  showMyPositionOption() {
    this.dropdownTarget.innerHTML = this.buildMyPositionItem()
    this.dropdownTarget.style.display = "block"
  }

  // Appelé quand l'user clique "Ma position" → demande GPS → recherche à proximité
  async useMyPosition() {
    if (!navigator.geolocation) {
      this.showError("La géolocalisation n'est pas disponible sur ce navigateur.")
      return
    }

    this.inputTarget.value = "Localisation en cours…"
    this.inputTarget.disabled = true
    this.hideDropdown()

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        const lat = position.coords.latitude
        const lon = position.coords.longitude

        this.userLat = lat
        this.userLon = lon
        // Sauvegarde le GPS en sessionStorage pour survivre aux navigations Turbo
        sessionStorage.setItem("place_search_lat", lat)
        sessionStorage.setItem("place_search_lon", lon)
        this.inputTarget.disabled = false
        this.inputTarget.value = ""

        // Même logique que searchCombined : BDD + Nominatim en parallèle
        // fetchNominatim avec query="" cherche "sport" autour des coordonnées (bounded=1)
        const [dbVenues, nominatimVenues] = await Promise.all([
          this.fetchDbVenues({ lat, lon }),
          this.fetchNominatim("", lat, lon)
        ])
        const merged = this.mergeResults(dbVenues, nominatimVenues)
        this.showResults(merged, "")
      },
      () => {
        this.inputTarget.value = ""
        this.inputTarget.disabled = false
        this.showError("Impossible d'obtenir votre position. Veuillez saisir votre lieu manuellement.")
      }
    )
  }

  // ── SOURCE 1 : Notre BDD Rails ──────────────────────────────────────────────
  // Retourne un tableau d'objets { id, name, sport_type, address, city, postal_code, ... }
  async fetchDbVenues(params = {}) {
    try {
      const urlParams = new URLSearchParams()
      if (params.q) urlParams.append("q", params.q)

      // Toujours envoyer le GPS quand disponible :
      // - Sans texte → le controller filtre par zone (~30km)
      // - Avec texte → le controller cherche sur toute la France et TRIE par proximité
      const lat = params.lat || this.userLat
      const lon = params.lon || this.userLon
      if (lat) urlParams.append("lat", lat)
      if (lon) urlParams.append("lon", lon)

      const response = await fetch(`/venues/search?${urlParams.toString()}`, {
        headers: { "X-Requested-With": "XMLHttpRequest", "Accept": "application/json" }
      })
      if (!response.ok) return []

      return await response.json()  // Format attendu : [{ id, name, sport_type, city, ... }]
    } catch {
      return []  // En cas d'erreur réseau, on retourne un tableau vide (l'autre source prend le relais)
    }
  }

  // ── SOURCE 2 : Nominatim / OpenStreetMap ────────────────────────────────────
  // Retourne un tableau d'objets au même format que fetchDbVenues (id: null car pas en BDD)
  // Couvre : clubs privés, nouvelles salles, gyms, centres sportifs non référencés
  async fetchNominatim(query, lat, lon) {
    try {
      // Quand query est vide (cas "Ma position"), on cherche "sport" dans le rayon GPS
      // Nominatim ne sait pas faire "tous les lieux sportifs à Xkm" sans mot-clé
      const searchQuery = query || "sport"

      const params = new URLSearchParams({
        q:                searchQuery,
        format:           "json",
        addressdetails:   "1",   // Retourne rue, ville, CP...
        namedetails:      "1",   // Retourne le nom officiel du lieu
        limit:            "8",
        "accept-language": "fr",
        countrycodes:     "fr",  // Limité à la France
      })

      if (lat && lon) {
        // Viewbox légèrement plus large (0.5° ≈ 55km) pour ne pas rater les venues en bord de zone.
        // Le filtre 30km sera appliqué APRÈS dans mergeResults.
        const delta = 0.5
        params.append("viewbox", `${lon - delta},${lat + delta},${lon + delta},${lat - delta}`)
        // bounded=1 : Nominatim ne retourne QUE des résultats dans le viewbox.
        // Auparavant on utilisait bounded=0 (toute la France) pour les recherches texte,
        // mais ça remplissait les 8 slots avec des Le Five de Paris/Lyon/etc. avant Bordeaux.
        params.append("bounded", "1")
      }

      const response = await fetch(
        `https://nominatim.openstreetmap.org/search?${params.toString()}`,
        { headers: { "Accept-Language": "fr", "User-Agent": "TeamUpApp/1.0" } }
      )
      if (!response.ok) return []

      const data = await response.json()

      // Filtre sport : toujours appliqué, que l'user tape du texte ou non.
      // On exige que le résultat OSM soit dans une catégorie liée au sport/leisure.
      // Les pubs, restaurants, pharmacies... ont class="amenity" et sont donc exclus.
      // Les établissements sportifs (Le Five, salles de sport, stades...) ont
      // class="leisure" ou class="sport" dans OpenStreetMap.
      // On accepte un résultat OSM si :
      //   - sa class contient "sport" ou "leisure" (ex: "sport", "sports", "leisure")
      //   - ou son type contient "sport" (ex: "sports_centre", "sports_hall", "sports")
      //   - ou son type est un type de sport connu
      // Cela exclut pubs (amenity/pub), restos (amenity/restaurant), etc.
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

      // Convertit le format Nominatim vers notre format unifié
      return filtered.map(r => {
        const addr       = r.address || {}
        const name       = r.namedetails?.name || r.name || r.display_name.split(",")[0].trim()
        const road       = addr.road || addr.pedestrian || ""
        const postcode   = addr.postcode || ""
        const city       = addr.city || addr.town || addr.village || addr.municipality || ""
        return {
          id:          null,   // Pas en BDD → venue_id sera vide à la sélection
          name:        name,
          sport_type:  r.type || r.class || "",
          address:     road,
          city:        city,
          postal_code: postcode,
          longitude:   parseFloat(r.lon),
          latitude:    parseFloat(r.lat),
          _source:     "osm"   // Marqueur interne pour l'affichage (badge "OSM")
        }
      })
    } catch {
      return []
    }
  }

  // ── FUSION DES DEUX SOURCES ─────────────────────────────────────────────────
  // Notre BDD passe en premier. Nominatim complète avec ce qui manque.
  // Règle géographique :
  //   1. Si GPS disponible → affiche uniquement les résultats dans ~30km, triés par distance
  //   2. Si aucun résultat dans les 30km → élargit à tout le pool, toujours triés par distance
  //   3. Sans GPS → ordre tel quel (BDD d'abord, puis Nominatim)
  mergeResults(dbVenues, nominatimVenues) {
    // Fusionne BDD + Nominatim en éliminant les doublons exacts (même nom + même ville).
    // On utilise une déduplication EXACTE (après normalisation) plutôt qu'un préfixe approximatif.
    //
    // Pourquoi ?
    // Avec un préfixe de 6 chars ("le fiv"), "Le Five Bordeaux" (Nominatim) était éliminé
    // car "le five / complexe multisports" (BDD, Périgy) contient aussi "le fiv".
    // Résultat : Le Five Bordeaux disparaissait des suggestions même avec GPS actif.
    //
    // Avec la déduplication exacte (nom+ville), deux venues de noms différents
    // ne se dédupliquent plus entre elles, même si elles partagent un début commun.
    const seen = new Set()
    const allVenues = [...dbVenues, ...nominatimVenues].filter(v => {
      // Clé : nom normalisé + ville normalisée (insensible à la casse)
      const key = v.name.toLowerCase().trim() + "|" + v.city.toLowerCase().trim()
      if (seen.has(key)) return false
      seen.add(key)
      return true
    })

    if (this.userLat && this.userLon) {
      const lat = this.userLat
      const lon = this.userLon

      // Calcule la distance (euclidienne au carré) pour chaque résultat
      const withDistance = allVenues
        .filter(v => v.latitude && v.longitude)  // Ignore les entrées sans coordonnées
        .map(v => ({
          ...v,
          _dist: (v.latitude - lat) ** 2 + (v.longitude - lon) ** 2
        }))

      // delta² correspondant à ~30km (0.27° ≈ 30km → 0.27² ≈ 0.0729)
      const delta30km = 0.27 * 0.27

      // Étape 1 : uniquement les résultats dans les ~30km, triés du plus proche au plus loin
      let nearby = withDistance.filter(v => v._dist <= delta30km)
      nearby.sort((a, b) => a._dist - b._dist)

      // Étape 2 : si aucun résultat proche → on prend tout, toujours triés par distance
      if (nearby.length === 0) {
        withDistance.sort((a, b) => a._dist - b._dist)
        return withDistance.slice(0, 8)
      }

      return nearby.slice(0, 8)
    }

    // Pas de GPS → on retourne les 8 premiers sans tri particulier
    return allVenues.slice(0, 8)
  }

  // ── AFFICHAGE DU DROPDOWN ───────────────────────────────────────────────────
  showResults(venues, query = "") {
    const myPositionItem = this.buildMyPositionItem()

    // Bouton fallback "Utiliser [texte] comme adresse" — affiché en bas si l'user a tapé
    const freeTextItem = query.length >= 3 ? `
      <button
        type="button"
        class="dropdown-item py-2"
        style="border-top: 1px solid rgba(255,255,255,0.08);"
        data-action="click->place-search#useFreeText"
        data-free-text="${this.escapeAttr(query)}"
      >
        <div class="d-flex align-items-center gap-2">
          <span>✏️</span>
          <div style="font-size:0.85rem;">
            Utiliser <span class="fw-semibold">"${this.escapeHtml(query)}"</span> comme adresse
          </div>
        </div>
      </button>
    ` : ""

    if (venues.length === 0) {
      this.dropdownTarget.innerHTML = myPositionItem + `
        <div class="px-3 py-2" style="font-size:0.85rem; color:rgba(255,255,255,0.55);">
          Aucun établissement trouvé.
        </div>
      ` + freeTextItem
      this.dropdownTarget.style.display = "block"
      return
    }

    const items = venues.map(venue => {
      const addressParts = [venue.address, venue.postal_code, venue.city].filter(Boolean)
      const shortAddress = addressParts.join(", ")
      const fullValue    = shortAddress ? `${venue.name} - ${shortAddress}` : venue.name
      const icon         = this.getSportIcon(venue.sport_type)

      // Badge "OSM" discret pour les résultats venant de Nominatim (pas en BDD)
      const sourceBadge = venue._source === "osm"
        ? `<span style="font-size:0.65rem; color:rgba(255,255,255,0.4); margin-left:4px;">OSM</span>`
        : ""

      return `
        <button
          type="button"
          class="dropdown-item py-2"
          style="white-space:normal; border-bottom: 1px solid rgba(255,255,255,0.08);"
          data-action="click->place-search#selectResult"
          data-full-value="${this.escapeAttr(fullValue)}"
          data-venue-id="${venue.id || ""}"
        >
          <div class="d-flex align-items-start gap-2">
            <span>${icon}</span>
            <div>
              <div class="fw-semibold" style="font-size:0.9rem;">
                ${this.escapeHtml(venue.name)}${sourceBadge}
              </div>
              <div style="font-size:0.8rem; color:rgba(255,255,255,0.65);">
                ${this.escapeHtml(venue.sport_type || "")} · ${this.escapeHtml(shortAddress)}
              </div>
            </div>
          </div>
        </button>
      `
    })

    this.dropdownTarget.innerHTML = myPositionItem + items.join("") + freeTextItem
    this.dropdownTarget.style.display = "block"
  }

  // ── ACTIONS DE SÉLECTION ────────────────────────────────────────────────────

  // Sélection d'un résultat depuis le dropdown
  selectResult(event) {
    const button = event.target.closest("[data-full-value]")
    if (!button) return

    this.inputTarget.value = button.dataset.fullValue

    // venue_id : rempli si résultat BDD, vide si résultat OSM
    if (this.hasVenueIdTarget) {
      this.venueIdTarget.value = button.dataset.venueId || ""
    }

    this.hideDropdown()
  }

  // Validation du texte libre saisi (pas de venue en BDD)
  useFreeText(event) {
    const button = event.target.closest("[data-free-text]")
    if (!button) return

    this.inputTarget.value = button.dataset.freeText
    if (this.hasVenueIdTarget) this.venueIdTarget.value = ""
    this.hideDropdown()
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  // Construit le bouton "Ma position" (réutilisé à plusieurs endroits)
  buildMyPositionItem() {
    return `
      <button
        type="button"
        class="dropdown-item py-2"
        style="border-bottom: 1px solid rgba(255,255,255,0.08);"
        data-action="click->place-search#useMyPosition"
      >
        <div class="d-flex align-items-center gap-2">
          <span>📍</span>
          <div class="fw-semibold" style="font-size:0.9rem;">Ma position</div>
        </div>
      </button>
    `
  }

  // Emoji selon le type d'équipement (données BDD) ou le type OSM (Nominatim)
  getSportIcon(sportType) {
    if (!sportType) return "🏟️"
    const type = sportType.toLowerCase()

    if (type.includes("football") || type.includes("foot") || type.includes("pitch")) return "⚽"
    if (type.includes("tennis"))                                                       return "🎾"
    if (type.includes("basket"))                                                       return "🏀"
    if (type.includes("natation") || type.includes("bassin") ||
        type.includes("piscine")  || type.includes("pool"))                            return "🏊"
    if (type.includes("rugby"))                                                        return "🏉"
    if (type.includes("volley"))                                                       return "🏐"
    if (type.includes("gym") || type.includes("fitness") ||
        type.includes("musculation") || type.includes("fitness_centre"))               return "💪"
    if (type.includes("boxe") || type.includes("combat") ||
        type.includes("judo") || type.includes("martial"))                             return "🥊"
    if (type.includes("athletisme") || type.includes("piste") ||
        type.includes("parcours") || type.includes("track"))                           return "🏃"
    if (type.includes("golf"))                                                         return "⛳"
    if (type.includes("padel") || type.includes("squash"))                             return "🏓"
    if (type.includes("escalade") || type.includes("sae"))                             return "🧗"
    if (type.includes("salle") || type.includes("gymnase") ||
        type.includes("multisports") || type.includes("sports_centre"))                return "🏋️"

    return "🏟️"
  }

  showError(message) {
    this.dropdownTarget.innerHTML = `
      <div class="px-3 py-2 text-danger small">${message}</div>
    `
    this.dropdownTarget.style.display = "block"
  }

  hideDropdown() {
    this.dropdownTarget.style.display = "none"
    this.dropdownTarget.innerHTML = ""
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) this.hideDropdown()
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
}
