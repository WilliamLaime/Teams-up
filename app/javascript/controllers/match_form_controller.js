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
    "playersInput",      // Input caché : nombre de joueurs (mis à jour par le compteur)
    "playersCount",      // Span visible : chiffre du compteur affiché à l'écran
    "minusBtn",          // Bouton "−" du compteur (pour changer sa couleur)
    "plusBtn",           // Bouton "+" du compteur (pour changer sa couleur)
    "levelInput",        // Input caché : niveau sélectionné (mis à jour par les boutons)
    "validationToggle",  // Checkbox du toggle Manuel/Automatique
    "priceInput",        // Champ numérique : prix par joueur

    // ── Format ────────────────────────────────────────────
    "formatWrapper",     // Div englobant les boutons de format (affiché/caché selon sport)
    "formatInput",       // Input caché : valeur du format soumise avec le formulaire
    "formatButtons",     // Div recevant les boutons de format générés dynamiquement
    "recapFormatRow",    // Ligne "Format" dans le récap (masquée si mono-format)
    "recapFormat",       // Valeur du format dans la ligne récap

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
    "formCol"            // Colonne gauche (col-lg-7) — sert à mesurer son bas pour l'alignement
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

      // Met à jour le max global pour ce sport
      this.maxPlayers = maxMap[sportId] || 9

      // Met à jour le récap sport
      this.recapSportTarget.textContent = nameMap[sportId] || "—"

      // N'affiche le sélecteur et la ligne récap que s'il y a plusieurs formats possibles
      if (formats.length > 1) {
        this._renderFormatButtons(formats)
        this.formatWrapperTarget.style.display = ""
        this.recapFormatRowTarget.style.display = ""
      } else {
        this.formatWrapperTarget.style.display = "none"
        this.recapFormatRowTarget.style.display = "none"
      }

      // Sélectionne automatiquement le premier format (applique aussi le compteur)
      this._applyFormat(formats[0])
    } else {
      // Aucun sport sélectionné
      this.maxPlayers = 9
      this.recapSportTarget.textContent = "—"
      this.formatWrapperTarget.style.display = "none"
    }
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
  _applyFormat(fmt, clickedBtn = null) {
    // Met à jour l'input caché format (soumis avec le formulaire)
    this.formatInputTarget.value = fmt.label

    // Met à jour la ligne récap format
    this.recapFormatTarget.textContent = fmt.label

    // Le max devient le nombre exact de joueurs du format (ex: 3v3 → max 5)
    this.maxPlayers = fmt.players

    // Démarre toujours à 1 joueur manquant (l'utilisateur incrémente jusqu'au max)
    const count = 1
    this.playersInputTarget.value       = count
    this.playersCountTarget.textContent = count
    this.recapPlayersTarget.textContent = count
    this.updateCounterButtons(count)

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
  // time_select génère deux <select> avec des IDs prévisibles :
  //   match_time_4i → heures
  //   match_time_5i → minutes
  // On les trouve par leurs IDs depuis l'élément racine du contrôleur
  updateTime() {
    const hourEl   = this.element.querySelector('[id$="_time_4i"]')
    const minuteEl = this.element.querySelector('[id$="_time_5i"]')

    if (hourEl && minuteEl && hourEl.value && minuteEl.value) {
      // padStart(2, "0") : force "9" → "09" pour avoir "09h00"
      const h = hourEl.value.padStart(2, "0")
      const m = minuteEl.value.padStart(2, "0")
      this.recapTimeTarget.textContent = `${h}h${m}`
    } else {
      this.recapTimeTarget.textContent = "—"
    }
  }

  // ── Nombre de joueurs : décrémenter ("-") ────────────────
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

  // ── Nombre de joueurs : incrémenter ("+") ────────────────
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

  // ── Met à jour la couleur des boutons − et + selon la valeur ──
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

  // ── Synchroniser le récap avec la valeur actuelle ────────
  updatePlayers() {
    const val = this.playersInputTarget.value || "—"
    this.playersCountTarget.textContent = val
    this.recapPlayersTarget.textContent  = val
  }

  // ── Niveau : sélectionner un bouton ──────────────────────
  // Appelé quand l'utilisateur clique sur un des boutons Débutant/Intermédiaire/etc.
  selectLevel(event) {
    const btn   = event.currentTarget
    const value = btn.dataset.level  // la valeur est dans data-level="Avancé"

    // 1. Met à jour le champ caché qui sera envoyé avec le formulaire
    this.levelInputTarget.value = value

    // 2. Retire la classe "active" de tous les boutons de niveau
    //    + styles inline : garantit l'apparence même si le CSS est surchargé
    this.element.querySelectorAll(".match-level-btn").forEach(b => {
      b.classList.remove("active")
      b.style.setProperty("border", "2px solid rgba(255,255,255,0.4)", "important")
      b.style.setProperty("background", "rgba(255,255,255,0.08)", "important")
      b.style.setProperty("color", "rgba(255,255,255,0.9)", "important")
    })
    // 3. Ajoute "active" + styles verts seulement sur le bouton cliqué
    btn.classList.add("active")
    btn.style.setProperty("border", "2px solid #1EDD88", "important")
    btn.style.setProperty("background", "rgba(30,221,136,0.12)", "important")
    btn.style.setProperty("color", "#1EDD88", "important")

    // 4. Met à jour le récap (la ligne reste toujours visible)
    this.recapLevelTarget.textContent = value
  }

  // ── Niveau : synchroniser le récap ────────────────────────
  updateLevel() {
    const val = this.levelInputTarget.value
    // Affiche la valeur ou rien si vide (la ligne reste toujours visible)
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
