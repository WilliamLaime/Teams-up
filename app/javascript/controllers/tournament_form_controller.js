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
  ronde_suisse:      "Ronde Suisse",
  poules:            "Poules",
  championnat:       "Championnat",
  criterium_federal: "Critérium Fédéral"
}

// Seuils d'effectif du Critérium — miroir de Tournament::CRITERIUM_POOLS_ONLY_MAX
// et CRITERIUM_INTEGRAL_MAX. Au-delà, la structure standard (barrages + tableau
// final + consolante) ; en dessous, poule unique ou classement intégral.
const CRITERIUM_POOLS_ONLY_MAX = 7
const CRITERIUM_INTEGRAL_MAX   = 16

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
    "maxPlayersInput", "countBtn", "libreBtn", "libreSection", "libreInput",
    "unlimitedBtn", "unlimitedHint",
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
    // Vrai quand l'organisateur a choisi « Sans limite » : max_players reste vide,
    // aucun plafond n'est annoncé. À distinguer d'un effectif simplement pas
    // encore choisi — d'où un drapeau explicite plutôt qu'un test sur le champ.
    this.unlimitedMode = this.hasUnlimitedBtnTarget &&
                         this.unlimitedBtnTarget.classList.contains("active")
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
    // On masque les presets UN PAR UN et non la rangée entière : « Sans limite »
    // y figure aussi et doit rester accessible en championnat.
    this.countBtnTargets.forEach(b => { b.style.display = isChampionnat ? "none" : "" })
    this.libreBtnTarget.style.display = isChampionnat ? "none" : ""

    if (isChampionnat) {
      // « Sans limite » est un choix explicite et compatible avec le championnat :
      // on ne le remplace pas par une saisie libre dans le dos de l'organisateur.
      if (!this.libreMode && !this.unlimitedMode) {
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

  // ── Nombre de joueurs : sans limite ──────────────────────────
  // Le seul mode qui laisse max_players VIDE. Il n'y a alors pas de structure à
  // prévisualiser (elle dépendra des inscrits), ni de réglages avancés à
  // proposer : leurs valeurs recommandées se calculent toutes sur l'effectif.
  selectUnlimited() {
    this.unlimitedMode = true
    this.libreMode = false
    this.forcedLibreByChampionnat = false

    this.libreSectionTarget.style.display = "none"
    this.libreBtnTarget.classList.remove("active")
    this.countBtnTargets.forEach(b => b.classList.remove("active"))
    this.unlimitedBtnTarget.classList.add("active")
    this.unlimitedHintTarget.style.display = ""

    this.maxPlayersInputTarget.value = ""
    this.recapPlayersTarget.textContent = "Sans limite"
    this.structurePreviewTarget.style.display = "none"
    this.recapStructureRowTarget.style.display = "none"
    this.advancedSectionTarget.style.display = "none"
  }

  // Quitte le mode « sans limite ». Appelé par tout autre choix d'effectif.
  _exitUnlimitedMode() {
    if (!this.unlimitedMode) return

    this.unlimitedMode = false
    this.unlimitedBtnTarget.classList.remove("active")
    this.unlimitedHintTarget.style.display = "none"
  }

  // ── Nombre de joueurs : presets ──────────────────────────────
  selectPlayerCount(event) {
    const btn = event.currentTarget
    this.libreMode = false
    this.forcedLibreByChampionnat = false
    this._exitUnlimitedMode()
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
    this._exitUnlimitedMode()
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
      // Critérium compris : il équilibre lui-même ses poules (4/4/3 à 11 joueurs),
      // aucun effectif n'est « mal rempli » — on propose le nombre demandé tel quel.
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
      // Distinct de poolSize : en Critérium, « vide » ne veut pas dire 4 mais
      // « laisse les seuils du règlement décider » (cf. _criteriumPoolCount).
      explicitPoolSize: int(this.poolSizeInputTarget),
      wins:        int(this.winsInputTarget)     || DEFAULTS.wins,
      losses:      int(this.lossesInputTarget)   || DEFAULTS.losses,
      bracketSize: int(this.bracketSizeInputTarget)
    }
  }

  // Miroirs de Tournament#planned_pool_count / #planned_final_size / #planned_bracket_stage.
  _poolCount(players, poolSize) { return Math.max(Math.ceil(players / poolSize), 1) }

  // Miroir de Tournament#bracket_capacity_for : un tableau à élimination directe
  // n'a que 2, 4, 8, 16… places (les places en trop sont des byes).
  _capacityFor(qualified) {
    let size = 2
    while (size < qualified) size *= 2
    return size
  }

  // ── Critérium Fédéral : miroirs des seuils du règlement ─────────────────────
  // Tournament#criterium_pool_count_for. Un réglage explicite de taille de poule
  // gagne, comme côté serveur.
  _criteriumPoolCount(players, explicitPoolSize) {
    if (explicitPoolSize) return this._poolCount(players, explicitPoolSize)
    if (players <= CRITERIUM_POOLS_ONLY_MAX) return 1
    if (players <= 10) return 2
    if (players === 11) return 3
    if (players <= CRITERIUM_INTEGRAL_MAX) return 4
    return this._poolCount(players, DEFAULTS.poolSize)
  }

  // Tournament#pool_plan : la taille de chaque poule, les plus grandes d'abord.
  _criteriumPoolPlan(players, explicitPoolSize) {
    const pools = this._criteriumPoolCount(players, explicitPoolSize)
    const base  = Math.floor(players / pools)
    const extra = players % pools
    return Array.from({ length: pools }, (_, i) => base + (i < extra ? 1 : 0))
  }

  // Tournament#criterium_mode : la variante déduite de l'effectif.
  _criteriumMode(players) {
    if (players <= CRITERIUM_POOLS_ONLY_MAX) return "none"
    return players <= CRITERIUM_INTEGRAL_MAX ? "integral" : "standard"
  }

  _finalSize(format, players, settings) {
    if (settings.bracketSize) return settings.bracketSize
    // Classement intégral : tout l'effectif entre dans le tableau unique.
    if (format === "criterium_federal" && this._criteriumMode(players) === "integral") {
      return this._capacityFor(players)
    }
    // Poules (et Critérium standard) : 2 qualifiés par poule.
    if (format === "poules") return this._capacityFor(this._poolCount(players, settings.poolSize) * 2)
    if (format === "criterium_federal") {
      return this._capacityFor(this._criteriumPoolPlan(players, settings.explicitPoolSize).length * 2)
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
    if (format === "criterium_federal") {
      return this._criteriumText(players, settings, stage)
    }
    if (format === "ronde_suisse") {
      return `Ronde suisse (${settings.wins} V / ${settings.losses} D) + ${stage}`
    }

    const base = `${players} joueurs, ${players - 1} journées`
    return this._withPlayoffs()
      ? `${base}, top ${this._finalSize(format, players, settings)} en playoffs`
      : `${base}, vainqueur = 1er du classement`
  }

  // Miroir de Tournament#criterium_structure_summary — une phrase par variante.
  _criteriumText(players, settings, stage) {
    // La variante ne dépend QUE de l'effectif, même si l'organisateur a imposé une
    // taille de poule : c'est le règlement qui fixe les seuils (miroir exact de
    // Tournament#criterium_mode, qui ignore lui aussi players_per_pool).
    const plan = this._criteriumPoolPlan(players, settings.explicitPoolSize)
    const mode = this._criteriumMode(players)

    if (mode === "none") return `Poule unique de ${plan[0]}, classement final = classement de poule`
    if (mode === "integral") {
      const size = this._finalSize("criterium_federal", players, settings)
      return `${this._planLabel(plan)} + tableau unique de ${size}, chaque place jouée`
    }
    return `${this._planLabel(plan)}, barrages, ${stage} + consolante`
  }

  // Miroir de Tournament#pool_plan_label : « 4 poules de 4 », ou « 3 poules (4-4-3) »
  // quand l'effectif ne se divise pas — annoncer une taille unique serait faux.
  _planLabel(plan) {
    const uniform = plan.every(size => size === plan[0])
    return uniform ? `${plan.length} poules de ${plan[0]}` : `${plan.length} poules (${plan.join("-")})`
  }

  _withPlayoffs() { return this.playoffsInputTarget.value !== "false" }

  // Affiche les seuls réglages pertinents pour le format, avec la valeur
  // recommandée en placeholder. Le bloc n'apparaît qu'une fois l'effectif choisi :
  // sans lui, aucune recommandation n'est calculable.
  _syncAdvanced(format, players) {
    const ready = Boolean(format) && Number.isFinite(players) && players >= 2
    this.advancedSectionTarget.style.display = ready ? "" : "none"
    if (!ready) return

    const isCriterium = format === "criterium_federal"
    const isPools = format === "poules" || isCriterium
    const isSwiss = format === "ronde_suisse"
    // Pas de tableau final à dimensionner pour un championnat sans playoffs, ni
    // pour un Critérium à poule unique (cf. Tournament#bracket_expected?).
    const hasBracket = (format !== "championnat" || this._withPlayoffs()) &&
                       !(isCriterium && this._criteriumMode(players) === "none")

    this.poolSizeFieldTarget.style.display    = isPools ? "" : "none"
    this.winsFieldTarget.style.display        = isSwiss ? "" : "none"
    this.lossesFieldTarget.style.display      = isSwiss ? "" : "none"
    this.bracketSizeFieldTarget.style.display = hasBracket ? "" : "none"

    // Le Critérium ne connaît que les poules de 3 ou 4 (cf. la validation
    // Tournament#criterium_pool_size_is_three_or_four) ; vide = seuils du règlement.
    this.poolSizeInputTarget.placeholder = isCriterium
      ? "Recommandé : selon l'effectif (3 ou 4)"
      : `Recommandé : ${DEFAULTS.poolSize}`
    this.winsInputTarget.placeholder     = `Recommandé : ${DEFAULTS.wins}`
    this.lossesInputTarget.placeholder   = `Recommandé : ${DEFAULTS.losses}`
  }

  // ── Aperçu de structure ──────────────────────────────────────
  _refreshStructure() {
    // Sans limite : rien à prévisualiser tant qu'on ne connaît pas les inscrits.
    // On sort avant _syncAdvanced, qui rouvrirait le bloc des réglages.
    if (this.unlimitedMode) return

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
