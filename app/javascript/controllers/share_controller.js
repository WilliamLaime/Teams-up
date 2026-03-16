// Contrôleur Stimulus pour la modale de partage
// Gère uniquement le copier-coller du lien dans le presse-papier
// Les autres options (WhatsApp, Messenger, SMS) sont de simples liens <a>
import { Controller } from "@hotwired/stimulus"

// Durée en ms avant que le bouton "Copié !" repasse en "Copier le lien"
const COPY_FEEDBACK_DURATION = 2000

export default class extends Controller {
  // Targets = éléments HTML qu'on va manipuler
  static targets = ["copyIcon", "checkIcon", "copyLabel"]

  // Values = données passées depuis le HTML via data-share-url-value
  static values = { url: String }

  // Méthode appelée quand l'utilisateur clique sur "Copier le lien"
  copy() {
    // navigator.clipboard.writeText retourne une Promise
    navigator.clipboard.writeText(this.urlValue).then(() => {
      // Succès : on affiche le feedback visuel
      this._showCopiedFeedback()
    }).catch(() => {
      // Fallback pour navigateurs sans support clipboard API (rare)
      this._fallbackCopy()
    })
  }

  // Affiche temporairement l'état "Copié !" à la place de l'icône lien
  _showCopiedFeedback() {
    // Cache l'icône "lien", montre l'icône "check"
    this.copyIconTarget.classList.add("d-none")
    this.checkIconTarget.classList.remove("d-none")

    // Change le libellé
    this.copyLabelTarget.textContent = "Copié !"

    // Remet l'état initial après COPY_FEEDBACK_DURATION ms
    setTimeout(() => {
      this.copyIconTarget.classList.remove("d-none")
      this.checkIconTarget.classList.add("d-none")
      this.copyLabelTarget.textContent = "Copier le lien"
    }, COPY_FEEDBACK_DURATION)
  }

  // Méthode de secours si navigator.clipboard n'est pas disponible
  // (ex: HTTP non sécurisé en développement)
  _fallbackCopy() {
    // Crée un input temporaire, copie via execCommand (déprécié mais compatible)
    const input = document.createElement("input")
    input.value = this.urlValue
    document.body.appendChild(input)
    input.select()
    document.execCommand("copy")
    document.body.removeChild(input)

    // Affiche quand même le feedback
    this._showCopiedFeedback()
  }
}
