import { Controller } from "@hotwired/stimulus"

// Onglets de la page détail d'un tournoi (Vue d'ensemble / Matchs / Participants /
// Classement). La bascule est purement côté client : on masque/affiche les
// panneaux via une classe CSS — AUCUN panneau n'est retiré du DOM.
//
// Point crucial : le board (#tournament_board) est la cible des Turbo Streams de
// saisie de score. Comme on ne fait que le masquer (display:none) et jamais le
// détacher, il reste toujours dans le DOM et la saisie de score continue de
// fonctionner quel que soit l'onglet actif.
export default class extends Controller {
  static targets = ["tab", "panel"]

  // Active l'onglet cliqué. Le nom du panneau est passé en paramètre d'action
  // (data-tournament-tabs-panel-param) → event.params.panel.
  select(event) {
    this.#activate(event.params.panel)
  }

  #activate(name) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tournamentTabsPanelParam === name
      tab.classList.toggle("is-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.panel === name
      panel.classList.toggle("is-active", active)
      panel.toggleAttribute("hidden", !active)
    })
  }
}
