// ══════════════════════════════════════════════════════════════
// Contrôleur Stimulus : tournament-form
// ══════════════════════════════════════════════════════════════
// Version allégée de match-form, dédiée à la création d'un tournoi :
//   • récapitulatif (sidebar droite) mis à jour en temps réel
//   • boutons de format générés dynamiquement selon le sport
//   • nombre de joueurs : presets 8/16/32 OU mode "Libre" (saisie d'un
//     nombre souhaité → 1 config recommandée + propositions alternatives)
//   • réglages de structure PERSONNALISABLES (Lot 7) : taille des poules, seuils
//     de la ronde suisse, taille du tableau final — vides = valeurs recommandées
//   • aperçu de la structure, recalculé en direct depuis ces réglages
//   • toggle d'auto-inscription du créateur
// ══════════════════════════════════════════════════════════════

import { Controller } from "@hotwired/stimulus"

// Libellés lisibles des formats (miroir de Tournament::FORMAT_LABELS).
const FORMAT_LABELS = {
  ronde_suisse: "Ronde Suisse",
  poules:       "Poules",
  championnat:  "Championnat"
}

// Valeurs recommandées — MIROIR des défauts du modèle : Tournament::DEFAULT_POOL_SIZE
// et TournamentUser::WINS_TO_QUALIFY / LOSSES_TO_ELIMINATE. Toute évolution doit être
// répercutée ici (l'aperçu doit annoncer ce que le serveur appliquera réellement).
const DEFAULTS = { poolSize: 4, wins: 3, losses: 3 }

// Nom du tour d'entrée d'un tableau final selon sa taille (miroir de
// Tournament::BRACKET_STAGE_NAMES).
const BRACKET_STAGE_NAMES = { 2: "finale", 4: "demi-finales", 8: "quarts", 16: "huitièmes" }

export default class extends Controller {
  static targets = [
    // Sources
    "sportInput", "formatInput", "formatWrapper", "formatButtons",
    "nameInput", "descriptionInput", "placeInput", "dateInput",
    "maxPlayersInput", "presetsGroup", "countBtn", "libreBtn", "libreSection", "libreInput",
    "proposals", "structurePreview", "structureText", "selfRegister", "coOrgInput",
    "playoffsWrapper", "playoffsInput", "playoffsBtn", "bannerImageInput",
    // Réglages de structure personnalisables (Lot 7)
    "advancedSection", "advancedToggle", "advancedFields",
    "poolSizeField", "poolSizeInput", "winsField", "winsInput",
    "lossesField", "lossesInput", "bracketSizeField", "bracketSizeInput",
    // Récapitulatif
    "recapName", "recapDescription", "recapSport", "recapFormat", "recapFormatRow",
    "recapDate", "recapPlace", "recapPlayers",
    "recapStructure", "recapStructureRow", "recapSelfRegister", "recapDeadline", "recapCoOrg",
    "recapPlayoffsRow", "recapPlayoffs"
  ]

  connect() {
    // Vrai quand l'utilisateur est en saisie "Libre" (nombre arbitraire).
    this.libreMode = false
    // Vrai quand le mode Libre a été forcé par le format championnat (pas un choix
    // manuel) — permet de le désactiver proprement si on change de format ensuite.
    this.forcedLibreByChampionnat = false

    // Initialise le récap avec les valeurs déjà présentes (sport par défaut, etc.).
    this.updateName()
    this.updateDescription()
    this.updateSport()   // rend les boutons de format + applique le 1er format (+ bannière)
    this.updateDate()
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

    this.updateBanner()
  }

  // ── Bannière : le fond de la page suit le sport sélectionné ──
  // Même mécanique que match-form : une image tirée parmi celles du sport, écrite
  // dans le hidden banner_image pour être persistée (la carte du tournoi et sa page
  // afficheront ensuite exactement cette image, cf. sport_cover_image).
  //
  // ⚠️  Le tirage n'a lieu que si le sport a changé (ou si aucune image n'est encore
  // retenue) : connect() appelle updateSport(), donc sans cette garde une simple
  // édition du tournoi changerait son image à chaque enregistrement.
  updateBanner() {
    const select    = this.sportInputTarget
    const imagesMap = JSON.parse(select.dataset.images || "{}")
    const images    = imagesMap[select.value] || []
    const current   = this.bannerImageInputTarget.value

    if (!images.length) return

    const image = current && images.includes(current)
      ? current
      : images[Math.floor(Math.random() * images.length)]

    this.bannerImageInputTarget.value = image

    // Bannière présente sur /tournois/new et /tournois/:id/edit — absente ailleurs.
    const bannerEl = document.getElementById("tournament-new-banner")
    if (bannerEl) {
      // Gradient sombre par-dessus l'image : garde le titre lisible.
      bannerEl.style.background = `linear-gradient(rgba(0,0,0,0.65), rgba(0,0,0,0.65)), url('${image}') center 25% / cover no-repeat`
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
    // _syncPlayerCountMode appelle déjà buildProposals() en entrant de force en
    // mode Libre (championnat) : éviter de le rappeler ici, ça écraserait la
    // sélection qu'elle vient de restaurer.
    const enteredLibre = this._syncPlayerCountMode(value)
    if (!enteredLibre) this._refreshStructure()
    this._syncPlayoffsMode(value)
  }

  // ── Playoffs (Lot 6) : réglage propre au championnat ─────────
  // Masqué pour les autres formats (ronde suisse / poules toujours en playoffs).
  _syncPlayoffsMode(format) {
    const isChampionnat = format === "championnat"
    this.playoffsWrapperTarget.style.display  = isChampionnat ? "" : "none"
    this.recapPlayoffsRowTarget.style.display = isChampionnat ? "" : "none"
    if (isChampionnat) this._applyPlayoffsValue(this.playoffsInputTarget.value !== "false")
  }

  selectPlayoffs(event) {
    this._applyPlayoffsValue(event.currentTarget.dataset.value === "true")
  }

  _applyPlayoffsValue(withPlayoffs) {
    this.playoffsInputTarget.value = withPlayoffs
    this.recapPlayoffsTarget.textContent = withPlayoffs ? "Oui" : "Non"
    this.playoffsBtnTargets.forEach(btn => {
      const active = (btn.dataset.value === "true") === withPlayoffs
      btn.classList.toggle("active", active)
      this._styleFormatBtn(btn, active)
    })
    // Avec ou sans playoffs, la structure annoncée change (et le réglage de taille
    // du tableau final n'a plus lieu d'être sans playoffs).
    this._refreshStructure()
  }

  // ── Championnat : pas de nombre de joueurs prédéfini ─────────
  // Le round-robin n'a aucune contrainte de puissance de 2 (contrairement à la
  // ronde suisse / au tableau final) : le nombre de joueurs dépend uniquement
  // de qui s'inscrit. On masque les presets 8/16/32 et le bouton "Libre" pour
  // ne garder que la saisie libre, seul mode pertinent pour ce format.
  // @return {boolean} true si on vient de forcer l'entrée en mode Libre.
  _syncPlayerCountMode(format) {
    const isChampionnat = format === "championnat"
    this.presetsGroupTarget.style.display = isChampionnat ? "none" : ""
    this.libreBtnTarget.style.display     = isChampionnat ? "none" : ""

    if (isChampionnat) {
      if (!this.libreMode) {
        this._enterLibreMode(true) // préserve une valeur déjà saisie
        return true
      }
    } else if (this.forcedLibreByChampionnat) {
      this._exitForcedLibreMode()
    }
    return false
  }

  _exitForcedLibreMode() {
    this.forcedLibreByChampionnat = false
    this.libreMode = false
    this.libreSectionTarget.style.display = "none"
    this.libreBtnTarget.classList.remove("active")
  }

  // ── Nombre de joueurs : presets ──────────────────────────────
  selectPlayerCount(event) {
    const btn = event.currentTarget
    this.libreMode = false
    this.forcedLibreByChampionnat = false
    this.libreSectionTarget.style.display = "none"
    this.libreBtnTarget.classList.remove("active")

    this.countBtnTargets.forEach(b => b.classList.toggle("active", b === btn))
    this.maxPlayersInputTarget.value = btn.dataset.players
    this.recapPlayersTarget.textContent = btn.dataset.players
    this._refreshStructure()
  }

  // ── Nombre de joueurs : mode Libre ───────────────────────────
  toggleLibre() {
    this._enterLibreMode(false)
  }

  // `preserveExisting` : true quand le mode libre est forcé par le format
  // championnat (ou restauré après un échec de validation) — garde la valeur
  // déjà saisie dans maxPlayersInput au lieu de la vider.
  _enterLibreMode(preserveExisting) {
    this.libreMode = true
    this.forcedLibreByChampionnat = this.formatInputTarget.value === "championnat"
    this.libreSectionTarget.style.display = ""
    this.countBtnTargets.forEach(b => b.classList.remove("active"))
    this.libreBtnTarget.classList.add("active")

    const existing = preserveExisting ? this.maxPlayersInputTarget.value : ""
    this.libreInputTarget.value = existing

    // buildProposals() relit libreInputTarget et se charge lui-même de renseigner
    // max_players + le récap (cf. plus bas) : pas besoin de le refaire ici.
    this.buildProposals()
  }

  // Construit les propositions à partir du nombre souhaité + format courant.
  buildProposals() {
    const wanted = parseInt(this.libreInputTarget.value)
    const format = this.formatInputTarget.value
    const container = this.proposalsTarget
    container.innerHTML = ""

    if (!wanted || wanted < 2 || !format) {
      this.maxPlayersInputTarget.value = ""
      this.recapPlayersTarget.textContent = "—"
      this.structurePreviewTarget.style.display = "none"
      this.recapStructureRowTarget.style.display = "none"
      return
    }

    // Le nombre saisi est TOUJOURS la valeur réellement soumise, dès la frappe :
    // avant ce fix, max_players (hidden field) restait vide tant qu'aucune carte
    // de proposition n'était cliquée — bloquant silencieusement la création du
    // tournoi malgré un nombre visiblement rempli à l'écran.
    this.maxPlayersInputTarget.value = wanted
    this.recapPlayersTarget.textContent = wanted

    if (format === "championnat") {
      // Round-robin : aucune contrainte de puissance de 2, donc aucune carte de
      // proposition à choisir — mais l'aperçu de structure reste utile (nombre de
      // journées, playoffs ou pas, taille du tableau final si personnalisée).
      this._showStructure(this._structureText(format, wanted))
      return
    }

    const proposals = this._buildProposals(format, wanted)
    proposals.forEach((p) => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "tournament-proposal"
        + (p.recommended ? " recommended" : "")
        + (p.players === wanted ? " selected" : "")
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
    this._showStructure(proposals[0].recap)
  }

  selectProposal(event) {
    const btn = event.currentTarget
    this.proposalsTarget.querySelectorAll(".tournament-proposal")
        .forEach(b => b.classList.toggle("selected", b === btn))

    this.maxPlayersInputTarget.value    = btn.dataset.players
    this.recapPlayersTarget.textContent = btn.dataset.players
    this._showStructure(btn.dataset.recap)
  }

  // Génère les propositions d'effectif pour le mode Libre. Le récap de chaque carte
  // est calculé par _structureText : il reflète donc les réglages personnalisés.
  // Championnat exclu : géré à part dans buildProposals() (pas de carte, aperçu direct).
  _buildProposals(format, wanted) {
    const out = []
    const push = (players, recommended = false) => {
      if (players >= 2 && !out.some(p => p.players === players)) {
        out.push({ players, recap: this._structureText(format, players), recommended })
      }
    }

    if (format === "poules") {
      // Effectif le plus proche qui remplit des poules entières.
      const { poolSize } = this._settings()
      push(Math.max(poolSize, Math.round(wanted / poolSize) * poolSize), true)
    } else {
      push(wanted, true)
    }
    push(16)
    push(32)
    return out.slice(0, 4)
  }

  // ══════════════════════════════════════════════════════════
  // Réglages de structure personnalisables (Lot 7)
  // ══════════════════════════════════════════════════════════
  toggleAdvanced() {
    const fields = this.advancedFieldsTarget
    const open = fields.hidden
    fields.hidden = !open
    this.advancedToggleTarget.setAttribute("aria-expanded", String(open))
  }

  // Action des champs de réglage : l'aperçu de structure suit la saisie.
  refreshStructure() {
    this._refreshStructure()
  }

  // Réglages actuellement saisis, complétés par les valeurs recommandées.
  // bracketSize reste null si vide : sa recommandation dépend du format/effectif.
  _settings() {
    const int = (target) => {
      const value = parseInt(target.value)
      return Number.isFinite(value) && value > 0 ? value : null
    }

    return {
      poolSize:    int(this.poolSizeInputTarget) || DEFAULTS.poolSize,
      wins:        int(this.winsInputTarget)     || DEFAULTS.wins,
      losses:      int(this.lossesInputTarget)   || DEFAULTS.losses,
      bracketSize: int(this.bracketSizeInputTarget)
    }
  }

  // Miroirs de Tournament#planned_pool_count / #planned_final_size / #planned_bracket_stage.
  _poolCount(players, poolSize) { return Math.max(Math.ceil(players / poolSize), 1) }

  _finalSize(format, players, settings) {
    if (settings.bracketSize) return settings.bracketSize
    // Poules : 2 qualifiés par poule, arrondis à la puissance de 2 supérieure —
    // un tableau à élimination directe n'a que 2, 4, 8, 16… places (miroir de
    // Tournament#bracket_capacity_for).
    if (format === "poules") {
      const qualified = this._poolCount(players, settings.poolSize) * 2
      let size = 2
      while (size < qualified) size *= 2
      return size
    }

    return players <= 8 ? 4 : 8
  }

  _stageName(size) { return BRACKET_STAGE_NAMES[size] || `tableau à ${size}` }

  // Miroir de Tournament#structure_summary : ce que le serveur produira réellement.
  _structureText(format, players) {
    const settings = this._settings()
    const stage = this._stageName(this._finalSize(format, players, settings))

    if (format === "poules") {
      return `${this._poolCount(players, settings.poolSize)} poules de ${settings.poolSize} + ${stage}`
    }
    if (format === "ronde_suisse") {
      return `Ronde suisse (${settings.wins} V / ${settings.losses} D) + ${stage}`
    }

    const base = `${players} joueurs, ${players - 1} journées`
    return this._withPlayoffs()
      ? `${base}, top ${this._finalSize(format, players, settings)} en playoffs`
      : `${base}, vainqueur = 1er du classement`
  }

  _withPlayoffs() { return this.playoffsInputTarget.value !== "false" }

  // Affiche les seuls réglages pertinents pour le format, avec la valeur
  // recommandée en placeholder. Le bloc n'apparaît qu'une fois l'effectif choisi :
  // sans lui, aucune recommandation n'est calculable.
  _syncAdvanced(format, players) {
    const ready = Boolean(format) && Number.isFinite(players) && players >= 2
    this.advancedSectionTarget.style.display = ready ? "" : "none"
    if (!ready) return

    const isPools = format === "poules"
    const isSwiss = format === "ronde_suisse"
    // Championnat sans playoffs : pas de tableau final, donc rien à dimensionner
    // (cf. Tournament#bracket_expected?).
    const hasBracket = format !== "championnat" || this._withPlayoffs()

    this.poolSizeFieldTarget.style.display    = isPools ? "" : "none"
    this.winsFieldTarget.style.display        = isSwiss ? "" : "none"
    this.lossesFieldTarget.style.display      = isSwiss ? "" : "none"
    this.bracketSizeFieldTarget.style.display = hasBracket ? "" : "none"

    this.poolSizeInputTarget.placeholder = `Recommandé : ${DEFAULTS.poolSize}`
    this.winsInputTarget.placeholder     = `Recommandé : ${DEFAULTS.wins}`
    this.lossesInputTarget.placeholder   = `Recommandé : ${DEFAULTS.losses}`
  }

  // ── Aperçu de structure ──────────────────────────────────────
  _refreshStructure() {
    const format  = this.formatInputTarget.value
    const players = parseInt(this.maxPlayersInputTarget.value)
    this._syncAdvanced(format, players)

    if (this.libreMode) { this.buildProposals(); return }

    if (format && Number.isFinite(players) && players >= 2) {
      this._showStructure(this._structureText(format, players))
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
