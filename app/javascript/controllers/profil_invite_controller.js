// profil_invite_controller.js
// Gère le formulaire "Inviter dans mon équipe" sur la page profil.
// Met à jour l'action du formulaire selon l'équipe sélectionnée (radio ou hidden).
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "select"]
  // URL de base : /teams/TEAM_ID/team_invitations (TEAM_ID est remplacé dynamiquement)
  static values  = { baseUrl: String }

  connect() {
    this._updateAction()
  }

  // Appelé quand un radio change (plusieurs équipes)
  update() {
    this._updateAction()
  }

  // Appelé quand on clique sur un label (met le focus sur le radio correspondant)
  selectTeam(event) {
    const teamId = event.currentTarget.dataset.teamId
    // Coche le radio correspondant à ce label
    const radio = event.currentTarget.querySelector("input[type='radio']")
    if (radio) {
      radio.checked = true
      this.formTarget.action = this.baseUrlValue.replace("TEAM_ID", teamId)
    }
  }

  _updateAction() {
    // Récupère la valeur du premier select/radio coché ou hidden
    const checked = this.selectTargets.find(el =>
      el.type === "radio" ? el.checked : true
    )
    if (checked) {
      this.formTarget.action = this.baseUrlValue.replace("TEAM_ID", checked.value)
    }
  }
}
