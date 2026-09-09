import { Controller } from "@hotwired/stimulus"

// Modale de lancement du tournoi (cf. _pool_draw_modal.html.erb).
export default class extends Controller {
  static targets = ["select"]

  // Le <select> désactivé n'est pas soumis : c'est LUI qui porte le mode
  // automatique, aucun paramètre virtuel à filtrer côté serveur.
  choose(event) {
    // Le bouton d'habillage suit tout seul : custom-select observe l'attribut
    // `disabled` du <select> natif qu'il double.
    this.selectTarget.disabled = event.target.value !== "custom"
  }

  // La réponse Turbo Stream remplace le board SOUS la modale ouverte : sans ça,
  // l'animation de tirage se jouerait derrière le backdrop. Même pattern que
  // tournament-score#close.
  close(event) {
    if (event?.detail?.success === false) return

    // `closest` et non un target : la div .modal est le PARENT du formulaire, donc
    // hors de la portée de ce contrôleur.
    const modal = this.element.closest(".modal")
    if (modal) bootstrap.Modal.getOrCreateInstance(modal).hide()
  }
}
