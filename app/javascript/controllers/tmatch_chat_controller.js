// Stimulus controller : tmatch-chat
// Pilote la modale de chat partagée du tableau de tournoi.
//
// Rôle volontairement minimal : le contenu du fil arrive par turbo-frame (la
// bulle d'une carte est un lien qui cible #tmatch-chat-frame), et le fil lui-même
// est piloté par le contrôleur `chat` existant (auto-scroll, envoi à Entrée).
// Il ne reste ici qu'à ouvrir la fenêtre.

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    // ── Fix Bootstrap backdrop + Turbo Drive (cf. tournament_score_controller) ──
    // Bootstrap garde _isAppended = true après la 1re ouverture ; quand Turbo
    // remplace le <body>, le backdrop disparaît du DOM mais Bootstrap le croit
    // encore présent — les ouvertures suivantes se font alors sans voile.
    // dispose() AVANT le remplacement réinitialise le flag.
    this._handleTurboBeforeRender = () => {
      if (typeof bootstrap === "undefined") return
      const instance = bootstrap.Modal.getInstance(this.modalTarget)
      if (instance) instance.dispose()
    }
    document.addEventListener("turbo:before-render", this._handleTurboBeforeRender)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this._handleTurboBeforeRender)
  }

  // Ouvre la modale. Le clic sur la bulle déclenche EN PARALLÈLE le chargement du
  // turbo-frame (data-turbo-frame sur le lien) : la fenêtre s'ouvre tout de suite
  // sur « Chargement… » et se remplit à l'arrivée de la réponse, plutôt que de
  // laisser l'utilisateur sans retour pendant la requête.
  open() {
    if (typeof bootstrap === "undefined") return

    bootstrap.Modal.getOrCreateInstance(this.modalTarget).show()
  }
}
