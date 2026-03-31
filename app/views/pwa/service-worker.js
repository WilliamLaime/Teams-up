// ── Service Worker TeamUp ────────────────────────────────────────────────────
// Ce fichier est enregistré par le layout et tourne en arrière-plan dans le navigateur.
// Il intercepte les requêtes réseau pour les mettre en cache et permettre un mode offline.

// Nom du cache : à changer quand on veut forcer un rafraîchissement du cache
const CACHE_NAME = "teamup-v1";

// Pages à pré-cacher dès l'installation du service worker
const PAGES_TO_PRECACHE = ["/", "/offline"];

// ── Événement "install" ───────────────────────────────────────────────────────
// Déclenché une seule fois quand le service worker est installé pour la 1ère fois.
// On en profite pour mettre en cache les pages essentielles.
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      // addAll télécharge et stocke les pages dans le cache
      return cache.addAll(PAGES_TO_PRECACHE);
    })
  );
  // skipWaiting : le nouveau SW prend le contrôle immédiatement sans attendre
  self.skipWaiting();
});

// ── Événement "activate" ─────────────────────────────────────────────────────
// Déclenché quand le SW devient actif (après install).
// On supprime les anciens caches pour libérer de l'espace.
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME) // on garde seulement le cache actuel
          .map((name) => caches.delete(name))     // on supprime les anciens caches
      );
    })
  );
  // clients.claim : le SW prend immédiatement le contrôle des onglets ouverts
  self.clients.claim();
});

// ── Événement "fetch" ────────────────────────────────────────────────────────
// Déclenché à chaque requête réseau de l'app (pages, images, CSS, JS...).
// Stratégie : Network First → on essaie le réseau, et si ça échoue (offline),
// on retourne la réponse en cache.
self.addEventListener("fetch", (event) => {
  // On ignore les requêtes non-GET (POST, PATCH, DELETE...)
  // Ces requêtes ne peuvent pas être mises en cache de façon simple
  if (event.request.method !== "GET") return;

  // On ignore les connexions WebSocket d'ActionCable (Turbo Streams / chat)
  // car elles ne sont pas des requêtes HTTP classiques
  if (event.request.url.includes("/cable")) return;

  // On ignore les requêtes vers d'autres domaines (ex: CDN Lucide Icons)
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        // Requête réseau réussie → on met la réponse en cache pour usage futur
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone(); // on clone car le body ne peut être lu qu'une fois
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return networkResponse;
      })
      .catch(() => {
        // Réseau indisponible → on cherche dans le cache
        return caches.match(event.request).then((cachedResponse) => {
          // Si la page est en cache, on la retourne
          if (cachedResponse) return cachedResponse;
          // Sinon, si c'est une navigation (page HTML), on affiche la page offline
          if (event.request.mode === "navigate") {
            return caches.match("/offline");
          }
        });
      })
  );
});
