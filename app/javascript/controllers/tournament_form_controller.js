// ══════════════════════════════════════════════════════════════
// Contrôleur Stimulus : tournament-form
// ══════════════════════════════════════════════════════════════
// Version allégée de match-form, dédiée à la création d'un tournoi :
//   • récapitulatif (sidebar droite) mis à jour en temps réel
//   • boutons de format générés dynamiquement selon le sport
//   • nombre de joueurs : presets 8/16/32 OU mode "Libre" (saisie d'un
//     nombre souhaité → 1 config recommandée + propositions alternatives)
//   • aperçu en lecture seule de la structure figée (format + nb joueurs)
//   • toggle d'auto-inscription du créateur
//
// La logique de structure / propositions est PROVISOIRE : elle ne sert
// ici qu'à guider l'organisateur. La génération réelle des tableaux
// arrivera au Lot 3 (cf. docs/TOURNOI.md).
// ══════════════════════════════════════════════════════════════

import { Controller } from "@hotwired/stimulus"

// Libellés lisibles des formats (miroir de Tournament::FORMAT_LABELS).
const FORMAT_LABELS = {
  ronde_suisse: "Ronde Suisse",
  poules:       "Poules",
  championnat:  "Championnat"
}

export default class extends Controller {
  static targets = [
    // Sources
    "sportInput", "formatInput", "formatWrapper", "formatButtons",
    "nameInput", "descriptionInput", "placeInput", "dateInput",
    "maxPlayersInput", "countBtn", "libreBtn", "libreSection", "libreInput",
    "proposals", "structurePreview", "structureText", "selfRegister", "coOrgInput",
    // Récapitulatif
    "recapName", "recapDescription", "recapSport", "recapFormat", "recapFormatRow",
    "recapDate", "recapTime", "recapPlace", "recapPlayers",
    "recapStructure", "recapStructureRow", "recapSelfRegister", "recapDeadline", "recapCoOrg"
  ]

  connect() {
    // Structures figées passées en data-attribute (JSON Tournament::STRUCTURE_PRESETS).
    this.structures = JSON.parse(this.sportInputTarget.dataset.structures || "{}")
    // Vrai quand l'utilisateur est en saisie "Libre" (nombre arbitraire).
    this.libreMode = false

    // Initialise le récap avec les valeurs déjà présentes (sport par défaut, etc.).
    this.updateName()
    this.updateDescription()
    this.updateSport()   // rend les boutons de format + applique le 1er format
    this.updateDate()
    this.updateTime()
    this.updatePlace()
  }

  // ── Sport → formats compatibles ──────────────────────────────
  updateSport() {
    const select     = this.sportInputTarget
    const sportId     = select.value
    const formatsMap  = JSON.parse(select.dataset.formats    || "{}")
    const nameMap     = JSON.parse(select.dataset.sportNames || "{}")

    this.recapSportTarget.textContent = nameMap[sportId] || "—"

    const formats = formatsMap[sportId]
    if (sportId && formats && formats.length) {
      this._renderFormatButtons(formats)
      this.formatWrapperTarget.style.display  = ""
      this.recapFormatRowTarget.style.display = ""

      // Conserve le format déjà choisi s'il reste compatible, sinon prend le 1er.
      const saved   = this.formatInputTarget.value
      const chosen  = formats.includes(saved) ? saved : formats[0]
      const btns    = this.formatButtonsTarget.querySelectorAll(".match-level-btn")
      const btn     = Array.from(btns).find(b => b.dataset.format === chosen) || btns[0]
      this._applyFormat(chosen, btn)
    } else {
      this.formatWrapperTarget.style.display  = "none"
      this.recapFormatRowTarget.style.display = "none"
    }
  }

  _renderFormatButtons(formats) {
    const container = this.formatButtonsTarget
    container.innerHTML = ""

    formats.forEach((value, index) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "match-level-btn" + (index === 0 ? " active" : "")
      btn.textContent = FORMAT_LABELS[value] || value
      btn.dataset.format = value
      this._styleFormatBtn(btn, index === 0)
      btn.addEventListener("mouseover", () => { if (!btn.classList.contains("active")) this._styleFormatBtn(btn, true, true) })
      btn.addEventListener("mouseout",  () => { if (!btn.classList.contains("active")) this._styleFormatBtn(btn, false) })
      btn.addEventListener("click",     () => this._applyFormat(value, btn))
      container.appendChild(btn)
    })
  }

  // Applique les styles inline (thème-agnostiques) d'un bouton format/actif.
  _styleFormatBtn(btn, active, hover = false) {
    btn.style.setProperty("padding", "0.5rem 1.1rem")
    btn.style.setProperty("border-radius", "0.5rem")
    btn.style.setProperty("font-size", "0.9rem")
    btn.style.setProperty("cursor", "pointer")
    btn.style.setProperty("border",     active ? "2px solid #1EDD88"       : "2px solid var(--theme-border-strong)", "important")
    btn.style.setProperty("background", active ? (hover ? "rgba(30,221,136,0.08)" : "rgba(30,221,136,0.12)") : "var(--theme-hover-bg)", "important")
    btn.style.setProperty("color",      active ? "#1EDD88"                  : "var(--theme-text-primary)", "important")
  }

  _applyFormat(value, clickedBtn) {
    this.formatInputTarget.value = value
    this.recapFormatTarget.textContent = FORMAT_LABELS[value] || value

    if (clickedBtn) {
      this.formatButtonsTarget.querySelectorAll(".match-level-btn").forEach(b => {
        const isActive = b === clickedBtn
        b.classList.toggle("active", isActive)
        this._styleFormatBtn(b, isActive)
      })
    }
    this._refreshStructure()
  }

  // ── Nombre de joueurs : presets ──────────────────────────────
  selectPlayerCount(event) {
    const btn = event.currentTarget
    this.libreMode = false
    this.libreSectionTarget.style.display = "none"
    this.libreBtnTarget.classList.remove("active")

    this.countBtnTargets.forEach(b => b.classList.toggle("active", b === btn))
    this.maxPlayersInputTarget.value = btn.dataset.players
    this.recapPlayersTarget.textContent = btn.dataset.players
    this._refreshStructure()
  }

  // ── Nombre de joueurs : mode Libre ───────────────────────────
  toggleLibre() {
    this.libreMode = true
    this.libreSectionTarget.style.display = ""
    this.countBtnTargets.forEach(b => b.classList.remove("active"))
    this.libreBtnTarget.classList.add("active")
    this.maxPlayersInputTarget.value = ""
    this.recapPlayersTarget.textContent = "—"
    this.buildProposals()
  }

  // Construit les propositions à partir du nombre souhaité + format courant.
  buildProposals() {
    const wanted = parseInt(this.libreInputTarget.value)
    const format = this.formatInputTarget.value
    const container = this.proposalsTarget
    container.innerHTML = ""

    if (!wanted || wanted < 2 || !format) {
      this.structurePreviewTarget.style.display = "none"
      return
    }

    const proposals = this._buildProposals(format, wanted)
    proposals.forEach((p, i) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "tournament-proposal" + (i === 0 ? " recommended" : "")
      btn.dataset.players = p.players
      btn.dataset.recap   = p.recap
      btn.dataset.action  = "click->tournament-form#selectProposal"
      btn.innerHTML = `
        <span class="tournament-proposal-head">
          ${p.recommended ? '<span class="tournament-proposal-badge">Recommandé</span>' : ""}
          <strong>${p.players} joueurs</strong>
        </span>
        <span class="tournament-proposal-recap">${p.recap}</span>`
      container.appendChild(btn)
    })
  }

  selectProposal(event) {
    const btn = event.currentTarget
    this.proposalsTarget.querySelectorAll(".tournament-proposal")
        .forEach(b => b.classList.toggle("selected", b === btn))

    this.maxPlayersInputTarget.value    = btn.dataset.players
    this.recapPlayersTarget.textContent = btn.dataset.players
    this._showStructure(btn.dataset.recap)
  }

  // Génère les propositions (LOGIQUE PROVISOIRE — affinée au Lot 3).
  _buildProposals(format, wanted) {
    const out = []
    const push = (players, recap, recommended = false) => {
      if (players >= 2 && !out.some(p => p.players === players)) out.push({ players, recap, recommended })
    }

    if (format === "poules") {
      const nearest = Math.max(4, Math.round(wanted / 4) * 4)
      push(nearest, `${nearest / 4} poules de 4 + tableau final`, true)
      push(16, "4 poules de 4 + quarts")
      push(32, "8 poules de 4 + huitièmes")
    } else if (format === "ronde_suisse") {
      push(wanted, `Ronde suisse (${wanted}) → ${wanted < 12 ? "Final 4" : "Final 8"}`, true)
      push(16, "4 rondes + Final 8")
      push(32, "5 rondes + Final 8")
    } else { // championnat
      push(wanted, `${wanted} joueurs, round-robin, top ${wanted <= 10 ? 4 : 8} en playoffs`, true)
      push(16, "16 joueurs, top 8 en playoffs")
      push(32, "32 joueurs, top 8 en playoffs")
    }
    return out.slice(0, 4)
  }

  // ── Aperçu de structure figée (presets) ──────────────────────
  _refreshStructure() {
    if (this.libreMode) { this.buildProposals(); return }

    const fmt     = this.formatInputTarget.value
    const players = parseInt(this.maxPlayersInputTarget.value)
    const preset  = (this.structures[fmt] || {})[players]

    if (preset) {
      this._showStructure(preset)
    } else {
      this.structurePreviewTarget.style.display = "none"
      this.recapStructureRowTarget.style.display = "none"
    }
  }

  _showStructure(text) {
    this.structureTextTarget.textContent = text
    this.structurePreviewTarget.style.display = ""
    this.recapStructureTarget.textContent = text
    this.recapStructureRowTarget.style.display = ""
  }

  // ── Auto-inscription du créateur ─────────────────────────────
  toggleSelfRegister() {
    this.recapSelfRegisterTarget.textContent = this.selfRegisterTarget.checked ? "Oui" : "Non"
  }

  // ── Récap : champs texte ─────────────────────────────────────
  updateName() {
    const v = this.nameInputTarget.value.trim()
    this.recapNameTarget.textContent = v ? (v.charAt(0).toUpperCase() + v.slice(1)) : "Nom du tournoi"
  }

  updateDescription() {
    const v = this.descriptionInputTarget.value.trim()
    if (v) {
      this.recapDescriptionTarget.textContent = v.length > 80 ? v.slice(0, 80) + "…" : v
      this.recapDescriptionTarget.style.display = ""
    } else {
      this.recapDescriptionTarget.style.display = "none"
    }
  }

  updatePlace() {
    this.recapPlaceTarget.textContent = this.placeInputTarget.value.trim() || "—"
  }

  updateCoOrg() {
    this.recapCoOrgTarget.textContent = this.coOrgInputTarget.value.trim() || "—"
  }

  updateDate() {
    const iso = this.dateInputTarget.value
    if (!iso) { this.recapDateTarget.textContent = "—"; return }
    const d = new Date(iso)
    this.recapDateTarget.textContent = isNaN(d) ? iso
      : d.toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "numeric" })
  }

  updateTime() {
    const h = this.element.querySelector("[name='tournament[time(4i)]']")?.value
    const m = this.element.querySelector("[name='tournament[time(5i)]']")?.value
    this.recapTimeTarget.textContent = (h ? `${String(h).padStart(2, "0")}h${String(m || 0).padStart(2, "0")}` : "—")
  }

  updateDeadline() {
    const date = this.element.querySelector("[name='deadline_date']")?.value
    const h    = this.element.querySelector("[name='deadline_hour']")?.value
    const m    = this.element.querySelector("[name='deadline_min']")?.value
    if (!date) { this.recapDeadlineTarget.textContent = "—"; return }

    const d = new Date(date)
    const datePart = isNaN(d) ? date : d.toLocaleDateString("fr-FR", { day: "2-digit", month: "short" })
    const timePart = h ? ` à ${String(h).padStart(2, "0")}h${String(m || 0).padStart(2, "0")}` : ""
    this.recapDeadlineTarget.textContent = datePart + timePart
  }
}
