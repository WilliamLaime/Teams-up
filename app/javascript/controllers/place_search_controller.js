// Controller Stimulus pour la recherche de lieu avec dropdown
// Utilise l'API gratuite Nominatim (OpenStreetMap) — pas de clé API nécessaire
// Améliorations :
//   - Géolocalisation du navigateur pour prioriser les résultats proches
//   - Tri des établissements sportifs en premier
//   - Adresse affichée plus courte et lisible

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "input"    → le champ texte de saisie
  // "dropdown" → le div qui affiche les suggestions
  static targets = ["input", "dropdown"]

  connect() {
    this.timeout = null    // Pour le debounce
    this.userLat = null    // Latitude de l'utilisateur (si géolocalisation accordée)
    this.userLon = null    // Longitude de l'utilisateur

    // Ferme le dropdown si on clique ailleurs sur la page
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)

    // Demande la position de l'utilisateur en arrière-plan
    // Si l'utilisateur refuse, on continue sans géolocalisation (résultats non filtrés géographiquement)
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.userLat = position.coords.latitude
          this.userLon = position.coords.longitude
        },
        () => { /* Permission refusée ou indisponible — on ignore */ }
      )
    }
  }

  disconnect() {
    // Nettoyage quand le controller est retiré du DOM
    document.removeEventListener("click", this.handleOutsideClick)
    clearTimeout(this.timeout)
  }

  // Appelé à chaque frappe dans le champ (data-action="input->place-search#search")
  search() {
    clearTimeout(this.timeout) // Annule la recherche précédente si on tape vite

    const query = this.inputTarget.value.trim()

    // Pas de recherche si moins de 3 caractères
    if (query.length < 3) {
      this.hideDropdown()
      return
    }

    // Attend 350ms après la dernière frappe avant de lancer la requête (debounce)
    this.timeout = setTimeout(() => {
      this.fetchResults(query)
    }, 350)
  }

  // Envoie la requête à l'API Nominatim
  async fetchResults(query) {
    try {
      // Paramètres de base de la requête
      const params = new URLSearchParams({
        q: query,
        format: "json",
        addressdetails: "1",   // Retourne les détails d'adresse (ville, CP, rue...)
        namedetails: "1",      // Retourne le nom officiel du lieu
        limit: "8",            // Maximum 8 résultats
        "accept-language": "fr",
        countrycodes: "fr",    // Limiter les résultats à la France
      })

      // Si la géolocalisation est disponible, ajoute une "viewbox" (zone de priorité)
      // Nominatim privilégie les résultats dans cette zone, sans les exclure complètement
      if (this.userLat && this.userLon) {
        // Zone de ~100km autour de l'utilisateur (1 degré ≈ 111 km)
        const delta = 1.0
        const minLon = this.userLon - delta
        const maxLat = this.userLat + delta
        const maxLon = this.userLon + delta
        const minLat = this.userLat - delta
        params.append("viewbox", `${minLon},${maxLat},${maxLon},${minLat}`)
        params.append("bounded", "0") // 0 = résultats hors zone aussi retournés, mais moins prioritaires
      }

      const url = `https://nominatim.openstreetmap.org/search?${params.toString()}`

      const response = await fetch(url, {
        headers: {
          "Accept-Language": "fr",
          "User-Agent": "TeamUpApp/1.0" // Nominatim demande un User-Agent identifiable
        }
      })

      if (!response.ok) return

      const data = await response.json()

      // Trie les résultats pour mettre les établissements sportifs en premier
      const sorted = this.sortBySportsRelevance(data)
      this.showResults(sorted, query)

    } catch (error) {
      // En cas d'erreur réseau, on n'affiche rien (le champ reste utilisable manuellement)
      console.error("Erreur recherche lieu:", error)
    }
  }

  // Trie les résultats pour mettre les établissements sportifs/loisirs en tête de liste
  sortBySportsRelevance(results) {
    // Types OSM considérés comme sportifs
    const sportsTypes = [
      "sports_centre", "stadium", "leisure_centre", "fitness_centre",
      "pitch", "track", "swimming_pool", "golf_course",
      "tennis", "volleyball", "basketball", "padel"
    ]
    // Classes OSM considérées comme sportives
    const sportsClasses = ["leisure", "sport"]

    return results.sort((a, b) => {
      const aIsSports = sportsClasses.includes(a.class) || sportsTypes.includes(a.type)
      const bIsSports = sportsClasses.includes(b.class) || sportsTypes.includes(b.type)

      if (aIsSports && !bIsSports) return -1  // a avant b
      if (!aIsSports && bIsSports) return 1   // b avant a
      return 0                                 // égalité, ordre inchangé
    })
  }

  // Affiche les résultats dans le dropdown
  showResults(results, query) {
    if (results.length === 0) {
      // Aucun résultat : on propose quand même la saisie libre
      this.dropdownTarget.innerHTML = `
        <div class="px-3 py-2 text-muted small">
          Aucun résultat — tu peux saisir ton lieu manuellement.
        </div>
      `
      this.dropdownTarget.style.display = "block"
      return
    }

    // Construit les lignes du dropdown
    const items = results.map(result => {
      // Nom du lieu : préfère le nom officiel OSM, sinon le premier segment du display_name
      const name = result.namedetails?.name || result.name || result.display_name.split(",")[0].trim()

      // Adresse courte et lisible : rue + code postal + ville
      const addr = result.address || {}
      const road     = addr.road || addr.pedestrian || ""
      const postcode = addr.postcode || ""
      const city     = addr.city || addr.town || addr.village || addr.municipality || ""
      const shortAddress = [road, postcode, city].filter(Boolean).join(", ")

      // Valeur insérée dans le champ quand on clique : "Nom - Adresse"
      const fullValue = shortAddress ? `${name} - ${shortAddress}` : name

      // Emoji selon le type d'établissement
      const icon = this.getSportsIcon(result)

      return `
        <button
          type="button"
          class="dropdown-item py-2"
          style="white-space:normal; border-bottom: 1px solid #f0f0f0;"
          data-action="click->place-search#selectResult"
          data-full-value="${this.escapeAttr(fullValue)}"
        >
          <div class="d-flex align-items-start gap-2">
            <span>${icon}</span>
            <div>
              <div class="fw-semibold" style="font-size:0.9rem;">${this.escapeHtml(name)}</div>
              <div class="text-muted" style="font-size:0.78rem;">${this.escapeHtml(shortAddress)}</div>
            </div>
          </div>
        </button>
      `
    })

    this.dropdownTarget.innerHTML = items.join("")
    this.dropdownTarget.style.display = "block"
  }

  // Retourne un emoji selon le type OSM du lieu
  getSportsIcon(result) {
    const type = result.type || ""
    const cls  = result.class || ""

    if (["sports_centre", "leisure_centre", "stadium"].includes(type)) return "🏟️"
    if (["fitness_centre", "gym"].includes(type))                       return "💪"
    if (["swimming_pool"].includes(type))                               return "🏊"
    if (["pitch", "track"].includes(type))                              return "⚽"
    if (cls === "leisure" || cls === "sport")                           return "🏃"
    return "📍"
  }

  // Appelé quand l'utilisateur clique sur un résultat
  selectResult(event) {
    // Remonte jusqu'au bouton si on a cliqué sur un élément enfant (div, span...)
    const button = event.target.closest("[data-full-value]")
    if (!button) return

    this.inputTarget.value = button.dataset.fullValue // Insère la valeur dans le champ
    this.hideDropdown()
  }

  hideDropdown() {
    this.dropdownTarget.style.display = "none"
    this.dropdownTarget.innerHTML = ""
  }

  // Ferme le dropdown si on clique en dehors du controller
  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.hideDropdown()
    }
  }

  // Échappe les caractères spéciaux pour affichage HTML sûr (anti-XSS)
  escapeHtml(text) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(String(text)))
    return div.innerHTML
  }

  // Échappe les caractères spéciaux pour un attribut HTML (data-*)
  escapeAttr(text) {
    return String(text).replace(/"/g, "&quot;").replace(/'/g, "&#39;")
  }
}
