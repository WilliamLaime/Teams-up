// Stimulus controller : countdown
// Affiche un décompte "flip clock" (effet tableau d'aéroport) jusqu'à la date cible.
//
// Usage dans la vue :
//   <div data-controller="countdown"
//        data-countdown-datetime-value="2026-03-18T20:00:00+01:00">
//   </div>
//
// Le controller construit entièrement le DOM des flip-cards et anime
// chaque chiffre indépendamment quand sa valeur change.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // La date/heure cible du match (ISO 8601, générée par Rails)
  static values = { datetime: String }

  // Stocke la valeur affichée précédemment pour chaque unité
  // → permet de n'animer que les chiffres qui changent (surtout utile pour les jours)
  _prev = { days: null, hours: null, minutes: null, seconds: null }

  // Références aux 4 éléments internes de chaque flip-card
  // Structure : { days: { top, bottom, flap, reveal }, hours: {...}, ... }
  _cards = {}

  connect() {
    // ── Nettoyage défensif ───────────────────────────────────────────────
    // 1. Stoppe un éventuel timer précédent : si connect() est rappelé sans
    //    disconnect() intermédiaire (ex : Turbo preview → page réelle), on évite
    //    d'avoir deux setInterval actifs en même temps.
    clearInterval(this._interval)

    // 2. Vide le DOM : si l'élément vient du cache Turbo avec les flip-cards déjà
    //    construites, on repart de zéro avant de les reconstruire.
    this.element.innerHTML = ""

    // ── Nettoyage avant mise en cache Turbo ──────────────────────────────
    // turbo:before-cache se déclenche juste AVANT que Turbo sauvegarde la page.
    // On vide l'élément à ce moment-là → la version en cache est vide.
    // Résultat : quand Turbo restaure la page, connect() trouve un élément vide
    // et reconstruit proprement → plus de timer en double.
    //
    // On retire d'abord l'ancien listener (si connect() est rappelé plusieurs fois)
    // pour ne jamais avoir deux listeners sur le même document.
    document.removeEventListener("turbo:before-cache", this._beforeCacheHandler)
    this._beforeCacheHandler = () => {
      clearInterval(this._interval)          // stoppe le timer
      this.element.innerHTML = ""            // vide les flip-cards du DOM
      this._cards = {}                       // réinitialise les références internes
      this._prev  = { days: null, hours: null, minutes: null, seconds: null }
    }
    document.addEventListener("turbo:before-cache", this._beforeCacheHandler)

    const diff = new Date(this.datetimeValue) - new Date()

    // Match terminé (débuté il y a plus d'1h) → pas de flip clock, juste le statut
    if (diff <= -3600000) {
      this._showEnded()
      return
    }

    // Match en cours (débuté il y a moins d'1h) → idem, statut sans flip clock
    if (diff <= 0) {
      this._showStarted()
      return
    }

    // Match à venir → construit le flip clock et lance le décompte
    this._buildDOM()
    this._update()
    this._interval = setInterval(() => this._update(), 1000)
  }

  disconnect() {
    // Stoppe le timer pour éviter les fuites mémoire
    clearInterval(this._interval)
    // Retire le listener turbo:before-cache pour éviter qu'il reste actif
    // après que le controller a été démonté (navigation vers une autre page)
    document.removeEventListener("turbo:before-cache", this._beforeCacheHandler)
  }

  // ── Construction du DOM ────────────────────────────────────────────────

  _buildDOM() {
    // Titre "Il reste"
    const title = document.createElement("div")
    title.className   = "countdown-title"
    title.textContent = "Commence dans"
    this.element.appendChild(title)

    // Conteneur flex qui aligne les 4 unités + les ":"
    const wrapper = document.createElement("div")
    wrapper.className = "countdown-wrapper"

    // Définition des 4 unités
    const units = [
      { key: "days",    label: "jour" },
      { key: "hours",   label: "hr."  },
      { key: "minutes", label: "min." },
      { key: "seconds", label: "sec." },
    ]

    units.forEach((unit, index) => {
      // Séparateur ":" entre les unités (pas avant le premier)
      if (index > 0) {
        const colon = document.createElement("div")
        colon.className   = "flip-separator"
        colon.textContent = ":"
        wrapper.appendChild(colon)
      }

      // Crée la flip-unit (carte + label en dessous)
      const flipUnit = this._makeFlipUnit(unit.key, unit.label)
      wrapper.appendChild(flipUnit)
    })

    this.element.appendChild(wrapper)
  }

  // Crée une unité complète : flip-card + label
  _makeFlipUnit(key, label) {
    const unit = document.createElement("div")
    unit.className = "flip-unit"

    // La flip-card elle-même
    const card = document.createElement("div")
    card.className = "flip-card"

    // Les 4 demi-panneaux de la carte
    // top / bottom  : fond statique (toujours visible)
    // flap / reveal : panneaux animés (z-index supérieur)
    const top    = this._makeHalf("fc-top",    false)  // moitié haute statique
    const bottom = this._makeHalf("fc-bottom", true)   // moitié basse statique
    const flap   = this._makeHalf("fc-flap",   false)  // flap animé (ancienne valeur)
    const reveal = this._makeHalf("fc-reveal", true)   // reveal animé (nouvelle valeur)

    card.append(top, bottom, flap, reveal)

    // Stocke les références pour pouvoir les mettre à jour facilement
    this._cards[key] = { top, bottom, flap, reveal }

    // Label sous la carte (jour / hr. / min. / sec.)
    const labelEl = document.createElement("div")
    labelEl.className   = "flip-unit__label"
    labelEl.textContent = label

    unit.append(card, labelEl)
    return unit
  }

  // Crée un demi-panneau avec son <span> interne
  // isBottom = true → le span aura margin-top:-40px (voir CSS) pour montrer la moitié basse
  _makeHalf(className, isBottom) {
    const el   = document.createElement("div")
    el.className = className

    const span = document.createElement("span")
    span.textContent = "--"

    // Pour les moitiés basses, le CSS gère le décalage via margin-top: -$fc-half
    // On ajoute une classe data-attribute pour que le CSS puisse cibler
    if (isBottom) el.dataset.bottom = "true"

    el.appendChild(span)
    return el
  }

  // ── Mise à jour du compteur ────────────────────────────────────────────

  _update() {
    const target = new Date(this.datetimeValue)
    const now    = new Date()
    const diff   = target - now   // différence en millisecondes

    if (diff <= -3600000) {
      // Plus d'1h depuis le début → match terminé
      this._showEnded()
      clearInterval(this._interval)
      return
    }

    if (diff <= 0) {
      // Moins d'1h depuis le début → match en cours
      this._showStarted()
      clearInterval(this._interval)
      return
    }

    // Décompose le diff en unités
    const days    = Math.floor(diff / (1000 * 60 * 60 * 24))
    const hours   = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60))
    const seconds = Math.floor((diff % (1000 * 60)) / 1000)

    // Formate avec 2 chiffres minimum (ex: "07", "00")
    const vals = {
      days:    String(days).padStart(2, "0"),
      hours:   String(hours).padStart(2, "0"),
      minutes: String(minutes).padStart(2, "0"),
      seconds: String(seconds).padStart(2, "0"),
    }

    // Pour chaque unité : n'anime que si la valeur a changé
    Object.keys(vals).forEach(key => {
      const newVal = vals[key]
      const oldVal = this._prev[key]

      if (oldVal === null) {
        // Premier affichage : pas d'animation, juste afficher la valeur
        this._setStatic(key, newVal)
      } else if (newVal !== oldVal) {
        // Valeur différente : déclenche le flip animé
        this._flipTo(key, oldVal, newVal)
      }

      this._prev[key] = newVal
    })
  }

  // Affichage initial sans animation (évite un flip parasite au chargement)
  _setStatic(key, val) {
    const { top, bottom, flap, reveal } = this._cards[key]
    top.querySelector("span").textContent    = val
    bottom.querySelector("span").textContent = val
    flap.querySelector("span").textContent   = val
    reveal.querySelector("span").textContent = val
  }

  // ── Animation flip ────────────────────────────────────────────────────

  _flipTo(key, oldVal, newVal) {
    const { top, bottom, flap, reveal } = this._cards[key]

    // 1. fc-top → nouvelle valeur immédiatement
    //    Il est caché par le flap pendant l'animation, puis révélé quand le flap bascule
    top.querySelector("span").textContent = newVal

    // 2. fc-bottom → GARDE l'ancienne valeur pendant toute l'animation
    //    Le reveal (par-dessus) montre la nouvelle valeur et se déplie progressivement
    //    Si on mettait la nouvelle valeur ici tout de suite, elle serait visible
    //    pendant les 0.3s de délai avant que le reveal commence → effet de saut visible
    bottom.querySelector("span").textContent = oldVal

    // 3. Le flap montre l'ANCIENNE valeur (moitié haute) et bascule vers le bas
    flap.querySelector("span").textContent = oldVal

    // 4. Le reveal montre la NOUVELLE valeur (moitié basse) et se déplie depuis le bas
    reveal.querySelector("span").textContent = newVal

    // 5. Reset des classes d'animation (permet de re-déclencher si même valeur)
    flap.classList.remove("flipping")
    reveal.classList.remove("revealing")

    // forceReflow : le navigateur doit recalculer avant qu'on rajoute les classes
    void flap.offsetWidth

    // 6. Lance les deux animations
    flap.classList.add("flipping")    // 0° → −90° en 0.32s
    reveal.classList.add("revealing") // 90° → 0° en 0.32s, avec 0.3s de délai

    // 7. Une fois les animations terminées (~0.62s) : remise à zéro propre
    setTimeout(() => {
      // Met le flap à la NOUVELLE valeur avant de retirer l'animation
      // → quand il revient à rotateX(0°) il est identique à fc-top (newVal)
      // → visuellement invisible = pas de flash
      flap.querySelector("span").textContent = newVal

      // Met fc-bottom à jour avant que le reveal disparaisse
      bottom.querySelector("span").textContent = newVal

      // Retire les deux classes dans le même tick → un seul repaint
      // flap   : rotateX(0°)  + newVal = même chose que fc-top → seamless
      // reveal : rotateX(90°) = replié/invisible → fc-bottom (newVal) apparaît
      flap.classList.remove("flipping")
      reveal.classList.remove("revealing")
    }, 700)
  }

  // ── Affichage "match en cours" (débuté il y a moins d'1h) ───────────

  _showStarted() {
    this.element.innerHTML = `
      <div class="countdown-started">
        <div class="countdown-pulse"></div>
        <span>Match en cours</span>
      </div>
    `
  }

  // ── Affichage "match terminé" (débuté il y a plus d'1h) ─────────────

  _showEnded() {
    this.element.innerHTML = `
      <div class="countdown-started">
        <div class="countdown-pulse" style="background:rgba(255,255,255,0.35); box-shadow:none; animation:none;"></div>
        <span style="color:rgba(255,255,255,0.4);">Match terminé</span>
      </div>
    `
  }
}
