// ══════════════════════════════════════════════════════════════
// Contrôleur Stimulus : map-picker
// ══════════════════════════════════════════════════════════════
// Rôle : permettre à l'utilisateur de pinpointer un lieu précis
// sur une carte OpenStreetMap quand la recherche texte ne suffit pas
// (terrain privé, coin de rue, lieu informel, etc.)
//
// Flux :
//   1. L'user clique "Choisir sur la carte" → modale Bootstrap s'ouvre
//   2. La carte Leaflet s'initialise dans la modale (après shown.bs.modal)
//   3. L'user clique sur la carte → marker vert + reverse geocode Nominatim
//   4. L'user clique "Confirmer" → remplit le champ :place du formulaire
//      + crée la venue en BDD via /venues/find_or_create
//
// Dépendances :
//   - Leaflet.js (importmap : "leaflet")
//   - Bootstrap Modal (déjà chargé globalement)
//   - Nominatim / OpenStreetMap (reverse geocoding, déjà utilisé dans place_search)
//   - /venues/find_or_create (endpoint Rails existant)
// ══════════════════════════════════════════════════════════════

import { Controller } from "@hotwired/stimulus"
// Leaflet exporte ses symboles en named exports (pas de default export dans l'ESM build).
// → on importe tout sous le namespace L pour retrouver L.map(), L.tileLayer(), etc.
import * as L from "leaflet"

export default class extends Controller {

  // ── Targets ────────────────────────────────────────────────
  // mapContainer  → le div où Leaflet monte la carte
  // confirmBtn    → le bouton "Confirmer ce lieu"
  // addressDisplay → la zone qui affiche l'adresse reverse-géocodée
  static targets = ["mapContainer", "confirmBtn", "addressDisplay", "searchInput"]

  // ── Values ─────────────────────────────────────────────────
  // Stockent la position et l'adresse du point sélectionné
  static values = {
    lat:     Number,  // Latitude du point cliqué
    lng:     Number,  // Longitude du point cliqué
    address: String   // Adresse reverse-géocodée (ou coordonnées brutes)
  }

  // ── connect() : appelé quand l'élément (la modale) entre dans le DOM ──────
  connect() {
    this.map             = null   // Instance Leaflet — créée uniquement au premier open
    this.marker          = null   // Marker posé par l'user sur la carte
    this._createMapTimer = null   // Référence du setTimeout en attente (pour pouvoir l'annuler)

    // Leaflet doit être initialisé APRÈS que la modale soit entièrement visible
    // (le conteneur doit avoir des dimensions calculées, sinon la carte est vide).
    // L'événement Bootstrap "shown.bs.modal" se déclenche après la fin de l'animation d'ouverture.
    this._onModalShown = () => this._initOrRefreshMap()
    this.element.addEventListener("shown.bs.modal", this._onModalShown)
  }

  // ── disconnect() : nettoyage quand la modale quitte le DOM ────────────────
  disconnect() {
    this.element.removeEventListener("shown.bs.modal", this._onModalShown)

    // Annule le timer si la modale quitte le DOM avant la fin du délai
    if (this._createMapTimer) {
      clearTimeout(this._createMapTimer)
      this._createMapTimer = null
    }

    // Détruit la carte Leaflet pour libérer la mémoire et les event listeners
    if (this.map) {
      this.map.remove()
      this.map    = null
      this.marker = null
    }
  }

  // ── _initOrRefreshMap() : recrée la carte Leaflet à chaque ouverture ───────
  // Appelée à chaque ouverture de la modale (événement shown.bs.modal).
  //
  // POURQUOI détruire et recréer plutôt qu'appeler invalidateSize() ?
  //
  // Problème : quand Leaflet initialise dans une modale Bootstrap avec
  // modal-dialog-centered (flex), les tuiles se découpent en 2-3 panneaux
  // qui se superposent. Cela vient d'un mauvais calcul de la taille du conteneur
  // au moment de la première création (valeurs fractionnaires, layout flex non finalisé).
  //
  // invalidateSize() ne suffit pas : les tuiles déjà chargées avec de mauvaises
  // coordonnées de transform3d ne sont pas rechargées — elles restent décalées.
  //
  // Solution : on détruit complètement la carte à chaque fermeture/réouverture,
  // et on la recrée après 100ms. Ce délai laisse Bootstrap finir son layout flex
  // (shown.bs.modal se déclenche à la fin de l'animation CSS, mais le reflow
  // du centrage vertical peut prendre quelques frames supplémentaires).
  _initOrRefreshMap() {
    // Annule tout timer précédent : si shown.bs.modal se déclenche deux fois rapidement
    // (edge case Bootstrap), on ne veut pas créer deux instances Leaflet sur le même conteneur
    if (this._createMapTimer) {
      clearTimeout(this._createMapTimer)
    }

    // Destruction de la carte précédente — repartir d'une instance fraîche
    // garantit que Leaflet mesurera le conteneur avec ses vraies dimensions finales
    if (this.map) {
      this.map.remove()
      this.map    = null
      this.marker = null
    }

    // 100ms : laisse le navigateur finaliser le reflow du layout Bootstrap
    // avant que Leaflet mesure offsetWidth/offsetHeight du conteneur
    this._createMapTimer = setTimeout(() => {
      this._createMapTimer = null
      this._createMap()
    }, 100)
  }

  _createMap() {
    const container = this.mapContainerTarget

    // Nettoyage de tout résidu Leaflet sur le conteneur.
    // Cas typique : Turbo Drive a restauré un snapshot de page qui contient déjà
    // les divs Leaflet (.leaflet-map-pane etc.) d'une session précédente.
    // Sans ce nettoyage, L.map() lève "Map container is already initialized."
    if (container._leaflet_id) {
      container.innerHTML = ""          // Supprime les divs Leaflet orphelins
      delete container._leaflet_id     // Réinitialise le marqueur d'initialisation Leaflet
    }

    // Crée la carte centrée sur la France par défaut (zoom 6 = vue nationale)
    this.map = L.map(container, {
      zoomControl: true   // Boutons + / - visibles
    }).setView([46.6, 2.4], 6)

    // Tuiles OpenStreetMap — gratuites, sans API key
    // Attribution obligatoire selon les CGU OpenStreetMap
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19
    }).addTo(this.map)

    // Recalcule les dimensions une fois les tuiles chargées, au cas où le layout
    // Bootstrap se serait stabilisé entre la création de la carte et le premier rendu
    this.map.whenReady(() => {
      this.map.invalidateSize({ animate: false })
    })

    // Clic sur la carte → dépose un marker + lance le reverse geocode
    this.map.on("click", (e) => this._handleMapClick(e))

    // Zoom automatique sur la position GPS de l'utilisateur dès l'ouverture de la modale.
    // map.locate() est l'API native Leaflet — plus simple que navigator.geolocation.
    // setView:true  → Leaflet recentre automatiquement quand la position est trouvée
    // maxZoom:13    → ne zoome pas plus que le niveau quartier (suffisant pour un terrain)
    // Silencieux si l'user refuse la géolocalisation ou si le navigateur ne la supporte pas.
    this.map.once("locationfound", (e) => {
      // Garde : si la modale a été fermée avant que la géolocalisation réponde,
      // this.map peut avoir été détruit → on vérifie qu'il existe encore
      if (this.map) this.map.setView(e.latlng, 13)
    })
    this.map.locate({ setView: false, maxZoom: 13 })
    // setView:false + handler manuel ci-dessus → permet le guard de sécurité sur this.map
  }

  // ── _handleMapClick() : pose un marker et lance le reverse geocode ────────
  // Appelée à chaque clic sur la carte Leaflet.
  async _handleMapClick(e) {
    const { lat, lng } = e.latlng

    // Supprime l'ancien marker s'il y en a un (un seul marker à la fois)
    if (this.marker) this.marker.remove()

    // Marker custom vert — cohérent avec le design de l'app (pas de PNG externe)
    const icon = L.divIcon({
      html: `<div style="
        width: 20px; height: 20px;
        background: #1EDD88;
        border-radius: 50%;
        border: 3px solid #fff;
        box-shadow: 0 2px 8px rgba(0,0,0,0.45);
      "></div>`,
      iconSize:   [20, 20],
      iconAnchor: [10, 10],  // Centre du cercle = point exact cliqué
      className:  ""         // Supprime la classe CSS par défaut de Leaflet
    })

    this.marker = L.marker([lat, lng], { icon }).addTo(this.map)

    // Feedback visuel : indique que la recherche d'adresse est en cours
    this.addressDisplayTarget.textContent = "Recherche de l'adresse…"
    this.confirmBtnTarget.disabled = true   // Désactive "Confirmer" pendant la recherche

    // Reverse geocode via Nominatim (même API que place_search_controller.js)
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&accept-language=fr`,
        { headers: { "User-Agent": "TeamsUpApp/1.0" } }
      )
      const data = await res.json()

      // Construit une adresse lisible à partir des champs Nominatim
      const addr     = data.address || {}
      const name     = data.name || ""                                            // Nom du lieu (stade, salle...)
      const road     = addr.road || addr.pedestrian || addr.path || ""            // Rue
      const city     = addr.city || addr.town || addr.village || addr.municipality || ""  // Ville
      const postcode = addr.postcode || ""                                        // Code postal

      // Filtre les parties vides avant de les assembler
      const parts = [name, road, postcode, city].filter(Boolean)
      // Fallback sur les coordonnées brutes si Nominatim ne renvoie rien d'utile
      this.addressValue = parts.join(", ") || `${lat.toFixed(5)}, ${lng.toFixed(5)}`

    } catch {
      // Si Nominatim est inaccessible, on utilise les coordonnées brutes
      this.addressValue = `${lat.toFixed(5)}, ${lng.toFixed(5)}`
    }

    // Stocke les coordonnées pour find_or_create
    this.latValue = lat
    this.lngValue = lng

    // Affiche l'adresse trouvée + active le bouton "Confirmer"
    this.addressDisplayTarget.textContent = this.addressValue
    this.confirmBtnTarget.disabled = false
  }

  // ── searchAddress() : géocode une adresse et centre la carte ────────────
  // Appelée par le bouton "Centrer" ou la touche Entrée dans le champ de recherche.
  // Utilise Nominatim (même API que le reverse geocode) pour trouver les coordonnées.
  // L'user peut ensuite cliquer précisément sur la carte pour confirmer le lieu.
  async searchAddress() {
    const query = this.searchInputTarget.value.trim()
    if (!query || !this.map) return  // Rien à faire si le champ est vide ou la carte absente

    // Feedback visuel : indique que la recherche est en cours
    this.searchInputTarget.disabled = true

    try {
      // Geocodage direct : texte libre → coordonnées GPS
      // limit=1 : on ne récupère que le meilleur résultat
      const res = await fetch(
        `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=1&accept-language=fr`,
        { headers: { "User-Agent": "TeamsUpApp/1.0" } }
      )
      const data = await res.json()

      if (data.length > 0) {
        // Nominatim retourne lat/lon en string → on les convertit en Number
        const lat = parseFloat(data[0].lat)
        const lon = parseFloat(data[0].lon)

        // Zoom 14 = vue de rue : précis mais garde assez de contexte pour choisir un terrain
        this.map.setView([lat, lon], 14)
      }
      // Pas de résultat → on ne fait rien, l'user peut reformuler sa recherche

    } catch {
      // Erreur réseau silencieuse — l'user peut réessayer
    } finally {
      // Réactive le champ dans tous les cas (succès ou erreur)
      this.searchInputTarget.disabled = false
      this.searchInputTarget.focus()
    }
  }

  // ── confirmLocation() : valide le lieu et remplit le formulaire ───────────
  // Appelée par le clic sur le bouton "Confirmer ce lieu".
  async confirmLocation() {
    if (!this.addressValue) return

    // 1. Remplit le champ texte visible du lieu (data-place-search-target="input")
    const placeInput = document.querySelector('[data-place-search-target="input"]')
    if (placeInput) {
      placeInput.value = this.addressValue
      // Dispatch "input" → match-form#updatePlace met à jour le récapitulatif en temps réel
      placeInput.dispatchEvent(new Event("input", { bubbles: true }))
    }

    // 2. Réinitialise le champ venue_id caché (sera mis à jour juste après)
    const venueIdInput = document.querySelector('[data-place-search-target="venueId"]')
    if (venueIdInput) venueIdInput.value = ""

    // 3. Crée ou retrouve la venue en BDD via l'endpoint existant /venues/find_or_create
    //    → permet que ce lieu soit retrouvable dans les lieux favoris du profil aussi
    if (this.latValue && this.lngValue) {
      const id = await this._findOrCreateVenue({
        name:      this.addressValue,
        city:      "",               // L'adresse complète est dans `name`
        address:   this.addressValue,
        latitude:  this.latValue,
        longitude: this.lngValue
      })
      if (venueIdInput && id) venueIdInput.value = id
    }

    // 4. Ferme la modale Bootstrap proprement (libère le backdrop)
    const modal = bootstrap.Modal.getInstance(this.element)
    if (modal) modal.hide()
  }

  // ── _findOrCreateVenue() : persiste la venue en BDD ──────────────────────
  // Identique à findOrCreateVenue() dans place_search_controller.js.
  // Retourne l'ID Rails de la venue, ou null en cas d'erreur réseau.
  async _findOrCreateVenue(venueData) {
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const response  = await fetch("/venues/find_or_create", {
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
      return null  // Erreur réseau silencieuse — le formulaire reste utilisable
    }
  }
}
