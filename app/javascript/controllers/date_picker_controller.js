// date_picker_controller.js
// Calendrier custom dans le même style que time-picker et sport-picker.
// Remplace le <input type="date"> natif par un trigger + dropdown calendrier.
//
// Pattern identique aux autres dropdowns :
//   - Un bouton trigger qui affiche la date sélectionnée
//   - Un dropdown avec un calendrier mensuel navigable
//   - Un input caché qui stocke la valeur réelle (soumise avec le formulaire)
//   - Émet l'événement global "dropdown:open" pour fermer les autres dropdowns

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "triggerText", "dropdown", "input"]

  // Noms des mois et jours en français
  static MONTHS = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
                   "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
  static DAYS   = ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]

  connect() {
    // Date sélectionnée : depuis la valeur de l'input caché (édition d'un match)
    // ou null si nouveau match
    const val = this.inputTarget.value
    this.selectedDate = val ? new Date(val + "T00:00:00") : null

    // Mois affiché dans le calendrier : celui de la date sélectionnée ou le mois courant
    const ref = this.selectedDate || new Date()
    this.viewYear  = ref.getFullYear()
    this.viewMonth = ref.getMonth()  // 0-11

    // Met à jour le texte du trigger si une date est déjà sélectionnée
    if (this.selectedDate) this._updateTrigger(this.selectedDate)

    // Initialise l'icône Lucide dans le trigger (si lucide est disponible sur la page)
    if (typeof lucide !== "undefined") lucide.createIcons({ nodes: [this.triggerTarget] })

    // Ferme ce dropdown si un autre s'ouvre
    this.handleOtherOpen = (e) => {
      if (e.detail.source !== this.element) {
        this.dropdownTarget.style.display = "none"
      }
    }
    document.addEventListener("dropdown:open", this.handleOtherOpen)

    // Ferme si clic en dehors
    this.handleClickOutside = (e) => {
      if (!this.element.contains(e.target)) {
        this.dropdownTarget.style.display = "none"
      }
    }
    document.addEventListener("click", this.handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("dropdown:open", this.handleOtherOpen)
    document.removeEventListener("click", this.handleClickOutside)
  }

  // ── Ouvre / ferme le calendrier ──────────────────────────────────────────────
  toggle(event) {
    event.stopPropagation()
    const d = this.dropdownTarget
    const isOpening = d.style.display === "none"
    d.style.display = isOpening ? "block" : "none"

    if (isOpening) {
      // Prévient les autres dropdowns
      document.dispatchEvent(new CustomEvent("dropdown:open", { detail: { source: this.element } }))
      // Dessine le calendrier du mois en cours
      this._renderCalendar()
    }
  }

  // ── Mois précédent ───────────────────────────────────────────────────────────
  prevMonth(event) {
    event.stopPropagation()
    if (this.viewMonth === 0) {
      this.viewMonth = 11
      this.viewYear--
    } else {
      this.viewMonth--
    }
    this._renderCalendar()
  }

  // ── Mois suivant ─────────────────────────────────────────────────────────────
  nextMonth(event) {
    event.stopPropagation()
    if (this.viewMonth === 11) {
      this.viewMonth = 0
      this.viewYear++
    } else {
      this.viewMonth++
    }
    this._renderCalendar()
  }

  // ── Sélection d'un jour ──────────────────────────────────────────────────────
  selectDay(event) {
    event.stopPropagation()
    const btn = event.currentTarget
    if (btn.disabled) return

    // Construit la date sélectionnée
    const day   = parseInt(btn.dataset.day)
    const month = parseInt(btn.dataset.month)
    const year  = parseInt(btn.dataset.year)
    this.selectedDate = new Date(year, month, day)

    // Met à jour l'input caché (format YYYY-MM-DD pour Rails)
    const iso = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`
    this.inputTarget.value = iso

    // Notifie match-form#updateDate (même mécanisme que time-picker)
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    // Met à jour le trigger et ferme le calendrier
    this._updateTrigger(this.selectedDate)
    this.dropdownTarget.style.display = "none"
  }

  // ── Rendu du calendrier ──────────────────────────────────────────────────────
  _renderCalendar() {
    const today    = new Date()
    const todayY   = today.getFullYear()
    const todayM   = today.getMonth()
    const todayD   = today.getDate()
    const minDate  = new Date(todayY, todayM, todayD) // pas de dates passées

    const selY = this.selectedDate?.getFullYear()
    const selM = this.selectedDate?.getMonth()
    const selD = this.selectedDate?.getDate()

    // Premier jour du mois (0=Dimanche…6=Samedi), converti en lundi=0
    const firstDay = new Date(this.viewYear, this.viewMonth, 1).getDay()
    const startOffset = (firstDay === 0) ? 6 : firstDay - 1  // décale pour commencer le lundi

    // Nombre de jours dans le mois affiché
    const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate()

    // ── En-tête : mois/année + navigation ──
    let html = `
      <div class="dp-header">
        <button type="button" class="dp-nav-btn" data-action="click->date-picker#prevMonth">‹</button>
        <span class="dp-month-label">
          ${this.constructor.MONTHS[this.viewMonth]} ${this.viewYear}
        </span>
        <button type="button" class="dp-nav-btn" data-action="click->date-picker#nextMonth">›</button>
      </div>
    `

    // ── Ligne des noms de jours ──
    html += `<div class="dp-grid">`
    this.constructor.DAYS.forEach(d => {
      html += `<div class="dp-day-name">${d}</div>`
    })

    // ── Cases vides avant le 1er du mois ──
    for (let i = 0; i < startOffset; i++) {
      html += `<div class="dp-day dp-day--empty"></div>`
    }

    // ── Jours du mois ──
    for (let day = 1; day <= daysInMonth; day++) {
      const thisDate  = new Date(this.viewYear, this.viewMonth, day)
      const isPast    = thisDate < minDate
      const isToday   = day === todayD && this.viewMonth === todayM && this.viewYear === todayY
      const isSelected = day === selD && this.viewMonth === selM && this.viewYear === selY

      let cls = "dp-day"
      if (isPast)     cls += " dp-day--past"
      if (isToday)    cls += " dp-day--today"
      if (isSelected) cls += " dp-day--selected"

      html += `
        <button type="button"
                class="${cls}"
                data-action="click->date-picker#selectDay"
                data-day="${day}"
                data-month="${this.viewMonth}"
                data-year="${this.viewYear}"
                ${isPast ? "disabled" : ""}>
          ${day}
        </button>
      `
    }

    html += `</div>` // fin dp-grid

    this.dropdownTarget.innerHTML = html
  }

  // ── Met à jour le texte du bouton trigger ────────────────────────────────────
  // On cible le <span> triggerText et non le bouton entier,
  // pour ne pas écraser l'icône calendrier qui est à côté
  _updateTrigger(date) {
    const days   = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
    const months = ["jan.", "fév.", "mars", "avr.", "mai", "juin",
                    "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    const label = `${days[date.getDay()]} ${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}`
    this.triggerTextTarget.textContent = label
    this.triggerTextTarget.style.color = "inherit"  // retire la couleur grise du placeholder
  }
}
