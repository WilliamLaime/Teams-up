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
    "levelInput",        // Input caché : niveau sélectionné (mis à jour par les boutons)
    "validationToggle",  // Checkbox du toggle Manuel/Automatique

    // ── Éléments du récapitulatif (destinations) ──────────
    "recapTitle",        // Zone affichant le titre dans la sidebar
    "recapDescription",  // Zone affichant la description tronquée
    "recapPlace",        // Zone affichant le lieu
    "recapDate",         // Zone affichant la date formatée
    "recapTime",         // Zone affichant l'heure (ex: 21h15)
    "recapPlayers",      // Zone affichant le nombre de joueurs
    "recapLevel",        // Zone affichant le niveau
    "recapValidation"    // Zone affichant "Automatique" ou "Manuelle"
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
  }

  // ══════════════════════════════════════════════════════════
  // Méthodes de mise à jour du récapitulatif
  // Chacune lit la valeur d'un champ et l'écrit dans la sidebar
  // ══════════════════════════════════════════════════════════

  // ── Titre ─────────────────────────────────────────────────
  updateTitle() {
    const val = this.titleInputTarget.value.trim()
    // Si le champ est vide, affiche un tiret, sinon la vraie valeur
    this.recapTitleTarget.textContent = val || "—"
  }

  // ── Description (tronquée à 80 caractères) ────────────────
  updateDescription() {
    const val = this.descriptionInputTarget.value.trim()
    if (val.length > 80) {
      // Coupe à 80 caractères et ajoute "..."
      this.recapDescriptionTarget.textContent = val.substring(0, 80) + "..."
    } else {
      this.recapDescriptionTarget.textContent = val || "—"
    }
  }

  // ── Lieu ──────────────────────────────────────────────────
  updatePlace() {
    const val = this.placeInputTarget.value.trim()
    this.recapPlaceTarget.textContent = val || "—"
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
    }
  }

  // ── Nombre de joueurs : incrémenter ("+") ────────────────
  increment() {
    const input = this.playersInputTarget
    const current = parseInt(input.value) || 1
    const newVal = current + 1
    input.value = newVal
    this.playersCountTarget.textContent = newVal
    this.recapPlayersTarget.textContent  = newVal
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

    // 4. Met à jour le récap
    this.recapLevelTarget.textContent = value || "—"
  }

  // ── Niveau : synchroniser le récap ────────────────────────
  updateLevel() {
    const val = this.levelInputTarget.value
    this.recapLevelTarget.textContent = val || "—"
  }

  // ── Validation : Manuel / Automatique ────────────────────
  updateValidation() {
    const isManual = this.validationToggleTarget.checked
    this.recapValidationTarget.textContent = isManual ? "Manuelle" : "Automatique"

    // Met aussi à jour les labels "Manuel" / "Automatique" à côté du toggle
    const labels = this.element.querySelectorAll(".toggle-label")
    if (labels.length === 2) {
      // Premier label = "Manuel" → actif si coché
      labels[0].classList.toggle("active-label", isManual)
      // Deuxième label = "Automatique" → actif si décoché
      labels[1].classList.toggle("active-label", !isManual)
    }
  }
}
