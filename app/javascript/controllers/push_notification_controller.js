// Controller Stimulus — Gestion des notifications push navigateur (Web Push API)
// Permet à l'utilisateur d'activer ou désactiver les notifications push depuis son profil.
// La clé VAPID publique est passée via data-push-notification-vapid-key-value.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values  = { vapidKey: String, subscribed: Boolean }

  connect() {
    // On vérifie si le navigateur supporte les notifications push
    if (!("Notification" in window) || !("serviceWorker" in navigator) || !("PushManager" in window)) {
      this.#setUnsupported()
      return
    }
    // Initialisation immédiate depuis l'état serveur (évite le flash "Activer" au rechargement)
    if (Notification.permission === "denied") {
      this.#setBlocked()
    } else if (this.subscribedValue) {
      this.#setActive()
    }
    // Puis on affine avec l'état réel du navigateur (async)
    this.#updateUI()
  }

  // Demande la permission et souscrit au service worker
  async subscribe() {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") {
      this.#setBlocked()
      return
    }

    try {
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly:      true,
        applicationServerKey: this.#urlBase64ToUint8Array(this.vapidKeyValue)
      })

      // Extrait les clés du subscription object
      const key  = subscription.getKey("p256dh")
      const auth = subscription.getKey("auth")

      await fetch("/push_subscriptions", {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token":  document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({
          subscription: {
            endpoint: subscription.endpoint,
            p256dh:   key  ? btoa(String.fromCharCode(...new Uint8Array(key)))  : null,
            auth:     auth ? btoa(String.fromCharCode(...new Uint8Array(auth))) : null
          }
        })
      })

      this.#setActive()
    } catch (err) {
      console.error("Erreur lors de la souscription push :", err)
    }
  }

  // Désabonne l'utilisateur et supprime la subscription en base
  async unsubscribe() {
    try {
      const registration  = await navigator.serviceWorker.ready
      const subscription  = await registration.pushManager.getSubscription()
      if (!subscription) return

      await fetch("/push_subscriptions", {
        method:  "DELETE",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token":  document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ endpoint: subscription.endpoint })
      })

      await subscription.unsubscribe()
      this.#setInactive()
    } catch (err) {
      console.error("Erreur lors du désabonnement push :", err)
    }
  }

  // ── Méthodes privées ────────────────────────────────────────────────────────

  async #updateUI() {
    if (Notification.permission === "denied") {
      this.#setBlocked()
      return
    }

    const registration  = await navigator.serviceWorker.ready
    const subscription  = await registration.pushManager.getSubscription()

    if (subscription) {
      this.#setActive()
    } else if (this.subscribedValue) {
      // La DB indique une subscription active mais le navigateur n'en a plus
      // (SW réinstallé, cache vidé...) → on re-souscrit silencieusement
      await this.subscribe()
    } else {
      this.#setInactive()
    }
  }

  #setActive() {
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent    = "Notifications activées"
      this.buttonTarget.dataset.action = "click->push-notification#unsubscribe"
      this.buttonTarget.classList.add("btn-push-active")
      this.buttonTarget.classList.remove("btn-push-inactive")
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = "✓ Tu recevras des alertes pour les matchs correspondant à ton profil."
  }

  #setInactive() {
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent    = "Activer les notifications"
      this.buttonTarget.dataset.action = "click->push-notification#subscribe"
      this.buttonTarget.classList.add("btn-push-inactive")
      this.buttonTarget.classList.remove("btn-push-active")
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }

  #setBlocked() {
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent  = "Notifications bloquées"
      this.buttonTarget.disabled     = true
      this.buttonTarget.classList.add("btn-push-blocked")
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = "Autorise les notifications dans les paramètres de ton navigateur."
  }

  #setUnsupported() {
    if (this.hasButtonTarget) {
      this.buttonTarget.style.display = "none"
    }
  }

  // Convertit la clé VAPID Base64url en Uint8Array pour l'API PushManager
  #urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64  = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw     = atob(base64)
    return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)))
  }
}
