// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
// ⚠️ `import "bootstrap"` et NON `import * as bootstrap` : le fichier épinglé
// (bootstrap.min.js du gem bootstrap) est le build **UMD**, qui n'a aucun export
// ESM — le namespace importé serait un objet VIDE, et `bootstrap.Modal` valait
// donc `undefined`. Le UMD peuple `window.bootstrap` : c'est ce global qu'il faut
// lire (comme le font déjà les contrôleurs Stimulus). Cette erreur silencieuse
// cassait les trois handlers ci-dessous depuis leur écriture.
import "bootstrap"

// ── Sentry Browser SDK — monitoring des erreurs JavaScript ───────────────────
//
// On lit le DSN depuis le meta tag injecté côté serveur (layout application.html.erb).
// Cela évite d'écrire le DSN en dur dans le JS et reste compatible avec le CSP.
// Sentry ne s'initialise que si le DSN est présent (= absent en dev/test).
import * as Sentry from "@sentry/browser"

const sentryDsn = document.querySelector("meta[name='sentry-dsn']")?.content
if (sentryDsn) {
  Sentry.init({
    dsn: sentryDsn,
    // browserTracingIntegration surveille les navigations Turbo et les requêtes fetch
    integrations: [Sentry.browserTracingIntegration()],
    // Echantillonne 20 % des transactions front (navigation, XHR) pour le perf monitoring
    tracesSampleRate: 0.2,
  })
}

// Ré-initialise les icônes Lucide après chaque mise à jour d'un turbo_frame ou turbo:render
// (ex: le bouton ami se met à jour en live → les nouveaux <i data-lucide="..."> doivent être convertis en SVG)
// RGAA 4.8 — masquer tous les SVG Lucide des lecteurs d'écran avec aria-hidden=true
// Car les icônes décoratives ne doivent pas être annoncées aux utilisateurs de technologies d'assistance
document.addEventListener("turbo:frame-render", () => {
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// RGAA 4.8 — re-render Lucide après turbo:render (réponses 422, streams, etc.)
document.addEventListener("turbo:render", () => {
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// Initialise les tooltips Bootstrap sur chaque navigation Turbo
// Turbo remplace le DOM sans recharger la page — on doit donc ré-initialiser à chaque fois
document.addEventListener("turbo:load", () => {
  // Sélectionne tous les éléments avec l'attribut data-bs-toggle="tooltip"
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  // window.bootstrap explicite : le namespace importé masquait le global et
  // valait {} (build UMD), donc ce constructeur levait une exception silencieuse.
  if (window.bootstrap?.Tooltip) {
    tooltipElements.forEach(el => new window.bootstrap.Tooltip(el))
  }

  // RGAA 4.8 — masquer les SVG Lucide au chargement initial
  if (window.lucide) window.lucide.createIcons({ attrs: { "aria-hidden": "true" } })
})

// ── Gestion hcaptcha + Turbo Drive ──────────────────────────────────────────
//
// Problème : hcaptcha charge son script avec "async defer".
// Turbo Drive ne ré-exécute pas les scripts déjà chargés lors des navigations.
// Résultat : l'auto-render hcaptcha ne se déclenche pas → widget invisible sur mobile.
//
// Solution en 2 étapes :
//   1. Avant la mise en cache Turbo → vider le widget pour éviter qu'un token
//      expiré soit restauré depuis le snapshot (même si no-cache est activé)
//   2. Après chaque navigation Turbo → forcer le re-render manuellement

// ── Compteur de pages vues dans l'onglet ────────────────────────────────────
//
// Sert aux boutons « Retour » (cf. back_link_controller) à savoir s'il existe une
// page précédente DANS l'app. On ne peut pas le déduire autrement : sous Turbo
// Drive, document.referrer reste figé au chargement initial, et history.length
// compte aussi les pages visitées avant d'arriver sur le site.
//
// turbo:load couvre les deux cas (chargement initial ET navigation Turbo) : au
// premier affichage le compteur vaut 1, donc « pas de page précédente ».
document.addEventListener("turbo:load", () => {
  try {
    const key = "teamsup:visit-count"
    sessionStorage.setItem(key, String(Number(sessionStorage.getItem(key) || 0) + 1))
  } catch {
    // sessionStorage indisponible : les boutons Retour utiliseront leur URL de secours.
  }
})

// ── Confirmation des actions destructrices ──────────────────────────────────
//
// Par défaut, tout `data-turbo-confirm` passe par window.confirm : un encadré
// dessiné par le navigateur (« localhost:3000 indique »), impossible à styler.
// setConfirmMethod redirige TOUS ces appels vers notre modale Bootstrap
// (shared/_confirm_modal, rendue dans le layout) — aucune vue à modifier.
//
// Le contrat Turbo attend une Promise<boolean> : true = on poursuit l'action.
// Options facultatives portées par le bouton (ou le formulaire) :
//   data-turbo-confirm-accept="Déclarer forfait"  → libellé du bouton
//   data-turbo-confirm-danger                     → bouton rouge
Turbo.setConfirmMethod((message, element, submitter) => {
  const modalElement = document.getElementById("turboConfirmModal")

  // Repli sur le confirm natif si la modale n'est pas là (page servie sans le
  // layout, Bootstrap pas encore chargé) : mieux vaut un encadré laid qu'une
  // action destructrice exécutée sans confirmation.
  // On teste `window.bootstrap?.Modal` et non `typeof bootstrap` : le namespace
  // importé existe toujours (objet vide côté UMD), donc tester sa seule présence
  // ne prouve rien — c'est exactement ce qui faisait échouer la confirmation.
  if (!modalElement || !window.bootstrap?.Modal) {
    return Promise.resolve(window.confirm(message))
  }

  // « Déclarer X forfait ? Ses matchs seront perdus. » → la question devient le
  // titre, l'explication le corps. Les messages sans explication (« Terminer ce
  // tournoi maintenant ? ») n'affichent tout simplement pas de corps.
  const [question, ...rest] = String(message).split(/(?<=\?)\s+/)
  const detail = rest.join(" ").trim()

  modalElement.querySelector("[data-confirm-title]").textContent = question
  const detailSlot = modalElement.querySelector("[data-confirm-detail]")
  detailSlot.textContent = detail
  detailSlot.hidden = detail === ""

  const source = submitter || element
  const accept = modalElement.querySelector("[data-confirm-accept]")
  accept.textContent = source?.dataset?.turboConfirmAccept || "Confirmer"
  const danger = source?.dataset?.turboConfirmDanger !== undefined
  accept.classList.toggle("btn-danger", danger)
  accept.classList.toggle("btn-primary", !danger)

  const modal = window.bootstrap.Modal.getOrCreateInstance(modalElement)

  return new Promise((resolve) => {
    let confirmed = false

    const onAccept = () => { confirmed = true; modal.hide() }
    // On résout sur `hidden` et non sur le clic : l'utilisateur peut fermer par
    // Échap, par le backdrop ou par « Annuler » — un seul point de sortie évite
    // de laisser une Promise pendante (Turbo attendrait indéfiniment).
    const onHidden = () => {
      accept.removeEventListener("click", onAccept)
      modalElement.removeEventListener("hidden.bs.modal", onHidden)
      resolve(confirmed)
    }

    accept.addEventListener("click", onAccept)
    modalElement.addEventListener("hidden.bs.modal", onHidden)
    modal.show()
  })
})

document.addEventListener("turbo:before-cache", () => {
  // Vide les widgets hcaptcha avant que Turbo prenne un snapshot de la page.
  // Sans ça, le snapshot contient un iframe avec un token invalide.
  document.querySelectorAll(".h-captcha").forEach(el => {
    el.innerHTML = ""
  })
})

// Fonction partagée : re-rend les widgets hcaptcha vides présents dans la page.
// Un widget déjà rendu contient un <iframe> — on ne re-rend que les divs vides
// pour éviter de créer des doublons.
function rerenderHcaptchaWidgets() {
  if (typeof hcaptcha === "undefined") return

  document.querySelectorAll(".h-captcha").forEach(el => {
    if (!el.querySelector("iframe")) {
      hcaptcha.render(el)
    }
  })
}

// turbo:load → navigation classique (lien, retour arrière, redirection)
document.addEventListener("turbo:load", rerenderHcaptchaWidgets)

// turbo:render → AUSSI déclenché après une réponse 422 (erreur de formulaire).
// turbo:load ne se déclenche PAS dans ce cas, c'est pour ça que le widget
// disparaissait après une erreur et ne réapparaissait qu'au rechargement complet.
document.addEventListener("turbo:render", rerenderHcaptchaWidgets)

// ── Dispose toutes les modales Bootstrap avant que Turbo remplace le body ──────
//
// Problème : Bootstrap garde un flag interne _isAppended=true. Si le body est
// remplacé par Turbo sans dispose(), le backdrop ne se ré-insère plus lors de la
// prochaine ouverture de modale.
//
// Solution : Dispose toutes les modales actives avant turbo:before-render
document.addEventListener("turbo:before-render", () => {
  document.querySelectorAll(".modal").forEach(el => {
    const instance = window.bootstrap?.Modal?.getInstance(el)
    if (instance) instance.dispose()
  })
})

// ── Ferme le drawer offcanvas mobile avant que Turbo remplace le body ──────────
//
// Même problème que les modales : Bootstrap garde un état interne sur l'offcanvas.
// On cache le drawer proprement avant chaque navigation Turbo pour éviter qu'il
// reste ouvert (ou bloqué) après le remplacement du DOM.
document.addEventListener("turbo:before-render", () => {
  const offcanvasEl = document.getElementById("mobileNavDrawer")
  if (offcanvasEl) {
    const instance = window.bootstrap?.Offcanvas?.getInstance(offcanvasEl)
    if (instance) instance.hide()
  }
})

