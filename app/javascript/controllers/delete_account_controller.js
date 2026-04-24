// ── Delete Account Modal Controller ──────────────────────────────────────────
// Gère la validation et l'activation du bouton de suppression dans la modal
// de confirmation de suppression de compte (RGPD, art. 17).
//
// Cas 1 : User OAuth (Google) → checkbox + opacity du bouton
// Cas 2 : User classique → validation du mot de passe en temps réel

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "submitBtn", "passwordInput"]

  // ── Initialisation du controller ──────────────────────────────────────────
  connect() {
    // Gère la disposition de l'instance Bootstrap Modal quand Turbo rend la page
    // IMPORTANT (CLAUDE.md) : Bootstrap stocke `_isAppended = true` après avoir
    // inséré le backdrop dans le body. Si Turbo remet le body, le flag reste
    // → le backdrop n'est plus inséré aux navigations futures.
    // Solution : dispose() l'instance avant la navigation.
    this.handleTurboRender = () => {
      const modalElement = this.element
      const modalInstance = window.bootstrap?.Modal.getInstance(modalElement)
      if (modalInstance) {
        modalInstance.dispose()
      }
    }

    document.addEventListener("turbo:before-render", this.handleTurboRender)
  }

  // ── Nettoyage du controller ─────────────────────────────────────────────
  disconnect() {
    document.removeEventListener("turbo:before-render", this.handleTurboRender)
  }

  // ── Active/désactive le bouton de suppression selon l'état de la checkbox ───
  // (OAuth only — user doit cocher la confirmation avant de pouvoir soumettre)
  toggleSubmit() {
    if (!this.hasCheckboxTarget) return

    const isChecked = this.checkboxTarget.checked
    const opacity = isChecked ? 1 : 0.5
    const disabled = !isChecked

    this.submitBtnTarget.disabled = disabled
    this.submitBtnTarget.style.opacity = opacity
    this.submitBtnTarget.style.cursor = disabled ? "not-allowed" : "pointer"
  }

  // ── Validation du mot de passe en temps réel ──────────────────────────────
  // (User classique — active le bouton si le champ n'est pas vide)
  validatePassword() {
    if (!this.hasPasswordInputTarget) return

    const hasPassword = this.passwordInputTarget.value.trim().length > 0
    const opacity = hasPassword ? 1 : 0.5
    const disabled = !hasPassword

    this.submitBtnTarget.disabled = disabled
    this.submitBtnTarget.style.opacity = opacity
    this.submitBtnTarget.style.cursor = disabled ? "not-allowed" : "pointer"
  }
}
