// level_filter_controller.js
// Gère le dropdown personnalisé pour le filtre de niveau (multi-sélection).
// Écoute l'event "sport:changed" (dispatché par sport_filter_controller)
// pour reconstruire les checkboxes selon le/les sport(s) actifs :
//   - 0 sport  → liste générique (Tout niveau, Débutant, Intermédiaire, Confirmé, Expert)
//   - 1 sport  → grille complète du sport
//   - N sports → union dédupliquée dans l'ordre des sports sélectionnés
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // "list" = div conteneur des checkboxes (son innerHTML est reconstruit dynamiquement)
  static targets = ["dropdown", "label", "checkbox", "list"]

  connect() {
    // Ferme le dropdown si on clique en dehors
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)
    // Ferme ce dropdown si un autre s'ouvre (custom event "filter:opened")
    this.handleOtherOpened = this.handleOtherOpened.bind(this)
    document.addEventListener("filter:opened", this.handleOtherOpened)
    // Écoute les changements de sport pour mettre à jour les niveaux disponibles
    this.handleSportChanged = this.handleSportChanged.bind(this)
    document.addEventListener("sport:changed", this.handleSportChanged)
    // Met à jour le label si des niveaux sont déjà dans l'URL
    this.updateLabel()
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
    document.removeEventListener("filter:opened", this.handleOtherOpened)
    document.removeEventListener("sport:changed", this.handleSportChanged)
  }

  // Ouvre ou ferme le dropdown au clic sur le trigger
  toggle(event) {
    event.stopPropagation()

    const dropdown = this.dropdownTarget
    // On contrôle directement le style inline — pas de conflit CSS possible
    if (dropdown.style.display === "none") {
      // Prévient les autres dropdowns de se fermer
      document.dispatchEvent(new CustomEvent("filter:opened", { detail: { source: this } }))
      dropdown.style.display = "flex"
      dropdown.style.flexDirection = "column"
      // Réinitialise le flag de modification à l'ouverture
      this.dirty = false
    } else {
      // Ferme et soumet si une checkbox a changé
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme ce dropdown si un autre filtre vient de s'ouvrir
  handleOtherOpened(event) {
    if (event.detail.source !== this) {
      // Soumet si une checkbox a changé avant de fermer
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown si on clique ailleurs sur la page
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      // Soumet si une checkbox a changé avant de fermer
      this.closeAndSubmitIfDirty()
    }
  }

  // Ferme le dropdown et soumet le formulaire si quelque chose a changé
  closeAndSubmitIfDirty() {
    this.dropdownTarget.style.display = "none"
    if (this.dirty) {
      this.dirty = false
      this.element.closest("form").requestSubmit()
    }
  }

  // Appelé à chaque checkbox cochée/décochée — met à jour le label et marque comme modifié
  change() {
    this.updateLabel()
    // Marque que l'utilisateur a changé une sélection
    this.dirty = true
  }

  // Soumet le formulaire et ferme le dropdown — appelé par le bouton "Appliquer"
  apply(event) {
    event.stopPropagation()
    this.dropdownTarget.style.display = "none"
    this.element.closest("form").requestSubmit()
  }

  // Met à jour le texte du trigger selon les cases cochées
  updateLabel() {
    const checked = this.checkboxTargets.filter(cb => cb.checked)

    if (checked.length === 0) {
      this.labelTarget.textContent = "Niveau"
    } else if (checked.length === 1) {
      this.labelTarget.textContent = checked[0].value
    } else {
      this.labelTarget.textContent = `${checked.length} niveaux`
    }
  }

  // ── Appelé quand le sport change (event "sport:changed") ──────────────────
  handleSportChanged(event) {
    this._rebuildLevels(event.detail.sportIds)
  }

  // Reconstruit les checkboxes selon le sport sélectionné.
  // Clé "0" = fallback (sport actif du contexte utilisateur, calculé côté serveur).
  // Les niveaux déjà cochés sont conservés si leur label existe dans la nouvelle liste.
  _rebuildLevels(sportIds) {
    // Récupère la map sport_id → [{label, css}] depuis le data attribute
    const map = JSON.parse(this.element.dataset.sportsLevels || "{}")

    // 1 sport sélectionné → sa grille complète ; fallback sur clé "0" (sport actif du contexte)
    const levels = (sportIds.length > 0 ? map[String(sportIds[0])] : null) || map["0"] || []

    // Conserve les labels actuellement cochés pour les re-cocher si présents dans la nouvelle liste
    const selected = new Set(this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.value))

    // Reconstruit le HTML du conteneur — Stimulus re-détecte les targets "checkbox" automatiquement
    this.listTarget.innerHTML = levels.map(lvl => `
      <label style="display:flex; flex-direction:row; align-items:center; gap:0.6rem; padding:0.35rem 0.5rem; border-radius:6px; cursor:pointer; margin:0; width:100%;">
        <input type="checkbox"
               name="levels[]"
               value="${lvl.label}"
               data-level-filter-target="checkbox"
               data-action="change->level-filter#change"
               style="width:15px; height:15px; margin:0; padding:0; flex-shrink:0; cursor:pointer; accent-color:#1EDD88;"
               ${selected.has(lvl.label) ? "checked" : ""}>
        <span class="match-badge-level ${lvl.css}"
              style="font-size:0.72rem; padding:0.2rem 0.6rem; line-height:1; margin:0;">
          ${lvl.label}
        </span>
      </label>
    `).join("")

    this.updateLabel()
  }
}
