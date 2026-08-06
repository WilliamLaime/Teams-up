import { Controller } from "@hotwired/stimulus"

// Stimulus controller : back-link
// Bouton « Retour » qui revient VRAIMENT à la page précédente (cf. _nav_button).
//
// ── Pourquoi ne pas appeler history.back() aveuglément ────────────────────────
// Si l'utilisateur arrive directement sur la page (lien partagé, nouvel onglet,
// notification, résultat Google), l'entrée précédente de l'historique n'est pas
// une page de l'app : history.back() le ferait SORTIR du site. D'où l'URL de
// secours, portée par le href du lien.
//
// ── Pourquoi un compteur et pas document.referrer ────────────────────────────
// Sous Turbo Drive, les navigations se font en pushState : document.referrer
// garde la valeur du chargement initial du document et ne dit donc rien du
// chemin réellement parcouru. history.length, de son côté, compte aussi les
// entrées antérieures à l'arrivée sur le site. On compte donc nous-mêmes les
// pages vues dans cet onglet (incrémenté sur turbo:load, cf. application.js) :
// au-delà de 1, l'entrée précédente est forcément une page de l'app.
export default class extends Controller {
  static values = { fallback: String }

  static VISIT_COUNT_KEY = "teamsup:visit-count"

  back(event) {
    if (!this.canGoBack) return // on laisse le href faire son travail

    event.preventDefault()
    history.back()
  }

  get canGoBack() {
    try {
      return Number(sessionStorage.getItem(this.constructor.VISIT_COUNT_KEY) || 0) > 1
    } catch {
      // sessionStorage indisponible (navigation privée verrouillée, iframe
      // cloisonnée) : on retombe sur l'URL de secours, jamais sur une sortie
      // du site.
      return false
    }
  }
}
