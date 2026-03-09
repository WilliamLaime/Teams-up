import { Controller } from "@hotwired/stimulus"

// Controller Stimulus pour la prévisualisation de la photo de profil avant upload
// Usage dans le HTML : data-controller="avatar-preview"
export default class extends Controller {
  // On déclare les "targets" — les éléments HTML qu'on va manipuler
  static targets = ["input", "preview", "image"]

  // Appelé quand l'utilisateur choisit un fichier
  // Lié au champ input via data-action="change->avatar-preview#preview"
  preview() {
    const file = this.inputTarget.files[0]
    if (!file) return

    // Lit le fichier localement pour afficher un aperçu sans upload
    const reader = new FileReader()
    reader.onload = (event) => {
      this.imageTarget.src = event.target.result
      this.previewTarget.style.display = "block"
    }
    reader.readAsDataURL(file)
  }
}
