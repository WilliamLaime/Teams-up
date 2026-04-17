// Stimulus controller : review_modal
// Gère la modal post-match qui apparaît à la connexion pour noter ses coéquipiers
// - Ouvre automatiquement la modal Bootstrap au chargement
// - Affiche un match à la fois (stepper) avec navigation "Match suivant →"
// - Soumet les avis en AJAX (fetch) sans recharger la page
// - Avance automatiquement au step suivant quand un match est entièrement traité
// - Ferme la modal quand tous les matchs sont traités ou sur "Plus tard"

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Initialise le step courant (index du match affiché)
    this.currentStep = 0

    // Met à jour la visibilité du bouton "Match suivant" selon le step courant
    this.updateNextBtn()
  }

  // Soumission AJAX d'un formulaire d'avis
  // Appelé par data-action="submit->review-modal#submitReview" sur chaque <form>
  async submitReview(event) {
    event.preventDefault()  // Empêche la soumission HTML classique

    const form     = event.target
    const playerId = event.params.playerId  // data-review-modal-player-id-param
    const matchId  = event.params.matchId   // data-review-modal-match-id-param
    const cardId   = `review-card-${playerId}-${matchId}`
    const card     = document.getElementById(cardId)

    // Vérifie qu'une note a bien été sélectionnée avant d'envoyer
    const ratingInput = form.querySelector("[data-star-rating-target='input']")
    if (!ratingInput || !ratingInput.value) {
      // Feedback visuel : outline rouge sur les étoiles si aucune note
      const starsContainer = form.querySelector("[data-star-rating-target='stars']")
      if (starsContainer) {
        starsContainer.style.outline = "1px solid rgba(255,100,100,0.5)"
        starsContainer.style.borderRadius = "4px"
        setTimeout(() => { starsContainer.style.outline = "none" }, 2000)
      }
      return
    }

    const submitBtn = form.querySelector("[data-star-rating-target='submit']")
    if (submitBtn) {
      submitBtn.disabled = true
      submitBtn.textContent = "Envoi..."
    }

    try {
      // Envoie le formulaire en AJAX avec le header JSON pour obtenir une réponse JSON
      const response = await fetch(form.action, {
        method:  "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
          "Accept":       "application/json"
        },
        body: new FormData(form)
      })

      const data = await response.json()

      if (response.ok && data.success) {
        // ✅ Succès : remplace la card par un message "Noté ✓"
        card.innerHTML = `
          <div style="display:flex; align-items:center; justify-content:center; gap:0.5rem; padding:0.75rem; color:#1EDD88;">
            <span style="font-size:1rem;">★</span>
            <span style="font-size:0.85rem; font-weight:600;">Avis envoyé !</span>
          </div>
        `
        // Met à jour le compteur de joueurs restants dans l'en-tête
        this.updatePendingCount()
        // Vérifie si le step courant est terminé pour avancer ou fermer
        this.checkIfAllReviewed()
      } else {
        // ❌ Erreur métier (ex: fenêtre 7j dépassée) — affiche le message
        const errorMsg = data.error || "Une erreur est survenue."
        if (submitBtn) submitBtn.disabled = false
        this.showCardError(card, errorMsg)
      }
    } catch (err) {
      // Erreur réseau
      this.showCardError(card, "Erreur de connexion, réessayez.")
      if (submitBtn) {
        submitBtn.disabled = false
        submitBtn.textContent = "Envoyer mon avis"
      }
    }
  }

  // Ferme la modal — appelé par le bouton "Plus tard" et la croix
  dismiss() {
    const modal = bootstrap.Modal.getInstance(this.element)
    if (modal) modal.hide()
  }

  // Sélectionne un candidat pour le vote "homme du match"
  // Appelé par data-action="click->review-modal#selectVoteCandidate" sur chaque bouton-joueur
  selectVoteCandidate(event) {
    const matchId  = event.currentTarget.dataset.matchId
    const playerId = event.currentTarget.dataset.playerId

    // Réinitialise le style de tous les boutons de ce match
    const allBtns = this.element.querySelectorAll(`.vote-candidate-btn[data-match-id="${matchId}"]`)
    allBtns.forEach(btn => {
      btn.style.background  = "var(--theme-hover-bg)"  // Fond inactif selon le thème
      btn.style.borderColor = "var(--theme-border)"    // Bordure selon le thème
      btn.style.color       = "var(--theme-text-muted)" // Texte inactif selon le thème
    })

    // Marque le bouton cliqué comme sélectionné (couleur ambre = homme du match)
    event.currentTarget.style.background  = "rgba(245,158,11,0.15)"
    event.currentTarget.style.borderColor = "rgba(245,158,11,0.45)"
    event.currentTarget.style.color       = "#f59e0b"

    // Active le bouton de vote et stocke l'ID du candidat dans son dataset
    const voteBtn = this.element.querySelector(`[data-action*="submitVote"][data-match-id="${matchId}"]`)
    if (voteBtn) {
      voteBtn.disabled           = false
      voteBtn.style.opacity      = "1"
      voteBtn.dataset.votedForId = playerId
    }
  }

  // Soumet le vote "homme du match" en AJAX
  // Appelé par data-action="click->review-modal#submitVote" sur le bouton de vote
  async submitVote(event) {
    const btn        = event.currentTarget
    const matchId    = btn.dataset.matchId
    const votedForId = btn.dataset.votedForId

    // Sécurité : ne fait rien si aucun candidat n'est sélectionné
    if (!votedForId) return

    btn.disabled    = true
    btn.textContent = "Envoi..."

    try {
      // POST /matches/:match_id/match_votes avec le candidat sélectionné
      const response = await fetch(`/matches/${matchId}/match_votes`, {
        method:  "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
          "Accept":       "application/json",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ match_vote: { voted_for_id: votedForId } })
      })

      const data = await response.json()

      if (response.ok && data.success) {
        // ✅ Succès : remplace la section vote par une confirmation
        const section = document.getElementById(`vote-section-${matchId}`)
        if (section) {
          section.innerHTML = `
            <div style="display:flex; align-items:center; justify-content:center; gap:0.5rem; padding:0.5rem; color:#f59e0b;">
              <span>🏆</span>
              <span style="font-size:0.85rem; font-weight:600;">Vote enregistré !</span>
            </div>
          `
        }
        // Vérifie si le step courant est terminé pour avancer ou fermer
        this.checkIfAllReviewed()
      } else {
        // ❌ Erreur : réactive le bouton et affiche le message
        btn.disabled      = false
        btn.textContent   = "Voter pour l'homme du match"
        btn.style.opacity = "1"
        const errorMsg    = data.error || "Une erreur est survenue."
        const section     = document.getElementById(`vote-section-${matchId}`)
        if (section) this.showCardError(section, errorMsg)
      }
    } catch (err) {
      // Erreur réseau
      btn.disabled      = false
      btn.textContent   = "Voter pour l'homme du match"
      btn.style.opacity = "1"
    }
  }

  // Passe au match suivant dans le stepper
  // Appelé par data-action="click->review-modal#nextStep" sur le bouton "Match suivant →"
  nextStep() {
    const steps = this.element.querySelectorAll("[data-match-step]")
    if (this.currentStep >= steps.length - 1) return  // déjà sur le dernier step

    // Cache le step courant
    steps[this.currentStep].style.display = "none"

    // Affiche le step suivant
    this.currentStep++
    steps[this.currentStep].style.display = ""

    // Met à jour l'indicateur "2 / 3" dans l'en-tête
    this.updateStepIndicator()

    // Met à jour la visibilité du bouton "Match suivant"
    this.updateNextBtn()

    // Met à jour le compteur de joueurs pour le nouveau step
    this.updatePendingCount()
  }

  // Met à jour l'indicateur de progression "X / Y" dans l'en-tête
  updateStepIndicator() {
    const indicator = this.element.querySelector("[data-step-indicator]")
    if (!indicator) return
    const totalSteps = this.element.querySelectorAll("[data-match-step]").length
    indicator.textContent = `${this.currentStep + 1} / ${totalSteps}`
  }

  // Masque le bouton "Match suivant" quand on est sur le dernier step
  updateNextBtn() {
    const nextBtn = this.element.querySelector("[data-next-btn]")
    if (!nextBtn) return
    const totalSteps = this.element.querySelectorAll("[data-match-step]").length
    nextBtn.style.display = this.currentStep >= totalSteps - 1 ? "none" : ""
  }

  // Met à jour le compteur "encore N joueurs à noter" dans l'en-tête
  // Compte uniquement les formulaires actifs dans le step courant
  updatePendingCount() {
    const label = this.element.querySelector("[data-pending-label]")
    if (!label) return

    // Ne compte que les cards du step courant (pas les autres matchs)
    const currentStepEl = this.element.querySelector(`[data-match-step="${this.currentStep}"]`)
    const remaining = currentStepEl ? currentStepEl.querySelectorAll(".review-card form").length : 0

    if (remaining === 0) {
      // Tous les joueurs de ce match ont été notés
      label.textContent = "Tous les joueurs ont été notés ✓"
      label.style.color = "#1EDD88"
    } else {
      label.textContent = `encore ${remaining} ${remaining > 1 ? "joueurs" : "joueur"} à noter`
      label.style.color = ""
    }
  }

  // Vérifie si le step courant est entièrement traité (avis + vote homme du match)
  // Si oui : avance au step suivant automatiquement, ou ferme la modal si c'est le dernier
  checkIfAllReviewed() {
    const currentStepEl = this.element.querySelector(`[data-match-step="${this.currentStep}"]`)
    if (!currentStepEl) return

    // Formulaires de review encore actifs dans ce step
    const activeForms  = currentStepEl.querySelectorAll(".review-card form")
    // Boutons de vote encore disponibles dans ce step (non soumis)
    const pendingVotes = currentStepEl.querySelectorAll(".vote-candidate-btn")

    // Le step n'est terminé que si ni review ni vote ne restent
    if (activeForms.length > 0 || pendingVotes.length > 0) return

    const totalSteps = this.element.querySelectorAll("[data-match-step]").length

    if (this.currentStep < totalSteps - 1) {
      // Il reste des matchs → avance automatiquement après un bref délai
      setTimeout(() => this.nextStep(), 800)
    } else {
      // Dernier match terminé → ferme la modal
      setTimeout(() => this.dismiss(), 1200)
    }
  }

  // Affiche un message d'erreur sous une card
  showCardError(card, message) {
    // Retire l'erreur précédente si elle existe
    const prev = card.querySelector(".review-error")
    if (prev) prev.remove()

    const errorDiv = document.createElement("div")
    errorDiv.className = "review-error"
    errorDiv.style.cssText = "font-size:0.75rem; color:#ff6b6b; margin-top:0.4rem; text-align:center;"
    errorDiv.textContent = message
    card.appendChild(errorDiv)
  }
}
