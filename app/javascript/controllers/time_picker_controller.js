// time_picker_controller.js
// Dropdown custom pour sélectionner l'heure de début du match.
// Même pattern que sport_picker_controller : trigger + dropdown scrollable.
// Affiche 5 heures à la fois (max-height CSS) puis scroll pour voir les autres.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "dropdown", "input"]

  connect() {
    // Ferme le dropdown si on clique en dehors du composant
    this.handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)

    // Ferme ce dropdown si un autre dropdown s'ouvre ailleurs sur la page
    this.handleOtherOpen = (e) => {
      if (e.detail.source !== this.element) {
        this.dropdownTarget.style.display = "none"
      }
    }
    document.addEventListener("dropdown:open", this.handleOtherOpen)

    // Injecte la CSS scrollbar directement dans le <head> — garanti même si
    // Sprockets ne charge pas encore le fichier SCSS compilé en développement.
    // Même style que .notif-list : 4px, vert, track transparent.
    if (!document.getElementById("time-picker-scrollbar-style")) {
      const style = document.createElement("style")
      style.id = "time-picker-scrollbar-style"
      style.textContent = `
        .time-picker-dropdown::-webkit-scrollbar { width: 4px !important; }
        .time-picker-dropdown::-webkit-scrollbar-track { background: transparent !important; }
        .time-picker-dropdown::-webkit-scrollbar-thumb { background: #1EDD88 !important; border-radius: 2px !important; }
      `
      document.head.appendChild(style)
    }

    // Hover JS sur chaque item : contourne le !important des styles inline
    this.element.querySelectorAll("[data-time-picker-item]").forEach(item => {
      item.addEventListener("mouseover", () => {
        if (!item.classList.contains("time-picker-item--active")) {
          item.style.setProperty("background", "rgba(30,221,136,0.12)", "important")
          item.style.color = "#1EDD88"
        }
      })
      item.addEventListener("mouseout", () => {
        if (!item.classList.contains("time-picker-item--active")) {
          item.style.setProperty("background", "transparent", "important")
          item.style.color = "rgba(255,255,255,0.7)"
        }
      })
    })
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
    document.removeEventListener("dropdown:open", this.handleOtherOpen)
  }

  // Ouvre ou ferme le dropdown au clic sur le trigger
  toggle(event) {
    event.stopPropagation()
    const d = this.dropdownTarget
    const isOpening = d.style.display === "none"
    d.style.display = isOpening ? "block" : "none"

    if (isOpening) {
      // Prévient les autres dropdowns qu'ils doivent se fermer
      document.dispatchEvent(new CustomEvent("dropdown:open", { detail: { source: this.element } }))
      const activeItem = d.querySelector(".time-picker-item--active")
      if (activeItem) {
        // Calcul manuel pour centrer dans le conteneur scrollable :
        // scrollTop = position de l'item - (hauteur visible / 2) + (hauteur item / 2)
        d.scrollTop = activeItem.offsetTop - (d.clientHeight / 2) + (activeItem.offsetHeight / 2)
      }
    }
  }

  // Appelé au clic sur une heure dans la liste
  select(event) {
    event.stopPropagation()
    const btn   = event.currentTarget
    const value = btn.dataset.value  // ex: "9"
    const label = btn.dataset.label  // ex: "09h"

    // 1. Met à jour l'input hidden time(4i) — soumis avec le formulaire
    this.inputTarget.value = value

    // 2. Déclenche un event "change" qui remonte jusqu'au div parent
    //    data-action="change->match-form#updateTime" → le récap se met à jour
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    // 3. Affiche la valeur sélectionnée dans le bouton trigger
    this.triggerTarget.textContent = label

    // 4. Marque l'item actif via classes ET styles inline (garantit la couleur verte)
    this.element.querySelectorAll("[data-time-picker-item]").forEach(item => {
      const isActive = item === btn
      item.classList.toggle("time-picker-item--active", isActive)
      // Inline styles : priorité absolue sur Bootstrap et les styles navigateur
      item.style.setProperty("background", isActive ? "rgba(30,221,136,0.12)" : "transparent", "important")
      item.style.color = isActive ? "#1EDD88" : "rgba(255,255,255,0.7)"
      item.style.fontWeight = isActive ? "700" : "500"
    })

    // 5. Ferme le dropdown
    this.dropdownTarget.style.display = "none"
  }

  // Ferme le dropdown si on clique en dehors
  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.style.display = "none"
    }
  }
}
