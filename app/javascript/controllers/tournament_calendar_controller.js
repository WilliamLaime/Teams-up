// tournament_calendar_controller.js
// Onglet « Calendrier » d'un tournoi : grille du mois, bascule en vue semaine,
// et mode agenda en mobile.
//
// Répartition des rôles — c'est le point à comprendre avant de toucher au reste :
// ce contrôleur ne fabrique AUCUN contenu de rencontre. Rails a déjà rendu toutes
// les vignettes dans des <template data-date="…"> (_calendar_source.html.erb) ;
// ici on ne construit que la charpente (cases de jour vides) et on y clone le
// template du jour. Le JS ne connaît donc que des dates — jamais un score, une
// poule, un nom de joueur ni un droit Pundit. C'est ce qui évite de réécrire en
// JavaScript la moitié de TournamentsHelper, et d'avoir à échapper à la main des
// noms saisis par des utilisateurs.
//
// La navigation est cliente parce qu'elle DOIT l'être : les onglets du tournoi
// basculent sans toucher à l'URL (tournament_tabs_controller), donc tout
// rechargement de page ramènerait le visiteur sur l'onglet Matchs.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "title", "source", "empty", "viewButton"]
  static values  = { view: String }

  static MONTHS    = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
                      "août", "septembre", "octobre", "novembre", "décembre"]
  static DAYS_ABBR = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]
  static DAYS_FULL = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

  connect() {
    // Ancre = premier jour de la période affichée. On ouvre sur le mois courant.
    this.anchor = this.#startOfMonth(new Date())

    // En mobile, la grille 7 colonnes n'est pas lisible : on rend la même période
    // sous forme d'agenda (liste groupée par jour). On écoute le redimensionnement
    // pour rebasculer, sinon une rotation de téléphone laisse une grille illisible.
    this.mobileQuery = window.matchMedia("(max-width: 767px)")
    this.onViewportChange = () => this.#render()
    this.mobileQuery.addEventListener("change", this.onViewportChange)

    this.#render()
  }

  disconnect() {
    this.mobileQuery?.removeEventListener("change", this.onViewportChange)
  }

  // La source est remplacée par Turbo Stream après une saisie de score : on
  // redessine la période courante pour que les scores affichés restent justes.
  // (Appelé aussi au tout premier rendu, avant connect() — d'où la garde.)
  sourceTargetConnected() {
    if (this.anchor) this.#render()
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  previous() { this.#shift(-1) }
  next()     { this.#shift(1) }

  today() {
    this.anchor = this.#weekView ? this.#startOfWeek(new Date()) : this.#startOfMonth(new Date())
    this.#render()
  }

  showMonth() {
    if (!this.#weekView) return

    this.viewValue = "month"
    this.anchor = this.#startOfMonth(this.anchor)
    this.#syncViewButtons()
    this.#render()
  }

  showWeek(event) {
    // Deux appelants, deux intentions :
    //   • le bouton « Semaine » de la barre → la semaine EN COURS, comme la vue
    //     mois s'ouvre sur le mois en cours. Repartir de la période affichée
    //     enverrait sur une semaine arbitraire du mois qu'on venait de feuilleter ;
    //   • le bouton « +N autres » d'une case → la semaine du jour cliqué, puisque
    //     c'est précisément ce jour-là qu'on veut voir en entier.
    const from = event?.params?.date ? this.#parseISO(event.params.date) : new Date()

    this.viewValue = "week"
    this.anchor = this.#startOfWeek(from)
    this.#syncViewButtons()
    this.#render()
  }

  // ── Rendu ───────────────────────────────────────────────────────────────────

  #render() {
    // La grille est TOUJOURS affichée, même sans une seule rencontre datée : un
    // mois vide reste une information (« rien n'est encore calé »), là où un
    // message à la place du calendrier oblige à deviner à quoi ressemblera l'écran.
    // Seule une note discrète sous la grille signale l'absence totale de créneau.
    this.emptyTarget.hidden = this.#allTemplates().length > 0

    this.gridTarget.replaceChildren()
    this.element.classList.toggle("tcal--month", !this.#weekView)
    this.element.classList.toggle("tcal--week", this.#weekView)

    if (this.mobileQuery.matches) {
      this.#renderAgenda()
    } else if (this.#weekView) {
      this.#renderWeek()
    } else {
      this.#renderMonth()
    }

    this.titleTarget.textContent = this.#periodLabel()
  }

  // Grille du mois : une vraie <table>. La sémantique jour/colonne est offerte
  // aux lecteurs d'écran, ce qu'une grille de <div> devrait reconstituer en ARIA.
  #renderMonth() {
    const table = document.createElement("table")
    table.className = "tcal-month"

    const caption = document.createElement("caption")
    caption.className = "visually-hidden"
    // Le mois redevient minuscule ici : il est au milieu d'une phrase.
    caption.textContent = `Rencontres de ${this.constructor.MONTHS[this.anchor.getMonth()]} ${this.anchor.getFullYear()}`
    table.append(caption)

    const thead = document.createElement("thead")
    const headRow = document.createElement("tr")
    this.constructor.DAYS_ABBR.forEach((label, i) => {
      const th = document.createElement("th")
      th.scope = "col"
      const abbr = document.createElement("abbr")
      abbr.title = this.constructor.DAYS_FULL[i]
      abbr.textContent = label
      th.append(abbr)
      headRow.append(th)
    })
    thead.append(headRow)
    table.append(thead)

    const tbody = document.createElement("tbody")
    const first = this.#startOfMonth(this.anchor)
    const daysInMonth = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    // Semaine commençant le lundi : getDay() rend 0 pour dimanche (cf. date_picker).
    const offset = (first.getDay() === 0) ? 6 : first.getDay() - 1
    const cells = Math.ceil((offset + daysInMonth) / 7) * 7

    let row = document.createElement("tr")
    for (let i = 0; i < cells; i++) {
      if (i > 0 && i % 7 === 0) { tbody.append(row); row = document.createElement("tr") }

      const dayNumber = i - offset + 1
      const td = document.createElement("td")

      if (dayNumber < 1 || dayNumber > daysInMonth) {
        // Case hors du mois : décorative, retirée de l'arbre d'accessibilité.
        td.className = "tcal-month__day tcal-month__day--out"
        td.setAttribute("aria-hidden", "true")
        row.append(td)
        continue
      }

      const date = new Date(first.getFullYear(), first.getMonth(), dayNumber)
      td.className = "tcal-month__day"
      if (this.#isToday(date)) td.classList.add("tcal-month__day--today")

      const num = document.createElement("time")
      num.className = "tcal-month__num"
      num.dateTime = this.#toISO(date)
      num.textContent = dayNumber
      td.append(num)

      // Au-delà de 2 vignettes, une journée chargée ferait exploser la hauteur de
      // toute la rangée : on renvoie vers la vue semaine, qui a la place.
      const events = this.#eventsFor(date)
      events.slice(0, 2).forEach((node) => td.append(node))
      if (events.length > 2) td.append(this.#moreButton(date, events.length - 2))

      row.append(td)
    }
    tbody.append(row)
    table.append(tbody)

    this.gridTarget.append(table)
  }

  // Vue semaine : sept colonnes-jours, chacune une liste chronologique. Pas d'axe
  // horaire au pixel — l'heure est déjà portée par la vignette, et un
  // positionnement absolu rendrait la vue inutilisable au clavier.
  #renderWeek() {
    const week = document.createElement("div")
    week.className = "tcal-week"

    for (let i = 0; i < 7; i++) {
      const date = this.#addDays(this.anchor, i)
      const events = this.#eventsFor(date)

      const day = document.createElement("section")
      day.className = "tcal-week__day"
      if (this.#isToday(date)) day.classList.add("tcal-week__day--today")
      if (events.length === 0) day.classList.add("tcal-week__day--empty")

      day.append(this.#dayHeading(date, "h4", "tcal-week__head"))

      const list = document.createElement("ol")
      list.className = "tcal-week__list"
      events.forEach((node) => {
        const li = document.createElement("li")
        li.append(node)
        list.append(li)
      })
      day.append(list)

      week.append(day)
    }

    this.gridTarget.append(week)
  }

  // Mobile : ni grille de mois ni sept colonnes ne tiennent sur 375 px. Même
  // période, même vignettes — une simple liste groupée par jour, sans les jours
  // vides qui n'apportent rien quand on fait défiler.
  #renderAgenda() {
    const agenda = document.createElement("div")
    agenda.className = "tcal-agenda"

    const days = this.#weekView ? 7 : this.#daysInMonth(this.anchor)
    const start = this.#weekView ? this.anchor : this.#startOfMonth(this.anchor)

    for (let i = 0; i < days; i++) {
      const date = this.#addDays(start, i)
      const events = this.#eventsFor(date)
      if (events.length === 0) continue

      const group = document.createElement("section")
      group.className = "tcal-agenda__day"
      if (this.#isToday(date)) group.classList.add("tcal-agenda__day--today")
      group.append(this.#dayHeading(date, "h4", "tcal-agenda__head", { long: true }))

      const list = document.createElement("ol")
      list.className = "tcal-agenda__list"
      events.forEach((node) => {
        const li = document.createElement("li")
        li.append(node)
        list.append(li)
      })
      group.append(list)

      agenda.append(group)
    }

    if (!agenda.hasChildNodes()) {
      const none = document.createElement("p")
      none.className = "tcal__none"
      const month = `${this.constructor.MONTHS[this.anchor.getMonth()]} ${this.anchor.getFullYear()}`
      none.textContent = `Aucune rencontre ${this.#weekView ? "cette semaine" : `en ${month}`}.`
      agenda.append(none)
    }

    this.gridTarget.append(agenda)
  }

  // ── Outils ──────────────────────────────────────────────────────────────────

  // Les vignettes du jour, clonées depuis le <template> correspondant. On clone
  // et on ne déplace pas : le template reste la source intacte, réutilisable au
  // rendu suivant (changement de vue, retour sur le mois).
  #eventsFor(date) {
    const template = this.#allTemplates().find((t) => t.dataset.date === this.#toISO(date))
    if (!template) return []

    return Array.from(template.content.cloneNode(true).children)
  }

  #allTemplates() {
    return this.sourceTargets.flatMap((source) => Array.from(source.querySelectorAll("template[data-date]")))
  }

  #moreButton(date, count) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "tcal-month__more"
    button.textContent = `+${count} autre${count > 1 ? "s" : ""}`
    button.dataset.action = "tournament-calendar#showWeek"
    button.dataset.tournamentCalendarDateParam = this.#toISO(date)
    return button
  }

  #dayHeading(date, tag, className, { long = false } = {}) {
    const heading = document.createElement(tag)
    heading.className = className

    const name = document.createElement("span")
    name.textContent = long
      ? this.constructor.DAYS_FULL[this.#weekdayIndex(date)]
      : this.constructor.DAYS_ABBR[this.#weekdayIndex(date)]

    const number = document.createElement("time")
    number.dateTime = this.#toISO(date)
    number.textContent = long
      ? `${date.getDate()} ${this.constructor.MONTHS[date.getMonth()]}`
      : date.getDate()

    heading.append(name, " ", number)
    return heading
  }

  #shift(direction) {
    this.anchor = this.#weekView
      ? this.#addDays(this.anchor, 7 * direction)
      : new Date(this.anchor.getFullYear(), this.anchor.getMonth() + direction, 1)

    this.#render()
  }

  #syncViewButtons() {
    this.viewButtonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.view === this.viewValue))
    })
  }

  #periodLabel() {
    if (!this.#weekView) {
      return this.#capitalize(`${this.constructor.MONTHS[this.anchor.getMonth()]} ${this.anchor.getFullYear()}`)
    }

    const end = this.#addDays(this.anchor, 6)
    const startMonth = this.constructor.MONTHS[this.anchor.getMonth()]
    const endMonth   = this.constructor.MONTHS[end.getMonth()]
    // « 28 septembre – 4 octobre 2026 » : on ne répète le mois que s'il change.
    const left = startMonth === endMonth ? `${this.anchor.getDate()}` : `${this.anchor.getDate()} ${startMonth}`

    return `${left} – ${end.getDate()} ${endMonth} ${end.getFullYear()}`
  }

  // Majuscule de tête uniquement : en français, « août » ne la prend qu'en début
  // de libellé — « 3 – 9 Août 2026 » serait fauté.
  #capitalize(text) { return text.charAt(0).toUpperCase() + text.slice(1) }

  get #weekView() { return this.viewValue === "week" }

  #weekdayIndex(date) { return (date.getDay() === 0) ? 6 : date.getDay() - 1 }

  #startOfMonth(date) { return new Date(date.getFullYear(), date.getMonth(), 1) }

  #startOfWeek(date) { return this.#addDays(date, -this.#weekdayIndex(date)) }

  #daysInMonth(date) { return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate() }

  #addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
  }

  #isToday(date) { return this.#toISO(date) === this.#toISO(new Date()) }

  // Date locale au format ISO — surtout PAS toISOString(), qui convertit en UTC et
  // décale d'un jour toutes les dates du soir en heure d'été française.
  #toISO(date) {
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day   = String(date.getDate()).padStart(2, "0")
    return `${date.getFullYear()}-${month}-${day}`
  }

  #parseISO(iso) {
    const [year, month, day] = iso.split("-").map(Number)
    return new Date(year, month - 1, day)
  }
}
