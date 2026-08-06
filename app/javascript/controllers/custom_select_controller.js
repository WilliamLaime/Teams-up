import { Controller } from "@hotwired/stimulus"

// Habillage d'un <select> natif — même vocabulaire visuel que le reste de l'app
// (pilule + accent vert, cf. .journee-picker). Un <select> ouvert est dessiné par
// l'OS : fond gris système, police système, aucune prise CSS. La seule façon de
// l'habiller est de le doubler d'un menu en HTML.
//
// Le <select> RESTE dans le DOM et reste la source de vérité : c'est lui qui est
// soumis avec le formulaire, lui qui porte les data-attributes lus ailleurs, et
// c'est sur lui qu'on redéclenche `change` — les contrôleurs déjà branchés
// dessus (ex. match-form#applyTournamentMatch) continuent de fonctionner sans
// rien savoir de cet habillage. Il est juste masqué visuellement.
//
// Les options peuvent être remplacées à chaud (match-form#updateTournament
// réécrit tout le innerHTML quand on change de tournoi) : un MutationObserver
// reconstruit alors le menu. Sans lui, l'habillage afficherait les options du
// tournoi précédent.
export default class extends Controller {
  static targets = ["native"]

  connect() {
    this.buildShell()
    this.render()

    this.boundClose = this.closeOnOutsideClick.bind(this)
    this.observer = new MutationObserver(() => this.render())
    this.observer.observe(this.nativeTarget, { childList: true, subtree: true })
    // Une valeur changée par ailleurs (préremplissage serveur, autre contrôleur)
    // doit se voir dans le libellé.
    this.nativeTarget.addEventListener("change", () => this.renderLabel())
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("click", this.boundClose)
  }

  // ── Construction ────────────────────────────────────────────────────────────

  buildShell() {
    this.toggle_ = document.createElement("button")
    this.toggle_.type = "button" // sans ça, un <button> dans un <form> le soumet
    this.toggle_.className = "custom-select__toggle"
    this.toggle_.setAttribute("aria-haspopup", "listbox")
    this.toggle_.setAttribute("aria-expanded", "false")
    this.toggle_.innerHTML =
      '<span class="custom-select__value"></span>' +
      '<i data-lucide="chevron-down" class="custom-select__chevron" aria-hidden="true"></i>'
    this.toggle_.addEventListener("click", () => this.toggleMenu())

    this.menu = document.createElement("ul")
    this.menu.className = "custom-select__menu"
    this.menu.setAttribute("role", "listbox")
    this.menu.hidden = true

    this.element.append(this.toggle_, this.menu)
  }

  render() {
    this.menu.innerHTML = ""
    Array.from(this.nativeTarget.options).forEach((option) => {
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "custom-select__option"
      button.setAttribute("role", "option")
      button.textContent = option.textContent
      button.dataset.value = option.value
      button.addEventListener("click", () => this.pick(option.value))
      item.append(button)
      this.menu.append(item)
    })
    this.renderLabel()
    // Les icônes Lucide sont injectées après coup : ce menu naît en JS, il n'est
    // donc pas couvert par les ré-initialisations de application.js.
    window.lucide?.createIcons({ nameAttr: "data-lucide" })
  }

  renderLabel() {
    const selected = this.nativeTarget.selectedOptions[0]
    const value = selected ? selected.textContent : ""
    this.toggle_.querySelector(".custom-select__value").textContent = value
    this.toggle_.classList.toggle("is-placeholder", !this.nativeTarget.value)

    this.menu.querySelectorAll(".custom-select__option").forEach((button) => {
      const active = button.dataset.value === this.nativeTarget.value
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-selected", active ? "true" : "false")
    })
  }

  // ── Interaction ─────────────────────────────────────────────────────────────

  pick(value) {
    this.nativeTarget.value = value
    // `bubbles: true` : les actions Stimulus écoutent au niveau du document.
    this.nativeTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.renderLabel()
    this.close()
  }

  toggleMenu() {
    this.menu.hidden ? this.open() : this.close()
  }

  open() {
    this.menu.hidden = false
    this.toggle_.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.boundClose)
    this.menu.querySelector(".is-active")?.scrollIntoView({ block: "nearest" })
  }

  close() {
    this.menu.hidden = true
    this.toggle_.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.boundClose)
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  // Échap ferme sans choisir — attendu de tout menu.
  keydown(event) {
    if (event.key === "Escape" && !this.menu.hidden) {
      event.preventDefault()
      this.close()
      this.toggle_.focus()
    }
  }
}
