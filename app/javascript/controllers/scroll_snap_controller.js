// Controller Stimulus — scroll-snap pleine page avec animation directionnelle
// Le texte entre par le bas et sort par le haut, fond fixe tout au long

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Active le scroll-snap sur <html> (et donc le fond fixe sur .about2-page)
    document.documentElement.classList.add("page-scroll-snap")

    // IntersectionObserver avec root: null = observe par rapport au viewport
    // C'est correct ici car html est le scroll container et les sections
    // occupent chacune 100vh dans le flux du document
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach(entry => {
          // querySelectorAll pour gérer les sections avec plusieurs blocs intérieurs
          // (ex: la section split avec 2 colonnes animées séparément)
          const inners = entry.target.querySelectorAll(".a2-section-inner")
          if (!inners.length) return

          if (entry.isIntersecting) {
            // Section visible → tous les blocs glissent vers leur position
            inners.forEach(inner => {
              inner.classList.add("is-visible")
              inner.classList.remove("is-above")
            })

          } else {
            inners.forEach(inner => {
              inner.classList.remove("is-visible")

              if (entry.boundingClientRect.top < 0) {
                // Section au-dessus du viewport (déjà scrollée) → sort vers le haut
                inner.classList.add("is-above")
              } else {
                // Section en dessous (pas encore atteinte) → reste en bas
                inner.classList.remove("is-above")
              }
            })
          }
        })
      },
      {
        // Déclenche dès que 15% de la section entre dans le viewport
        threshold: 0.15
      }
    )

    // Observe toutes les sections de la page
    this.element.querySelectorAll(".a2-section").forEach(section => {
      this.observer.observe(section)
    })
  }

  disconnect() {
    // Nettoyage au départ de la page (navigation Turbo)
    document.documentElement.classList.remove("page-scroll-snap")
    if (this.observer) {
      this.observer.disconnect()
    }
  }
}
