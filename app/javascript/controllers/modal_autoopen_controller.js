// Stimulus controller : modal-autoopen
// Ouvre une modale dès l'arrivée sur la page — utilisé par les liens des mails
// et des notifications de chat (cf. ChatEmailDigest#chat_path) pour atterrir
// directement DANS la discussion : ?open_chat=1 sur un match ou une équipe,
// ?tmatch_chat=:id sur un tournoi.
//
// La vue ne rend ce contrôleur que si le paramètre est présent ET que
// l'utilisateur a accès au chat : ici, on se contente d'ouvrir.
//
// Valeurs :
//   modal    — id de la modale à ouvrir (obligatoire)
//   param    — paramètre d'URL à retirer une fois la modale ouverte
//   frameId  — id d'un turbo-frame à charger avant l'ouverture (optionnel,
//              ex. le chat de tournoi dont la modale est partagée et vide)
//   frameSrc — URL à charger dans ce frame

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modal: String, param: String, frameId: String, frameSrc: String }

  connect() {
    // ── Fix Bootstrap backdrop + Turbo Drive (cf. tmatch_chat_controller) ──
    // Sans dispose() avant le remplacement du <body>, Bootstrap garde
    // _isAppended = true et les ouvertures suivantes se font sans voile.
    this._handleTurboBeforeRender = () => {
      const modal = document.getElementById(this.modalValue)
      if (!modal || typeof bootstrap === "undefined") return
      const instance = bootstrap.Modal.getInstance(modal)
      if (instance) instance.dispose()
    }
    document.addEventListener("turbo:before-render", this._handleTurboBeforeRender)

    this.open()
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this._handleTurboBeforeRender)
  }

  open() {
    // Déjà ouverte une fois : la page vient d'être restaurée depuis le cache
    // Turbo (retour arrière), qui a mémorisé ce marqueur avec le DOM.
    if (this.element.dataset.opened) return

    const modal = document.getElementById(this.modalValue)
    if (!modal || typeof bootstrap === "undefined") return
    this.element.dataset.opened = "true"

    if (this.hasFrameIdValue && this.hasFrameSrcValue) {
      const frame = document.getElementById(this.frameIdValue)
      if (frame) frame.setAttribute("src", this.frameSrcValue)
    }

    bootstrap.Modal.getOrCreateInstance(modal).show()
    this.removeParamFromUrl()
  }

  // Retire le paramètre de l'URL : sans cela, un rechargement de la page
  // rouvrirait la modale.
  removeParamFromUrl() {
    if (!this.hasParamValue) return

    const url = new URL(window.location.href)
    if (!url.searchParams.has(this.paramValue)) return

    url.searchParams.delete(this.paramValue)
    window.history.replaceState(window.history.state, "", url.toString())
  }
}
