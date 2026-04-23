// Stimulus controller : theme_toggle_controller.js
//
// Rôle : gérer le bouton de bascule entre le mode clair et le mode sombre.
//
// Comportement :
//   - Au montage (connect), il lit le thème actuel depuis l'attribut data-theme de <html>
//     et met à jour l'icône du bouton (soleil ↔ lune).
//   - Quand l'utilisateur clique le bouton toggle (action "toggle") :
//     1. Il inverse le thème sur <html> immédiatement (pas d'attente réseau → UX fluide)
//     2. Il met à jour l'icône du bouton
//     3. Si l'user est connecté, il envoie un PATCH /profil/update_theme en AJAX
//        pour persister la préférence en base de données.
//
// Valeurs Stimulus (déclarées via data-theme-toggle-*-value dans application.html.erb) :
//   - url    : l'URL du endpoint PATCH update_theme (vide si non connecté)
//   - authenticated : "true" si l'user est connecté (persiste en BDD), sinon local seulement

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Déclaration des valeurs transmises depuis le HTML via data-theme-toggle-*-value
  // url         : endpoint Rails PATCH update_theme
  // authenticated : indique si l'user est connecté (pour décider de l'appel AJAX)
  static values = {
    url:           String,
    authenticated: Boolean
  }

  // Déclaration des targets : éléments du DOM que ce controller gère
  // "button" : le bouton toggle dans la navbar (on peut en avoir plusieurs si besoin)
  static targets = ["button"]

  // connect() est appelé automatiquement par Stimulus quand le controller
  // est attaché au DOM (à chaque navigation Turbo incluse)
  connect() {
    // Lit le thème courant depuis l'attribut data-theme de <html>
    // (posé côté serveur dans application.html.erb pour éviter le flash)
    const currentTheme = document.documentElement.getAttribute("data-theme") || "dark"

    // Met l'icône du bouton en cohérence avec le thème au chargement
    this.updateButtonIcon(currentTheme)
  }

  // Action appelée via data-action="click->theme-toggle#toggle" sur le bouton navbar
  toggle() {
    // Lit le thème actuel depuis <html>
    const current = document.documentElement.getAttribute("data-theme") || "dark"
    // Calcule le nouveau thème
    const next = current === "dark" ? "light" : "dark"

    // 1. Applique immédiatement dans le DOM — pas d'attente réseau
    this.applyTheme(next)

    // 2. Si l'utilisateur est connecté, on persiste en base via AJAX
    if (this.authenticatedValue && this.urlValue) {
      this.persistTheme()
    }
  }

  // Applique le thème sur <html> et met à jour l'icône du bouton
  applyTheme(theme) {
    // Met à jour l'attribut data-theme sur <html> — tout le CSS réagit à cet attribut
    document.documentElement.setAttribute("data-theme", theme)

    // Met à jour l'icône du bouton (soleil en mode sombre, lune en mode clair)
    this.updateButtonIcon(theme)
  }

  // Met à jour l'attribut data-lucide de l'icône dans le bouton
  // et ré-initialise Lucide pour que le SVG soit bien rendu
  updateButtonIcon(theme) {
    // Cherche l'icône dans chaque bouton target déclaré
    this.buttonTargets.forEach(button => {
      const icon = button.querySelector("[data-lucide]")
      if (!icon) return

      // Mode sombre → on affiche le soleil (action = passer en clair)
      // Mode clair  → on affiche la lune (action = passer en sombre)
      icon.setAttribute("data-lucide", theme === "dark" ? "sun" : "moon")

      // Met à jour le tooltip (title) pour l'accessibilité
      button.setAttribute("title", theme === "dark" ? "Passer en mode clair" : "Passer en mode sombre")
      button.setAttribute("aria-label", theme === "dark" ? "Passer en mode clair" : "Passer en mode sombre")

      // Ré-initialise Lucide pour que le SVG corresponde au nouvel attribut data-lucide
      // window.lucide est défini dans application.html.erb (chargé en defer)
      if (window.lucide) lucide.createIcons()
    })
  }

  // Envoie une requête PATCH au serveur pour sauvegarder la préférence de thème
  // Utilise fetch() avec le token CSRF pour sécuriser l'appel (même pas de JS externe)
  persistTheme() {
    // Récupère le token CSRF depuis la balise <meta name="csrf-token"> du layout
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    // Envoi de la requête PATCH — le serveur inverse la valeur en BDD
    fetch(this.urlValue, {
      method:  "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept":       "application/json",
        "Content-Type": "application/json"
      }
    })
    .then(response => {
      if (!response.ok) {
        // Si l'appel échoue, on logge discrètement — le thème visuel est déjà basculé
        console.warn("[theme-toggle] Erreur lors de la persistance du thème :", response.status)
      }
    })
    .catch(error => {
      // Erreur réseau (offline, etc.) — on n'annule pas le changement visuel
      console.warn("[theme-toggle] Erreur réseau :", error)
    })
  }
}
