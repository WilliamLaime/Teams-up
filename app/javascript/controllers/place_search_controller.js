// Controller Stimulus pour la recherche de lieu avec dropdown
// Utilise l'API gratuite Nominatim (OpenStreetMap) — pas de clé API nécessaire
// Améliorations :
//   - Géolocalisation uniquement quand l'utilisateur clique "Ma position"
//   - "Ma position" toujours proposé en 1ère option du dropdown
//   - Tri des établissements sportifs en premier
//   - Adresse affichée plus courte et lisible

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "input"    → le champ texte de saisie
  // "dropdown" → le div qui affiche les suggestions
  static targets = ["input", "dropdown"]

  connect() {
    this.timeout = null    // Pour le debounce
    this.userLat = null    // Latitude de l'utilisateur (rempli seulement si géoloc accordée)
    this.userLon = null    // Longitude de l'utilisateur

    // Ferme le dropdown si on clique ailleurs sur la page
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    document.addEventListener("click", this.handleOutsideClick)

    // ⚠️ On ne demande plus la position ici au chargement.
    // La géolocalisation est déclenchée uniquement quand l'utilisateur
    // clique sur "Ma position" dans le dropdown (méthode useMyPosition).
  }

  disconnect() {
    // Nettoyage quand le controller est retiré du DOM
    document.removeEventListener("click", this.handleOutsideClick)
    clearTimeout(this.timeout)
  }

  // Appelé quand l'input reçoit le focus (data-action="focus->place-search#showDefault")
  // Affiche le dropdown avec "Ma position" en premier, sauf si l'utilisateur a déjà tapé 3+ caractères
  showDefault() {
    const query = this.inputTarget.value.trim()
    // Si l'utilisateur a déjà tapé quelque chose, on ne remplace pas les résultats existants
    if (query.length >= 3) return
    this.showMyPositionOption()
  }

  // Appelé à chaque frappe dans le champ (data-action="input->place-search#search")
  search() {
    clearTimeout(this.timeout) // Annule la recherche précédente si on tape vite

    const query = this.inputTarget.value.trim()

    // Moins de 3 caractères : on affiche juste "Ma position" sans rechercher
    if (query.length < 3) {
      this.showMyPositionOption()
      return
    }

    // Attend 350ms après la dernière frappe avant de lancer la requête (debounce)
    this.timeout = setTimeout(() => {
      this.fetchResults(query)
    }, 350)
  }

  // Affiche un dropdown avec uniquement l'option "Ma position"
  showMyPositionOption() {
    this.dropdownTarget.innerHTML = `
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
    this.dropdownTarget.style.display = "block"
  }

  // Appelé quand l'utilisateur clique sur "Ma position"
  // Déclenche la géolocalisation du navigateur (c'est ici que la permission est demandée)
  async useMyPosition() {
    // Vérifie que le navigateur supporte la géolocalisation
    if (!navigator.geolocation) {
      this.showError("La géolocalisation n'est pas disponible sur ce navigateur.")
      return
    }

    // Affiche un état de chargement dans l'input
    this.inputTarget.value = "Localisation en cours…"
    this.inputTarget.disabled = true
    this.hideDropdown()

    // Demande la position — c'est ici que le navigateur affiche la popup de permission
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        // Succès : on a les coordonnées
        const lat = position.coords.latitude
        const lon = position.coords.longitude

        // On mémorise la position pour les recherches suivantes (meilleure pertinence)
        this.userLat = lat
        this.userLon = lon

        // On fait un reverse geocoding pour obtenir une adresse lisible
        try {
          const response = await fetch(
            `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&accept-language=fr`,
            { headers: { "User-Agent": "TeamUpApp/1.0" } }
          )
          const data = await response.json()

          // Construit une adresse courte et lisible
          const addr = data.address || {}
          const road     = addr.road || addr.pedestrian || addr.suburb || ""
          const postcode = addr.postcode || ""
          const city     = addr.city || addr.town || addr.village || ""
          const shortAddress = [road, postcode, city].filter(Boolean).join(", ")

          // Remplit l'input avec l'adresse obtenue
          this.inputTarget.value = shortAddress || data.display_name.split(",").slice(0, 3).join(",").trim()

        } catch (error) {
          // Erreur réseau : on laisse le champ vide
          this.inputTarget.value = ""
          console.error("Erreur reverse geocoding:", error)
        }

        this.inputTarget.disabled = false
      },
      () => {
        // Permission refusée ou erreur : on remet le champ vide
        this.inputTarget.value = ""
        this.inputTarget.disabled = false
        this.showError("Impossible d'obtenir votre position. Veuillez saisir votre lieu manuellement.")
      }
    )
  }

  // Affiche un message d'erreur dans le dropdown
  showError(message) {
    this.dropdownTarget.innerHTML = `
      <div class="px-3 py-2 text-danger small">${message}</div>
    `
    this.dropdownTarget.style.display = "block"
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

      // Si la géolocalisation a déjà été utilisée, ajoute une "viewbox" (zone de priorité)
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

  // Affiche les résultats dans le dropdown, avec "Ma position" toujours en premier
  showResults(results, query) {
    // Option "Ma position" toujours en tête du dropdown
    const myPositionItem = `
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

    if (results.length === 0) {
      // Aucun résultat : on propose "Ma position" + saisie libre
      this.dropdownTarget.innerHTML = myPositionItem + `
        <div class="px-3 py-2 text-muted small">
          Aucun résultat — tu peux saisir ton lieu manuellement.
        </div>
      `
      this.dropdownTarget.style.display = "block"
      return
    }

    // Construit les lignes du dropdown pour chaque résultat
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
          style="white-space:normal; border-bottom: 1px solid rgba(255,255,255,0.08);"
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

    // "Ma position" en 1er, puis les résultats de recherche
    this.dropdownTarget.innerHTML = myPositionItem + items.join("")
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
