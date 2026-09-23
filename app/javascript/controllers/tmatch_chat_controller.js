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
  open(event) {
    // Éteint la pastille non-lu de la bulle cliquée, sans attendre le serveur.
    // Celui-ci marque bien le fil comme lu dès l'ouverture (cf.
    // TournamentMatchConversationsController#show) : le DOM et la base restent
    // d'accord, que l'utilisateur réponde ensuite ou non.
    //
    // Sans ce nettoyage la pastille survivait à la lecture ET à la réponse : elle
    // n'est rendue qu'au chargement du tableau, et la réponse Turbo Stream d'un
    // envoi ne met à jour que le formulaire du fil, jamais la carte.
    // Même principe que sticky_chat_controller pour la sidebar.
    this.clearUnread(event && event.currentTarget)

    if (typeof bootstrap === "undefined") return

    bootstrap.Modal.getOrCreateInstance(this.modalTarget).show()
  }

  // ── Repasse une bulle à l'état « lu » ──────────────────────────────────────
  // Les libellés accessibles suivent la couleur : sans cela un lecteur d'écran
  // continuerait d'annoncer « nouveau message » sur une bulle éteinte.
  clearUnread(link) {
    if (!link) return

    link.classList.remove("tmatch-card__chat-btn--unread")
    link.querySelectorAll(".tmatch-card__chat-dot").forEach(dot => dot.remove())
    link.title = "Organiser le match"
    link.setAttribute("aria-label", "Discuter pour organiser le match")
  }
}
