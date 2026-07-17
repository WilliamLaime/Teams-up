import { Controller } from "@hotwired/stimulus"

// ── Contrôleur Stimulus : partage Slack dans le formulaire de création ──────
// 1. Affiche le bloc de sélection uniquement quand la case "Partager sur Slack"
//    est cochée.
// 2. Sélection en deux temps : quand on change d'espace Slack (workspace), on
//    repeuple le <select> de destination (channels + messages directs) à partir
//    des données embarquées.
//
// Voir shared/_slack_share_field.html.erb pour le câblage des data-attributes.
export default class extends Controller {
  static targets = ["checkbox", "wrapper", "workspace", "channel"]
  // data = [{ id, name, destinations: { "Channels": [[nom,id]...], "Messages directs": [...] } }]
  static values = { data: Array }

  connect() {
    this.populateChannels()
    this.toggle()
  }

  // Affiche/masque le bloc de destination selon l'état de la case.
  // En mode standalone (modale de partage), il n'y a pas de case → le bloc reste
  // toujours visible, on ne touche donc pas à son affichage.
  toggle() {
    if (!this.hasWrapperTarget || !this.hasCheckboxTarget) return
    this.wrapperTarget.style.display = this.checkboxTarget.checked ? "block" : "none"
  }

  // Rechargement des destinations quand l'espace Slack change.
  workspaceChanged() {
    this.populateChannels()
  }

  // Reconstruit les <optgroup>/<option> du select de destination pour le workspace choisi.
  populateChannels() {
    if (!this.hasChannelTarget || !this.hasWorkspaceTarget) return

    const workspaceId = this.currentWorkspaceId()
    const workspace = this.dataValue.find((w) => String(w.id) === String(workspaceId))

    // On réinitialise en gardant l'option "défaut" (valeur vide).
    this.channelTarget.innerHTML = ""
    this.channelTarget.appendChild(this.buildOption("", "Ma destination par défaut"))

    if (!workspace) return

    Object.entries(workspace.destinations || {}).forEach(([groupLabel, pairs]) => {
      if (!pairs || pairs.length === 0) return
      const group = document.createElement("optgroup")
      group.label = groupLabel
      pairs.forEach(([label, id]) => group.appendChild(this.buildOption(id, label)))
      this.channelTarget.appendChild(group)
    })
  }

  currentWorkspaceId() {
    // Le workspace target est soit un <select>, soit un <input hidden> (workspace unique).
    return this.workspaceTarget.value
  }

  buildOption(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    return option
  }
}
