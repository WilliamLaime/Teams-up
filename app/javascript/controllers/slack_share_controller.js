import { Controller } from "@hotwired/stimulus"

// ── Contrôleur Stimulus : case « Partager sur Slack » du formulaire de création ──
// Affiche/masque le bloc de sélection (workspace + destination) selon l'état de la case.
// La logique du sélecteur de destination lui-même vit dans slack_destination_controller.
//
// En mode standalone (modale de partage), il n'y a pas de case → le bloc reste toujours
// visible, on ne touche donc pas à son affichage.
export default class extends Controller {
  static targets = ["checkbox", "wrapper"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasWrapperTarget || !this.hasCheckboxTarget) return
    this.wrapperTarget.style.display = this.checkboxTarget.checked ? "block" : "none"
  }
}
