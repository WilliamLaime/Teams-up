// Controller Stimulus : afficher/masquer le mot de passe avec l'icône oeil
// Usage HTML : data-controller="password-toggle"
// Sur l'input  : data-password-toggle-target="input"
// Sur le bouton: data-action="click->password-toggle#toggle"
//                data-password-toggle-target="button"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Cibles : l'input mot de passe + le bouton avec l'oeil
  static targets = ["input", "button"]

  // Appelée au clic sur l'icône oeil
  toggle(event) {
    // Empêche la soumission du formulaire au clic
    event.preventDefault()

    // Bascule entre "password" (masqué) et "text" (visible)
    const isPassword = this.inputTarget.type === "password"
    this.inputTarget.type = isPassword ? "text" : "password"

    // Met à jour l'icône selon l'état
    // On remplace l'attribut data-lucide puis on re-render l'icône
    const icon = this.buttonTarget.querySelector("i[data-lucide]")
    if (icon) {
      icon.setAttribute("data-lucide", isPassword ? "eye-off" : "eye")
      // lucide.createIcons() re-render toutes les icônes de la page
      if (window.lucide) window.lucide.createIcons()
    }
  }
}
