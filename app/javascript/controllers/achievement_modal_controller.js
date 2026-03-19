import { Controller } from "@hotwired/stimulus"

// ── Modal achievement — carte RONDE avec tilt 3D + momentum + shine ──────────
//
// Effets visuels :
//  • Hover  → tilt 3D (rotateX/Y) + reflet lumineux qui suit la souris
//  • Drag   → momentum avec vélocité variable selon la vitesse du curseur
//  • Idle   → animation de flottement CSS
//  • Snap   → rebond élastique au retour sur 0° ou 180°

export default class extends Controller {
  static targets = ["overlay", "wrapper", "card", "shine", "emoji", "name", "description", "xp", "locked", "unlocked"]

  connect() {
    this.rotation  = 0       // rotation Y accumulée (drag)
    this.tiltX     = 0       // inclinaison X du hover
    this.tiltY     = 0       // inclinaison Y du hover
    this.isDragging = false
    this.startX    = 0
    this.lastX     = 0
    this.velocity  = 0       // degrés/ms
    this.lastTime  = 0
    this.rafId     = null

    this.boundMove      = this.onMove.bind(this)
    this.boundEnd       = this.onEnd.bind(this)
    this.boundHover     = this.onHover.bind(this)
    this.boundHoverLeave = this.onHoverLeave.bind(this)
  }

  disconnect() {
    this._removeListeners()
    if (this.rafId) cancelAnimationFrame(this.rafId)
  }

  // ── Ouvre la modal ────────────────────────────────────────────────────────
  open(event) {
    const p = event.params

    if (this.rafId) { cancelAnimationFrame(this.rafId); this.rafId = null }

    // Supprime un éventuel flyer précédent (double-clic rapide)
    if (this._flyer) { this._flyer.remove(); this._flyer = null }
    if (this._flyerTimer) { clearTimeout(this._flyerTimer); this._flyerTimer = null }

    // Remplit les données (recto + verso)
    this.emojiTargets.forEach(el => el.textContent = p.emoji)
    this.nameTargets.forEach(el  => el.textContent = p.name)
    this.descriptionTargets.forEach(el => el.textContent = p.description)
    this.xpTargets.forEach(el    => el.textContent = `+${p.xp} XP`)

    // Stimulus auto-cast les params : "true" → true (booléen)
    const isUnlocked = p.unlocked === true || p.unlocked === "true"

    if (this.hasLockedTarget)   this.lockedTargets.forEach(el   => el.style.display = isUnlocked ? "none" : "flex")
    if (this.hasUnlockedTarget) this.unlockedTargets.forEach(el => el.style.display = isUnlocked ? "flex" : "none")

    this.cardTarget.classList.toggle("is-unlocked", isUnlocked)

    // Reset état 3D de la carte
    this.rotation = 0; this.tiltX = 0; this.tiltY = 0; this.velocity = 0
    this.cardTarget.style.transition = "none"
    this._applyTransform()

    // Active le hover tilt
    this.sceneElement.addEventListener("mousemove",  this.boundHover)
    this.sceneElement.addEventListener("mouseleave", this.boundHoverLeave)

    // ── Hero animation : emoji volant depuis le badge ─────────────────────
    //
    // On crée un <span> position:fixed avec l'emoji du badge.
    // Il est ancré au centre de l'écran via left/top = 50vw/50vh,
    // puis décalé + réduit via transform pour se superposer exactement
    // sur le badge. On anime ensuite le transform vers translate(-50%,-50%)
    // pour qu'il arrive au centre à pleine taille.
    // Quand l'animation se termine → on l'efface et on affiche la vraie carte.

    const badge = event.currentTarget
    const rect  = badge.getBoundingClientRect()

    // Position du badge par rapport au centre de l'écran
    const dx = rect.left + rect.width  / 2 - window.innerWidth  / 2
    const dy = rect.top  + rect.height / 2 - window.innerHeight / 2

    // Facteur d'échelle : taille du badge (48px) / taille du cercle volant (260px)
    // → le cercle démarre exactement superposé sur le badge
    const startScale = rect.width / 260

    // Crée l'emoji volant — cercle identique au badge + carte modale
    // Taille fixée à 260px (= scène modale), mis à l'échelle via transform
    // → la bordure verte voyage avec l'emoji tout au long du vol
    const FLYER_SIZE = 260
    const emojiPx    = Math.round(FLYER_SIZE * 0.55)   // proportion badge → emoji

    const flyer = document.createElement("div")
    flyer.className = "achievement-flyer"
    // Emoji centré dans le cercle
    flyer.innerHTML = `<span style="font-size:${emojiPx}px;line-height:1;display:block;">${p.emoji}</span>`
    Object.assign(flyer.style, {
      position:       "fixed",
      zIndex:         "10001",
      width:          `${FLYER_SIZE}px`,
      height:         `${FLYER_SIZE}px`,
      borderRadius:   "50%",
      display:        "flex",
      alignItems:     "center",
      justifyContent: "center",
      left:           "50%",
      top:            "50%",
      // Part de la position exacte du badge, à sa taille
      transform:      `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) scale(${startScale})`,
      pointerEvents:  "none",
      transition:     "none",
      willChange:     "transform, opacity",
      // Fond et bordure identiques au badge (verts si déverrouillé)
      background:     isUnlocked ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.03)",
      border:         isUnlocked ? "2px solid #1EDD88"      : "1px solid rgba(255,255,255,0.08)",
      boxShadow:      isUnlocked
        ? "0 0 0 4px rgba(30,221,136,0.18), 0 0 30px rgba(30,221,136,0.45), 0 0 70px rgba(30,221,136,0.2)"
        : "none"
    })
    document.body.appendChild(flyer)
    this._flyer = flyer

    // Cache la vraie carte pendant le vol
    this.wrapperTarget.style.opacity   = "0"
    this.wrapperTarget.style.transition = "none"

    // Ouvre le fond sombre en parallèle
    void this.overlayTarget.offsetHeight
    this.overlayTarget.classList.add("is-open")
    document.body.style.overflow = "hidden"

    // Double RAF : garantit que le navigateur a rendu le frame de départ
    // avant de lancer la transition (void offsetHeight seul ne suffit pas
    // pour les éléments fraîchement insérés dans le DOM)
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        // Vérifie que le flyer est toujours là (pas de fermeture rapide)
        if (!this._flyer) return

        // ease-out : démarre fort depuis le badge, décélère doucement à l'arrivée
        // (pas de cubic-bezier avec overshoot qui rushait la première moitié)
        flyer.style.transition = "transform 1.6s cubic-bezier(0.16, 1, 0.3, 1)"
        flyer.style.transform  = "translate(-50%, -50%) scale(1)"

        // Crossfade : 200ms avant la fin du vol, le flyer fade out pendant
        // que la vraie carte fade in — élimine la cassure visuelle
        this._flyerTimer = setTimeout(() => {
          if (!this._flyer) return

          // Fade out du flyer et fade in du wrapper en même temps
          this._flyer.style.transition = "opacity 0.25s ease"
          this._flyer.style.opacity    = "0"
          this.wrapperTarget.style.transition = "opacity 0.25s ease"
          this.wrapperTarget.style.opacity    = "1"

          // Supprime le flyer après le fondu
          const f = this._flyer
          setTimeout(() => f.remove(), 260)
          this._flyer     = null
          this._flyerTimer = null
        }, 1350)
      })
    })
  }

  // ── Ferme la modal ────────────────────────────────────────────────────────
  close() {
    // Coupe le flyer s'il est encore en vol
    if (this._flyer)      { this._flyer.remove(); this._flyer = null }
    if (this._flyerTimer) { clearTimeout(this._flyerTimer); this._flyerTimer = null }

    // Fermeture rapide : fade en 150ms (override la transition CSS de 300ms)
    this.overlayTarget.style.transition = "opacity 0.15s ease"
    this.overlayTarget.classList.remove("is-open")
    document.body.style.overflow = ""
    this.sceneElement.removeEventListener("mousemove",  this.boundHover)
    this.sceneElement.removeEventListener("mouseleave", this.boundHoverLeave)

    // Remet le wrapper invisible et réinitialise la transition de l'overlay
    setTimeout(() => {
      this.wrapperTarget.style.transition  = "none"
      this.wrapperTarget.style.opacity     = "0"
      this.overlayTarget.style.transition  = "" // rétablit la transition CSS d'origine
    }, 180)
  }

  closeOnOverlay(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  // ── Hover tilt : la carte s'incline vers la souris ────────────────────────
  onHover(event) {
    if (this.isDragging) return

    const rect = this.sceneElement.getBoundingClientRect()
    const cx   = rect.left + rect.width  / 2
    const cy   = rect.top  + rect.height / 2

    // Normalise entre -1 et 1
    const nx = (event.clientX - cx) / (rect.width  / 2)
    const ny = (event.clientY - cy) / (rect.height / 2)

    // Tilt max 14°
    this.tiltX = -ny * 14
    this.tiltY =  nx * 14

    // Déplace le reflet lumineux selon la position de la souris
    // Déplace le reflet sur chaque face (backface-visibility:hidden masque la face cachée)
    if (this.hasShineTarget) {
      const px = ((event.clientX - rect.left) / rect.width)  * 100
      const py = ((event.clientY - rect.top)  / rect.height) * 100
      const grad = `radial-gradient(circle at ${px}% ${py}%, rgba(255,255,255,0.2) 0%, transparent 60%)`
      this.shineTargets.forEach(el => {
        el.style.background = grad
        el.style.opacity = "1"
      })
    }

    this.cardTarget.style.transition = "transform 0.08s ease-out"
    this._applyTransform()
  }

  onHoverLeave() {
    if (this.isDragging) return
    this.tiltX = 0
    this.tiltY = 0

    if (this.hasShineTarget) this.shineTargets.forEach(el => el.style.opacity = "0")

    this.cardTarget.style.transition = "transform 0.5s cubic-bezier(0.34, 1.2, 0.64, 1)"
    this._applyTransform()
  }

  // ── Flèches : tourne de 180° vers la gauche ou la droite ─────────────────
  flipLeft() {
    this._flipTo(this.rotation - 180)
  }

  flipRight() {
    this._flipTo(this.rotation + 180)
  }

  // Anime vers une cible précise avec rebond élastique
  _flipTo(target) {
    // Annule tout momentum en cours
    if (this.rafId) { cancelAnimationFrame(this.rafId); this.rafId = null }

    this.rotation = target
    this.velocity = 0
    // Transition élastique identique au snap après momentum
    this.cardTarget.style.transition = "transform 0.55s cubic-bezier(0.34, 1.5, 0.64, 1)"
    this._applyTransform()
  }

  // ── Drag : début ──────────────────────────────────────────────────────────
  dragStart(event) {
    if (this.rafId) { cancelAnimationFrame(this.rafId); this.rafId = null }

    this.isDragging = true
    this.tiltX      = 0       // désactive le hover tilt pendant le drag
    this.tiltY      = 0
    this.startX     = this.getX(event)
    this.lastX      = this.startX
    this.velocity   = 0
    this.lastTime   = performance.now()

    this.cardTarget.style.transition        = "none"
    this.sceneElement.style.cursor          = "grabbing"
    this.sceneElement.style.animationPlayState = "paused"  // stop le flottement
    if (this.hasShineTarget) this.shineTargets.forEach(el => el.style.opacity = "0")

    window.addEventListener("mousemove", this.boundMove)
    window.addEventListener("mouseup",   this.boundEnd)
    window.addEventListener("touchmove", this.boundMove, { passive: false })
    window.addEventListener("touchend",  this.boundEnd)

    event.preventDefault()
  }

  // ── Drag : mouvement — vélocité instantanée ───────────────────────────────
  onMove(event) {
    if (!this.isDragging) return
    event.preventDefault()

    const now      = performance.now()
    const currentX = this.getX(event)
    const dt       = now - this.lastTime
    const dx       = currentX - this.lastX

    // Moyenne glissante sur la vélocité pour lisser les pics
    if (dt > 0) {
      const rawVel  = (dx * 0.5) / dt
      this.velocity = this.velocity * 0.6 + rawVel * 0.4  // lerp
    }

    const totalDx      = currentX - this.startX
    const liveRotation = this.rotation + totalDx * 0.6

    this.cardTarget.style.transform = `rotateX(0deg) rotateY(${liveRotation}deg)`

    this.lastX    = currentX
    this.lastTime = now
  }

  // ── Drag : relâche → momentum ─────────────────────────────────────────────
  onEnd(event) {
    if (!this.isDragging) return
    this.isDragging = false
    this._removeListeners()

    const currentX    = this.getX(event) || this.lastX
    const totalDx     = currentX - this.startX
    this.rotation    += totalDx * 0.6
    this.sceneElement.style.cursor             = "grab"
    this.sceneElement.style.animationPlayState = "running"

    this.lastTime = performance.now()
    this._animateMomentum()
  }

  // ── Momentum : élan → friction → snap élastique ───────────────────────────
  _animateMomentum() {
    const now = performance.now()
    const dt  = Math.min(now - this.lastTime, 32)  // cap à 32ms pour éviter les sauts
    this.lastTime = now

    this.rotation += this.velocity * dt
    // Friction douce — plus la carte va vite, plus elle garde son élan
    this.velocity *= Math.pow(0.90, dt / 16)

    this.cardTarget.style.transform = `rotateX(0deg) rotateY(${this.rotation}deg)`

    if (Math.abs(this.velocity) > 0.012) {
      this.rafId = requestAnimationFrame(() => this._animateMomentum())
    } else {
      // Snap sur le 180° le plus proche avec rebond élastique
      const target  = Math.round(this.rotation / 180) * 180
      this.rotation = target
      this.velocity = 0
      this.cardTarget.style.transition = "transform 0.55s cubic-bezier(0.34, 1.5, 0.64, 1)"
      this._applyTransform()
      this.rafId = null
    }
  }

  // ── Applique la transformation combinée tilt + rotation ──────────────────
  _applyTransform() {
    this.cardTarget.style.transform =
      `rotateX(${this.tiltX}deg) rotateY(${this.rotation + this.tiltY}deg)`
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────
  getX(event) {
    return event.touches        ? event.touches[0].clientX
         : event.changedTouches ? event.changedTouches[0].clientX
         : event.clientX
  }

  _removeListeners() {
    window.removeEventListener("mousemove", this.boundMove)
    window.removeEventListener("mouseup",   this.boundEnd)
    window.removeEventListener("touchmove", this.boundMove)
    window.removeEventListener("touchend",  this.boundEnd)
  }

  get sceneElement() { return this.cardTarget.parentElement }
}
