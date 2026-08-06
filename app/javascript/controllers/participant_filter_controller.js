import { Controller } from "@hotwired/stimulus"

// Stimulus controller : participant-filter
// Filtre la grille des participants d'un tournoi à la frappe (cf. _participants).
//
// Purement client : la liste est déjà entièrement rendue par le serveur, donc
// masquer/afficher suffit — un aller-retour Turbo ferait clignoter la page et
// perdrait l'état du board (phase sélectionnée, journées affichées).
//
// La comparaison est insensible à la casse ET aux accents : chercher « lea »
// doit trouver « Léa Martin », sinon la recherche est inutilisable sur des noms
// français. On compare sur data-name (le nom seul, calculé côté serveur) et non
// sur le texte de la carte, qui contient aussi « Qualifié » et « Forfait ».
export default class extends Controller {
  static targets = ["input", "card", "count", "empty"]

  filter() {
    const query = this.normalize(this.inputTarget.value)
    let visible = 0

    this.cardTargets.forEach((card) => {
      const match = query === "" || this.normalize(card.dataset.name).includes(query)
      card.hidden = !match
      if (match) visible += 1
    })

    // « 3 / 16 » pendant une recherche, l'effectif seul sinon : le total doit
    // rester lisible, c'est l'information de référence de l'onglet.
    if (this.hasCountTarget) {
      this.countTarget.textContent = query === "" ? this.total : `${visible} / ${this.total}`
    }
    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible > 0
  }

  get total() {
    return this.cardTargets.length
  }

  // Minuscules sans diacritiques. On cible la plage Unicode des marques
  // combinantes (U+0300–U+036F) plutôt que \p{Diacritic}, non reconnu par les
  // Safari plus anciens.
  normalize(value) {
    return (value || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim()
  }
}
