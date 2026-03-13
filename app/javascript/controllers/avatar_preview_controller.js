import { Controller } from "@hotwired/stimulus"

// Controller Stimulus pour la prévisualisation de la photo de profil avant upload
// Usage dans le HTML : data-controller="avatar-preview"
export default class extends Controller {
  // On déclare les "targets" — les éléments HTML qu'on va manipuler
  // "placeholder" est optionnel (utilisé sur la page d'inscription)
  static targets = ["input", "preview", "image", "placeholder"]

  // Appelé quand l'utilisateur choisit un fichier
  // Lié au champ input via data-action="change->avatar-preview#preview"
  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return

    // Lit le fichier localement pour afficher un aperçu sans upload
    const reader = new FileReader()
    reader.onload = (event) => {
      // Affiche l'image dans la target "image"
      this.imageTarget.src = event.target.result

      // Montre le conteneur de prévisualisation
      this.previewTarget.style.display = "block"

      // Cache le placeholder (icône + texte) si présent dans le DOM
      if (this.hasPlaceholderTarget) {
        this.placeholderTarget.style.display = "none"
      }
    }
    reader.readAsDataURL(file)
  }
}
