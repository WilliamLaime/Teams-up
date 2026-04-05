// ══════════════════════════════════════════════════════════════
// Contrôleur Stimulus : match-form
// ══════════════════════════════════════════════════════════════
// Rôle : mettre à jour le récapitulatif (sidebar droite) en temps
// réel pendant que l'utilisateur remplit le formulaire.
//
// Comment ça marche ?
//   1. Les champs du formulaire ont un attribut data-match-form-target="..."
//      → Stimulus les rend accessibles via this.xxxTarget
//   2. Les champs ont aussi data-action="input->match-form#updateXxx"
//      → Stimulus appelle la méthode quand l'utilisateur tape/change
//   3. Les éléments du récap ont aussi des targets (recapTitle, etc.)
//      → la méthode lit la valeur du champ et l'écrit dans le récap
// ══════════════════════════════════════════════════════════════

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ── Déclaration des targets ────────────────────────────────
  // Stimulus crée automatiquement this.xxxTarget pour chaque nom déclaré ici.
  // Ces noms correspondent aux attributs data-match-form-target="xxx" dans le HTML.
  static targets = [
    // ── Champs du formulaire (sources de données) ──────────
    "titleInput",        // Champ texte : titre du match
    "descriptionInput",  // Textarea : description
    "placeInput",        // Champ texte : lieu (avec autocomplete)
    "dateInput",         // Champ date
    "sportInput",        // Select sport : déclenche updateSport au changement
    "playersInput",      // Input caché : nombre de joueurs manquants (partagé standard + libre)
    "playersCount",      // Span visible : chiffre du compteur standard affiché à l'écran
    "minusBtn",          // Bouton "−" du compteur standard (pour changer sa couleur)
    "plusBtn",           // Bouton "+" du compteur standard (pour changer sa couleur)
    "levelInput",        // Input caché : niveau sélectionné (mis à jour par les boutons)
    "validationToggle",  // Checkbox du toggle Manuel/Automatique
    "priceInput",        // Champ numérique : prix par joueur
    "bannerImageInput",  // Input caché : URL de l'image de la banner (soumise avec le formulaire)

    // ── Format ────────────────────────────────────────────
    "formatWrapper",     // Div englobant les boutons de format
    "formatInput",       // Input caché : valeur du format soumise avec le formulaire
    "formatButtons",     // Div recevant les boutons de format générés dynamiquement
    "recapFormatRow",    // Ligne "Format" dans le récap
    "recapFormat",       // Valeur du format dans la ligne récap

    // ── Sections joueurs : standard vs Libre ─────────────
    "standardPlayerSection",  // Div compteur unique "manquants" (caché en mode Libre)
    "libreSection",           // Div deux compteurs présents + manquants (visible en mode Libre)

    // ── Champs Libre : saisie directe ──────────────────────
    "playersPresentInput",    // Input number : joueurs présents (players_present soumis)
    "playersLibreInput",      // Input number visible : joueurs manquants (synchronise playersInput)

    // ── Éléments du récapitulatif (destinations) ──────────
    "recapTitle",        // Zone affichant le titre dans la sidebar
    "recapDescription",  // Paragraphe affichant la description (masqué si vide)
    "recapSport",        // Valeur du sport dans la ligne récap
    "recapPlace",        // Valeur du lieu dans la ligne
    "recapDate",         // Zone affichant la date formatée
    "recapTime",         // Zone affichant l'heure (ex: 21h15)
    "recapPlayers",      // Zone affichant le nombre de joueurs
    "recapLevel",        // Valeur du niveau dans la ligne
    "recapValidation",   // Zone affichant le mode de validation (Manuel / Automatique)
    "recapPrice",        // Zone affichant le prix par joueur (en bas du récap, en blanc)
    "recapPresentRow",   // Ligne "Présents" dans le récap (visible uniquement en mode Libre)
    "recapPresent",      // Valeur "joueurs présents" dans la ligne récap
    "formCol",           // Colonne gauche (col-lg-7) — sert à mesurer son bas pour l'alignement

    // ── Boutons de niveau dynamiques (générés par JS selon le sport) ──
    "levelButtons"       // Div recevant les boutons de niveau générés dynamiquement
  ]

  // ── connect() : appelé automatiquement au chargement de la page ──
  // On initialise le récap avec les valeurs déjà présentes dans les champs
  // (utile lors de la modification d'un match existant)
  connect() {
    // Initialise le max de joueurs selon le sport déjà sélectionné (edit d'un match existant)
    // Par défaut 9 si aucun sport ou sport inconnu dans le mapping
    this.maxPlayers = this._maxForCurrentSport()

    this.updateTitle()
    this.updateDescription()
    // updateSport() appelle updateBanner() en interne
    this.updateSport()
    this.updatePlace()
    this.updateDate()
    this.updateTime()
    this.updatePlayers()
    this.updateLevel()
    this.updateValidation()
    this.updatePrice()
    // Initialise les couleurs des boutons − et + selon la valeur de départ
    this.updateCounterButtons(parseInt(this.playersInputTarget.value) || 4)
  }

  // ══════════════════════════════════════════════════════════
  // Méthodes de mise à jour du récapitulatif
  // Chacune lit la valeur d'un champ et l'écrit dans la sidebar
  // ══════════════════════════════════════════════════════════

  // ── Titre ─────────────────────────────────────────────────
  updateTitle() {
    const val = this.titleInputTarget.value.trim()
    if (val) {
      // Met uniquement la première lettre en majuscule, le reste en minuscules
      this.recapTitleTarget.textContent = val.charAt(0).toUpperCase() + val.slice(1).toLowerCase()
    } else {
      // Si le champ est vide, affiche le placeholder "Titre"
      this.recapTitleTarget.textContent = "Titre"
    }
  }

  // ── Description (tronquée à 80 caractères) ────────────────
  // Masque le paragraphe entier si la description est vide
  updateDescription() {
    const val = this.descriptionInputTarget.value.trim()
    if (val) {
      // Affiche la description tronquée à 80 caractères
      this.recapDescriptionTarget.textContent = val.length > 80 ? val.substring(0, 80) + "..." : val
      this.recapDescriptionTarget.style.display = ""   // visible
    } else {
      this.recapDescriptionTarget.textContent = ""
      this.recapDescriptionTarget.style.display = "none" // masqué
    }
  }

  // ── Banner : change le fond de .match-new-banner selon le sport ──
  // Choisit une image aléatoire dans le tableau du sport sélectionné.
  // Si aucun sport n'est sélectionné (ou sport inconnu), utilise l'image multisport.
  // Met à jour l'élément #match-new-banner (dans new.html.erb) + le champ caché
  updateBanner() {
    const select    = this.sportInputTarget
    const sportId   = select.value
    // Récupère la map { sportId => [url1, url2, ...] } passée en data-images
    const imagesMap = JSON.parse(select.dataset.images || "{}")
    const images    = imagesMap[sportId] || []

    // Fallback multisport : utilisé quand aucun sport n'est sélectionné ou inconnu dans la map
    const MULTISPORT_IMG = "https://res.cloudinary.com/dfw8rlluc/image/upload/v1775061666/sports/misc/multisports-img.png"

    // Choisit une image au hasard dans le tableau du sport, ou l'image multisport par défaut
    const randomImg = images.length > 0
      ? images[Math.floor(Math.random() * images.length)]
      : MULTISPORT_IMG

    // Met à jour le champ caché (sera sauvegardé en BDD à la soumission)
    this.bannerImageInputTarget.value = randomImg

    // Met à jour le fond de la banner dans new.html.erb (absent en edit → ok si null)
    const bannerEl = document.getElementById("match-new-banner")
    if (bannerEl) {
      // Garde le gradient sombre par-dessus l'image pour la lisibilité
      bannerEl.style.background = `linear-gradient(rgba(0,0,0,0.65), rgba(0,0,0,0.65)), url('${randomImg}') center 25% / cover no-repeat`
    }
  }

  // ── Sport : affiche les boutons de format + met à jour le récap ──
  updateSport() {
    const select  = this.sportInputTarget
    const sportId = select.value

    // Récupère les maps JSON passées en data-attributes sur le select
    const formatsMap = JSON.parse(select.dataset.formats     || "{}")
    const maxMap     = JSON.parse(select.dataset.maxPlayers  || "{}")
    const nameMap    = JSON.parse(select.dataset.sportNames  || "{}")

    if (sportId && formatsMap[sportId]) {
      const formats = formatsMap[sportId]

      // Met à jour le max global pour ce sport (compact exclut nil du format Libre)
      this.maxPlayers = maxMap[sportId] || 9

      // Met à jour le récap sport
      this.recapSportTarget.textContent = nameMap[sportId] || "—"

      // Tous les sports ont maintenant au moins 2 formats (sport-specific + Libre)
      // → le sélecteur de format est toujours affiché
      this._renderFormatButtons(formats)
      this.formatWrapperTarget.style.display = ""
      this.recapFormatRowTarget.style.display = ""

      // En mode édition, restaure le format sauvegardé ; sinon applique le premier format
      const savedFormat = this.formatInputTarget.value
      const allBtns     = this.formatButtonsTarget.querySelectorAll(".match-level-btn")
      const matchedFmt  = formats.find(f => f.label === savedFormat) || formats[0]
      const matchedBtn  = Array.from(allBtns).find(b => b.dataset.label === savedFormat) || allBtns[0]
      this._applyFormat(matchedFmt, matchedBtn)

      // Génère les boutons de niveau dynamiquement selon le sport
      const levelsMap  = JSON.parse(select.dataset.levels || "{}")
      const savedLevel = this.levelInputTarget.value
      if (levelsMap[sportId]) {
        this._renderLevelButtons(levelsMap[sportId], savedLevel)
      }

    } else {
      // Aucun sport sélectionné
      this.maxPlayers = 9
      this.recapSportTarget.textContent = "—"
      this.formatWrapperTarget.style.display = "none"
    }

    // Met à jour la banner selon le nouveau sport
    this.updateBanner()
  }

  // Génère les boutons de format dans le conteneur dédié
  _renderFormatButtons(formats) {
    const container = this.formatButtonsTarget
    container.innerHTML = ""

    formats.forEach((fmt, index) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "match-level-btn" + (index === 0 ? " active" : "")
      btn.textContent = fmt.label
      // dataset.players stocke "null" (string) pour le format Libre
      btn.dataset.players = fmt.players
      btn.dataset.label   = fmt.label
      // Styles inline garantis (évite tout conflit Bootstrap/navigateur)
      const isFirst = index === 0
      btn.style.setProperty("padding", "0.5rem 1.1rem")
      btn.style.setProperty("border-radius", "0.5rem")
      btn.style.setProperty("font-size", "0.9rem")
      btn.style.setProperty("cursor", "pointer")
      btn.style.setProperty("border", isFirst ? "2px solid #1EDD88" : "2px solid rgba(255,255,255,0.4)", "important")
      btn.style.setProperty("background", isFirst ? "rgba(30,221,136,0.12)" : "rgba(255,255,255,0.08)", "important")
      btn.style.setProperty("color", isFirst ? "#1EDD88" : "rgba(255,255,255,0.9)", "important")
      // Hover : vert au survol si non actif, retour à la normale en partant
      btn.addEventListener("mouseover", () => {
        if (!btn.classList.contains("active")) {
          btn.style.setProperty("border", "2px solid #1EDD88", "important")
          btn.style.setProperty("background", "rgba(30,221,136,0.08)", "important")
          btn.style.setProperty("color", "#1EDD88", "important")
        }
      })
      btn.addEventListener("mouseout", () => {
        if (!btn.classList.contains("active")) {
          btn.style.setProperty("border", "2px solid rgba(255,255,255,0.4)", "important")
          btn.style.setProperty("background", "rgba(255,255,255,0.08)", "important")
          btn.style.setProperty("color", "rgba(255,255,255,0.9)", "important")
        }
      })
      // Au clic : sélectionne ce format
      btn.addEventListener("click", () => this._applyFormat(fmt, btn))
      container.appendChild(btn)
    })
  }

  // Applique un format : met à jour le compteur, le max et l'input caché
  // Détecte si c'est le format Libre (players === null) pour basculer l'interface
  _applyFormat(fmt, clickedBtn = null) {
    // Met à jour l'input caché format (soumis avec le formulaire)
    this.formatInputTarget.value = fmt.label

    // Met à jour la ligne récap format
    this.recapFormatTarget.textContent = fmt.label

    // Détermine si c'est le format Libre (players vaut null ou undefined)
    const isLibre = fmt.players === null || fmt.players === undefined || fmt.players === "null"

    if (isLibre) {
      // ── Mode Libre : 2 compteurs indépendants, pas de max ──
      this.maxPlayers = 99 // limite pratique, sans contrainte réelle

      // Affiche la section Libre, cache la section standard
      this.libreSectionTarget.style.display     = ""
      this.standardPlayerSectionTarget.style.display = "none"

      // Affiche la ligne "Présents" dans le récap
      this.recapPresentRowTarget.style.display = ""

      // Initialise les deux compteurs avec les valeurs existantes (utile en mode édition)
      // Initialise les champs avec les valeurs existantes (utile en mode édition)
      const presentVal = parseInt(this.playersPresentInputTarget.value) || 1
      const libreVal   = parseInt(this.playersInputTarget.value) || 1

      // Pré-remplit les deux inputs visibles
      this.playersPresentInputTarget.value = presentVal
      this.playersLibreInputTarget.value   = libreVal
      // S'assure que le hidden field partagé est à jour
      this.playersInputTarget.value        = libreVal
      // Met à jour le récap
      this.recapPresentTarget.textContent  = presentVal
      this.recapPlayersTarget.textContent  = libreVal

    } else {
      // ── Mode standard : 1 compteur avec max défini par le format ──
      this.maxPlayers = fmt.players

      // Cache la section Libre, affiche la section standard
      this.libreSectionTarget.style.display         = "none"
      this.standardPlayerSectionTarget.style.display = ""

      // Cache la ligne "Présents" dans le récap
      this.recapPresentRowTarget.style.display = "none"

      // Efface players_present pour ne pas soumettre une valeur résiduelle
      // (évite que la validation Rails échoue sur un match repassé en format standard)
      this.playersPresentInputTarget.value = ""

      // Démarre toujours à 1 joueur manquant (l'utilisateur incrémente jusqu'au max)
      const count = 1
      this.playersInputTarget.value       = count
      this.playersCountTarget.textContent = count
      this.recapPlayersTarget.textContent = count
      this.updateCounterButtons(count)
    }

    // Met à jour l'état "active" des boutons de format avec styles inline
    if (clickedBtn) {
      this.formatButtonsTarget.querySelectorAll(".match-level-btn").forEach(b => {
        const isActive = b === clickedBtn
        b.classList.toggle("active", isActive)
        b.style.setProperty("border", isActive ? "2px solid #1EDD88" : "2px solid rgba(255,255,255,0.4)", "important")
        b.style.setProperty("background", isActive ? "rgba(30,221,136,0.12)" : "rgba(255,255,255,0.08)", "important")
        b.style.setProperty("color", isActive ? "#1EDD88" : "rgba(255,255,255,0.9)", "important")
      })
    }
  }

  // Appelé au clic sur un bouton de format (via event delegation)
  selectFormat(event) {
    const btn = event.currentTarget
    this._applyFormat({ label: btn.dataset.label, players: parseInt(btn.dataset.players) }, btn)
  }

  // Retourne le max de joueurs pour le sport actuellement sélectionné au chargement
  _maxForCurrentSport() {
    const select = this.sportInputTarget
    const maxMap = JSON.parse(select.dataset.maxPlayers || "{}")
    return maxMap[select.value] || 9
  }

  // ── Lieu ──────────────────────────────────────────────────
  updatePlace() {
    const val = this.placeInputTarget.value.trim()
    // Affiche la valeur ou rien si vide (la ligne reste toujours visible)
    this.recapPlaceTarget.textContent = val
  }

  // ── Date (format : "16 déc. 2026") ────────────────────────
  updateDate() {
    const val = this.dateInputTarget.value
    if (val) {
      // On ajoute "T00:00:00" pour forcer l'heure locale et éviter
      // le décalage UTC qui peut changer le jour affiché
      const date = new Date(val + "T00:00:00")
      const options = { day: "numeric", month: "short", year: "numeric" }
      // toLocaleDateString avec "fr-FR" donne "16 déc. 2026"
      this.recapDateTarget.textContent = date.toLocaleDateString("fr-FR", options)
    } else {
      this.recapDateTarget.textContent = "—"
    }
  }

  // ── Heure (format : "21h15") ──────────────────────────────
  // Les deux inputs cachés du time-picker ont des noms Rails prévisibles :
  //   match[time(4i)] → heures
  //   match[time(5i)] → minutes
  // On les trouve via l'attribut name (plus fiable que l'ID car Rails peut
  // ajouter un _ final à l'ID lors de la sanitisation des parenthèses)
  updateTime() {
    const hourEl   = this.element.querySelector('[name="match[time(4i)]"]')
    const minuteEl = this.element.querySelector('[name="match[time(5i)]"]')

    if (hourEl && minuteEl && hourEl.value !== "" && minuteEl.value !== "") {
      // padStart(2, "0") : force "9" → "09" pour avoir "09h00"
      const h = String(hourEl.value).padStart(2, "0")
      const m = String(minuteEl.value).padStart(2, "0")
      this.recapTimeTarget.textContent = `${h}h${m}`
    } else {
      this.recapTimeTarget.textContent = "—"
    }
  }

  // ── Nombre de joueurs standard : décrémenter ("-") ────────────────
  decrement() {
    const input = this.playersInputTarget
    const current = parseInt(input.value) || 1
    // Minimum : 1 joueur manquant
    if (current > 1) {
      const newVal = current - 1
      input.value = newVal
      this.playersCountTarget.textContent = newVal   // met à jour l'affichage du compteur
      this.recapPlayersTarget.textContent  = newVal  // met à jour le récap
      this.updateCounterButtons(newVal)              // met à jour les couleurs des boutons
    }
  }

  // ── Nombre de joueurs standard : incrémenter ("+") ────────────────
  increment() {
    const input = this.playersInputTarget
    const current = parseInt(input.value) || 1
    // Maximum dynamique selon le sport (this.maxPlayers, par défaut 9)
    const max = this.maxPlayers || 9
    if (current < max) {
      const newVal = current + 1
      input.value = newVal
      this.playersCountTarget.textContent = newVal
      this.recapPlayersTarget.textContent  = newVal
      this.updateCounterButtons(newVal)
    }
  }

  // ── Met à jour la couleur des boutons − et + du compteur standard ──
  // Règle :
  //   val = 1      → "-" gris (minimum atteint), "+" vert
  //   val = max    → "-" vert, "+" gris (maximum atteint)
  //   entre les deux → les deux verts
  updateCounterButtons(val) {
    const minus = this.minusBtnTarget
    const plus  = this.plusBtnTarget
    const max   = this.maxPlayers || 9

    minus.classList.remove("is-active", "is-disabled")
    plus.classList.remove("is-active", "is-disabled")

    if (val <= 1) {
      minus.classList.add("is-disabled")
      plus.classList.add("is-active")
    } else if (val >= max) {
      minus.classList.add("is-active")
      plus.classList.add("is-disabled")
    } else {
      minus.classList.add("is-active")
      plus.classList.add("is-active")
    }
  }

  // ── Synchroniser le récap avec la valeur actuelle (standard) ────────
  updatePlayers() {
    const val = this.playersInputTarget.value || "—"
    this.playersCountTarget.textContent = val
    this.recapPlayersTarget.textContent  = val
  }

  // ══════════════════════════════════════════════════════════
  // Champs Libre : saisie directe (pas de boutons +/-)
  // ══════════════════════════════════════════════════════════

  // Appelé à chaque frappe dans le champ "Présents" — met à jour le récap
  changePresent() {
    const val = Math.max(1, parseInt(this.playersPresentInputTarget.value) || 1)
    this.playersPresentInputTarget.value = val
    this.recapPresentTarget.textContent  = val
  }

  // Appelé à chaque frappe dans le champ "Manquants" — met à jour playersInput (hidden) + récap
  changeLibre() {
    const val = Math.max(1, parseInt(this.playersLibreInputTarget.value) || 1)
    this.playersLibreInputTarget.value  = val
    this.playersInputTarget.value       = val   // hidden field soumis avec le formulaire
    this.recapPlayersTarget.textContent = val
  }

  // ── Niveau : génère les boutons de niveau pour le sport sélectionné ──
  // Même style et même pattern que _renderFormatButtons
  _renderLevelButtons(levels, savedLevel) {
    const container = this.levelButtonsTarget
    container.innerHTML = ""

    levels.forEach((lvl) => {
      const btn = document.createElement("button")
      btn.type = "button"
      const isActive = lvl.label === savedLevel
      btn.className = "match-level-btn" + (isActive ? " active" : "")
      btn.textContent = lvl.label
      btn.dataset.level = lvl.label
      btn.style.setProperty("padding", "0.5rem 1.1rem")
      btn.style.setProperty("border-radius", "0.5rem")
      btn.style.setProperty("font-size", "0.9rem")
      btn.style.setProperty("cursor", "pointer")
      btn.style.setProperty("border",      isActive ? "2px solid #1EDD88"         : "2px solid rgba(255,255,255,0.4)", "important")
      btn.style.setProperty("background",  isActive ? "rgba(30,221,136,0.12)"     : "rgba(255,255,255,0.08)", "important")
      btn.style.setProperty("color",       isActive ? "#1EDD88"                   : "rgba(255,255,255,0.9)", "important")
      btn.addEventListener("mouseover", () => {
        if (!btn.classList.contains("active")) {
          btn.style.setProperty("border",     "2px solid #1EDD88", "important")
          btn.style.setProperty("background", "rgba(30,221,136,0.08)", "important")
          btn.style.setProperty("color",      "#1EDD88", "important")
        }
      })
      btn.addEventListener("mouseout", () => {
        if (!btn.classList.contains("active")) {
          btn.style.setProperty("border",     "2px solid rgba(255,255,255,0.4)", "important")
          btn.style.setProperty("background", "rgba(255,255,255,0.08)", "important")
          btn.style.setProperty("color",      "rgba(255,255,255,0.9)", "important")
        }
      })
      btn.addEventListener("click", () => this._applyLevel(lvl.label, btn))
      container.appendChild(btn)
    })
  }

  // Applique un niveau : met à jour l'input caché, le récap et les styles des boutons
  _applyLevel(label, clickedBtn) {
    this.levelInputTarget.value        = label
    this.recapLevelTarget.textContent  = label

    // Remet tous les boutons niveau à l'état inactif
    this.levelButtonsTarget.querySelectorAll(".match-level-btn").forEach(b => {
      const isActive = b === clickedBtn
      b.classList.toggle("active", isActive)
      b.style.setProperty("border",     isActive ? "2px solid #1EDD88"     : "2px solid rgba(255,255,255,0.4)", "important")
      b.style.setProperty("background", isActive ? "rgba(30,221,136,0.12)" : "rgba(255,255,255,0.08)", "important")
      b.style.setProperty("color",      isActive ? "#1EDD88"               : "rgba(255,255,255,0.9)", "important")
    })
  }

  // ── Niveau : sélectionner un bouton (appelé via data-action dans le HTML) ──
  selectLevel(event) {
    this._applyLevel(event.currentTarget.dataset.level, event.currentTarget)
  }

  // ── Niveau : synchroniser le récap au chargement ────────────
  updateLevel() {
    const val = this.levelInputTarget.value
    this.recapLevelTarget.textContent = val
  }

  // ── Prix par joueur ──────────────────────────────────────
  // Affiche "X €" si prix > 0, sinon rien (pas de "Gratuit")
  updatePrice() {
    const val = parseInt(this.priceInputTarget.value) || 0
    this.recapPriceTarget.textContent = val > 0 ? `${val} €` : ""
  }

  // ── Validation : Manuel / Automatique ───────────────────
  // Le toggle est dans la Section 4 du formulaire
  // Ordre des labels : "Manuel" à gauche (index 0), "Automatique" à droite (index 1)
  // checked = Automatique, unchecked = Manuel
  updateValidation() {
    // checked = Automatique → isManual est l'inverse
    const isManual = !this.validationToggleTarget.checked

    // Met à jour les labels "Manuel" / "Automatique" autour du toggle
    const labels = this.element.querySelectorAll(".toggle-label")
    if (labels.length === 2) {
      // Premier label = "Manuel" → actif si mode manuel
      labels[0].classList.toggle("active-label", isManual)
      // Deuxième label = "Automatique" → actif si mode automatique
      labels[1].classList.toggle("active-label", !isManual)
    }

    // Met à jour la ligne "Validation" dans le récapitulatif
    this.recapValidationTarget.textContent = isManual ? "Manuel" : "Automatique"
  }
}
