import { Controller } from "@hotwired/stimulus"

// ── Combobox recherchable de destination Slack (channel ou message direct) ──────
// Remplace l'ancien <select> natif : recherche instantanée (filtre par sous-chaîne),
// favoris épinglés en tête (groupe « ★ Favoris »), navigation clavier et thème cohérent.
//
// Les destinations sont DÉJÀ embarquées côté serveur (data-slack-destination-workspaces-value),
// donc tout le filtrage est en mémoire — aucun appel réseau pour lister. Seul l'épinglage
// d'un favori tape un endpoint (/slack/favorites) pour la persistance.
//
// Le champ caché `slack_channel_id` porte l'id sélectionné (vide = destination par défaut),
// exactement comme l'ancien <select> → aucun changement côté controller Rails.
export default class extends Controller {
  static targets = ["workspace", "hidden", "input", "list"]
  static values  = { workspaces: Array }

  connect() {
    // Copie locale mutable (les favoris évoluent au fil des clics sur l'étoile).
    this.workspaces = this.workspacesValue
    this.activeIndex = -1
    this.syncFavorites()

    this._outsideClick = (e) => { if (!this.element.contains(e.target)) this.close() }
    document.addEventListener("click", this._outsideClick)

    // La place disponible change avec le scroll et le redimensionnement : tant que
    // la liste est ouverte, on la replace pour qu'elle reste entièrement visible.
    this._reposition = () => { if (this.isOpen) this.positionList() }
    window.addEventListener("scroll", this._reposition, { passive: true })
    window.addEventListener("resize", this._reposition)
  }

  disconnect() {
    document.removeEventListener("click", this._outsideClick)
    window.removeEventListener("scroll", this._reposition)
    window.removeEventListener("resize", this._reposition)
  }

  get isOpen() {
    return this.hasListTarget && this.listTarget.style.display === "block"
  }

  // ── Résolution du workspace courant ───────────────────────────────────────────
  currentWorkspaceId() {
    if (this.hasWorkspaceTarget) return this.workspaceTarget.value
    return this.workspaces[0] && String(this.workspaces[0].id)
  }

  currentWorkspace() {
    const id = this.currentWorkspaceId()
    return this.workspaces.find((w) => String(w.id) === String(id))
  }

  // Ensemble des ids de channels/DM épinglés pour le workspace courant.
  syncFavorites() {
    const ws = this.currentWorkspace()
    this.favoriteIds = new Set((ws?.favorites || []).map(([, id]) => id))
  }

  // Changement d'espace Slack : on repart d'une sélection vierge.
  workspaceChanged() {
    this.hiddenTarget.value = ""
    this.inputTarget.value  = ""
    this.syncFavorites()
    this.close()
  }

  // ── Ouverture / fermeture / filtrage ────────────────────────────────────────────
  open() {
    this.render(this.inputTarget.value)
    this.listTarget.style.display = "block"
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.positionList()
  }

  close() {
    this.listTarget.style.display = "none"
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.activeIndex = -1
  }

  // ── Placement de la liste : toujours entièrement visible ────────────────────────
  // Le champ vit en bas d'une colonne sticky : la liste, en position absolue, ne
  // participe pas au flux et ne crée donc aucun scroll de page. Ouverte vers le bas
  // sans place disponible, elle passait sous la ligne de flottaison, hors d'atteinte.
  //
  // On mesure l'espace réellement disponible de part et d'autre du champ, on ouvre
  // du côté le plus dégagé, et on plafonne la hauteur à cet espace pour que le
  // scroll interne de la liste (overflow-y: auto) prenne le relais.
  positionList() {
    const MAX_HEIGHT = 260 // hauteur confortable, cf. _slack_destination.scss
    const MARGIN     = 12  // respiration avec le bord de l'écran

    const field       = this.inputTarget.getBoundingClientRect()
    const spaceBelow  = window.innerHeight - field.bottom - MARGIN
    const spaceAbove  = field.top - MARGIN
    // Vers le haut seulement si c'est franchement mieux : à espace comparable, on
    // garde le sens de lecture naturel.
    const dropUp      = spaceBelow < 160 && spaceAbove > spaceBelow

    const available = dropUp ? spaceAbove : spaceBelow
    this.listTarget.style.maxHeight = `${Math.max(120, Math.min(MAX_HEIGHT, available))}px`

    this.listTarget.classList.toggle("slack-dest-list--up", dropUp)
  }

  filter() {
    this.open()
  }

  // ── Sélection ────────────────────────────────────────────────────────────────
  onItemClick(event) {
    const el = event.currentTarget
    this.select(el.dataset.id, el.dataset.label)
  }

  select(id, label) {
    this.hiddenTarget.value = id || ""
    this.inputTarget.value  = id ? label : ""
    this.close()
  }

  // ── Favori : épingle/désépingle via l'endpoint puis re-render ───────────────────
  toggleFavorite(event) {
    // Ne pas déclencher la sélection de l'item parent.
    event.stopPropagation()
    event.preventDefault()

    const btn    = event.currentTarget
    const id     = btn.dataset.id
    const name   = btn.dataset.name
    const isFav  = this.favoriteIds.has(id)
    const method = isFav ? "DELETE" : "POST"

    this._favoriteRequest(method, id, name)
      .then((data) => {
        if (!data || !data.ok) return
        const ws = this.currentWorkspace()
        if (isFav) {
          this.favoriteIds.delete(id)
          if (ws) ws.favorites = (ws.favorites || []).filter(([, fid]) => fid !== id)
        } else {
          this.favoriteIds.add(id)
          if (ws) ws.favorites = [...(ws.favorites || []), [name, id]]
        }
        this.render(this.inputTarget.value) // liste reste ouverte
      })
      .catch(() => {})
  }

  _favoriteRequest(method, id, name) {
    const token  = document.querySelector('meta[name="csrf-token"]')?.content
    const params = new URLSearchParams({ slack_workspace_id: this.currentWorkspaceId(), channel_id: id })
    if (name) params.append("channel_name", name)
    return fetch("/slack/favorites", {
      method,
      headers: {
        "X-CSRF-Token": token,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json"
      },
      body: params.toString()
    }).then((r) => r.json())
  }

  // ── Rendu de la liste ───────────────────────────────────────────────────────────
  render(query = "") {
    const q   = query.trim().toLowerCase()
    const ws  = this.currentWorkspace()
    const dst = ws?.destinations || {}
    const fav = this.favoriteIds

    const match = (label) => q === "" || label.toLowerCase().includes(q)
    // Channels/DM privés de leurs favoris (les favoris sont regroupés en tête).
    const notFav = (pairs) => (pairs || []).filter(([, id]) => !fav.has(id))

    let html = ""

    // Item fixe « Ma destination par défaut » (id vide) — repli côté resolver.
    if (match("ma destination par défaut")) {
      html += this._itemHtml("Ma destination par défaut", "", false, false)
    }

    html += this._groupHtml("★ Favoris", (ws?.favorites || []).filter(([label]) => match(label)), true)
    html += this._groupHtml("Channels", notFav(dst["Channels"]).filter(([label]) => match(label)), false)
    html += this._groupHtml("Messages directs", notFav(dst["Messages directs"]).filter(([label]) => match(label)), false)

    if (html === "") html = `<li class="slack-dest-empty">Aucune destination</li>`

    this.listTarget.innerHTML = html
    window.lucide?.createIcons({ nameAttr: "data-lucide" })
    this.activeIndex = -1
  }

  _groupHtml(label, pairs, isFavGroup) {
    if (!pairs || pairs.length === 0) return ""
    const items = pairs.map(([lbl, id]) => this._itemHtml(lbl, id, true, isFavGroup)).join("")
    return `<li class="slack-dest-group-label" role="presentation">${this._esc(label)}</li>${items}`
  }

  // starrable=false pour l'item « défaut » (aucune étoile).
  _itemHtml(label, id, starrable, isFav) {
    const star = starrable
      ? `<button type="button"
                 class="slack-dest-star ${isFav ? "is-fav" : ""}"
                 aria-label="${isFav ? "Retirer des favoris" : "Ajouter aux favoris"}"
                 data-id="${this._attr(id)}"
                 data-name="${this._attr(label)}"
                 data-action="click->slack-destination#toggleFavorite">
           <i data-lucide="star" style="width:15px;height:15px;"></i>
         </button>`
      : ""
    return `<li class="slack-dest-item" role="option"
                data-id="${this._attr(id)}"
                data-label="${this._attr(label)}"
                data-action="click->slack-destination#onItemClick">
              <span class="slack-dest-item-label">${this._esc(label)}</span>
              ${star}
            </li>`
  }

  // ── Navigation clavier ────────────────────────────────────────────────────────
  keydown(event) {
    const items = this._optionItems()
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        if (this.listTarget.style.display === "none") return this.open()
        this._highlight(Math.min(this.activeIndex + 1, items.length - 1))
        break
      case "ArrowUp":
        event.preventDefault()
        this._highlight(Math.max(this.activeIndex - 1, 0))
        break
      case "Enter": {
        const el = items[this.activeIndex]
        if (el) { event.preventDefault(); this.select(el.dataset.id, el.dataset.label) }
        break
      }
      case "Escape":
        this.close()
        break
    }
  }

  _optionItems() {
    return Array.from(this.listTarget.querySelectorAll('.slack-dest-item[role="option"]'))
  }

  _highlight(index) {
    const items = this._optionItems()
    items.forEach((el) => { el.classList.remove("is-active"); el.setAttribute("aria-selected", "false") })
    this.activeIndex = index
    const el = items[index]
    if (!el) return
    el.classList.add("is-active")
    el.setAttribute("aria-selected", "true")
    el.scrollIntoView({ block: "nearest" })
  }

  // ── Échappement anti-XSS (labels/ids viennent de l'API Slack) ───────────────────
  _esc(str) {
    const div = document.createElement("div")
    div.textContent = String(str ?? "")
    return div.innerHTML
  }

  _attr(str) {
    return String(str ?? "").replace(/&/g, "&amp;").replace(/"/g, "&quot;")
  }
}
