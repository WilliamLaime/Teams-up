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
    "playersInput",      // Input caché : nombre de joueurs (mis à jour par le compteur)
    "playersCount",      // Span visible : chiffre du compteur affiché à l'écran
    "minusBtn",          // Bouton "−" du compteur (pour changer sa couleur)
    "plusBtn",           // Bouton "+" du compteur (pour changer sa couleur)
    "levelInput",        // Input caché : niveau sélectionné (mis à jour par les boutons)
    "validationToggle",  // Checkbox du toggle Manuel/Automatique
    "priceInput",        // Champ numérique : prix par joueur

    // ── Éléments du récapitulatif (destinations) ──────────
    "recapTitle",        // Zone affichant le titre dans la sidebar
    "recapDescription",  // Paragraphe affichant la description (masqué si vide)
    "recapPlace",        // Valeur du lieu dans la ligne
    "recapDate",         // Zone affichant la date formatée
    "recapTime",         // Zone affichant l'heure (ex: 21h15)
    "recapPlayers",      // Zone affichant le nombre de joueurs
    "recapLevel",        // Valeur du niveau dans la ligne
    "recapValidation",   // Zone affichant le mode de validation (Manuel / Automatique)
    "recapPrice"         // Zone affichant le prix par joueur (en bas du récap, en blanc)
  ]

  // ── connect() : appelé automatiquement au chargement de la page ──
  // On initialise le récap avec les valeurs déjà présentes dans les champs
  // (utile lors de la modification d'un match existant)
  connect() {
    this.updateTitle()
    this.updateDescription()
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
    // Maximum : 9 joueurs
    if (current < 9) {
      const newVal = current + 1
      input.value = newVal
      this.playersCountTarget.textContent = newVal
      this.recapPlayersTarget.textContent  = newVal
      this.updateCounterButtons(newVal)              // met à jour les couleurs des boutons
    }
  }

  // ── Met à jour la couleur des boutons − et + selon la valeur ──
  // Règle :
  //   val = 1 → "-" gris (limite atteinte),  "+" vert
  //   val = 9 → "-" vert,                    "+" gris (limite atteinte)
  //   entre   → les deux verts
  updateCounterButtons(val) {
    const minus = this.minusBtnTarget
    const plus  = this.plusBtnTarget

    // On retire les deux classes d'état avant de les réappliquer
    minus.classList.remove("is-active", "is-disabled")
    plus.classList.remove("is-active", "is-disabled")

    if (val <= 1) {
      minus.classList.add("is-disabled")  // Minimum atteint → "-" gris
      plus.classList.add("is-active")
    } else if (val >= 9) {
      minus.classList.add("is-active")
      plus.classList.add("is-disabled")   // Maximum atteint → "+" gris
    } else {
      minus.classList.add("is-active")    // Entre 1 et 9 → les deux verts
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
    this.element.querySelectorAll(".match-level-btn").forEach(b => {
      b.classList.remove("active")
    })
    // 3. Ajoute "active" seulement sur le bouton cliqué
    btn.classList.add("active")

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
