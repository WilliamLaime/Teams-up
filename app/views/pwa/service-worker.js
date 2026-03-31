// ── Service Worker Teams-Up ──────────────────────────────────────────────────
// Ce fichier est enregistré par le layout et tourne en arrière-plan dans le navigateur.
// Il intercepte les requêtes réseau pour les mettre en cache et permettre un mode offline.

// Nom du cache : incrémenté à "v2" pour forcer l'effacement du cache v1
// (le cache v1 contenait des pages HTML avec du contenu utilisateur, ce qui causait
//  l'affichage de photos incorrectes après connexion)
const CACHE_NAME = "teams-up-v2";

// Seule la page offline est pré-cachée (les pages HTML contiennent du contenu
// spécifique à l'utilisateur connecté → jamais en cache)
const PAGES_TO_PRECACHE = ["/offline"];

// ── Événement "install" ───────────────────────────────────────────────────────
// Déclenché une seule fois quand le service worker est installé pour la 1ère fois.
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(PAGES_TO_PRECACHE);
    })
  );
  self.skipWaiting();
});

// ── Événement "activate" ─────────────────────────────────────────────────────
// On supprime tous les anciens caches (notamment le v1 qui contenait des pages HTML).
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter((name) => name !== CACHE_NAME)
          .map((name) => caches.delete(name))
      );
    })
  );
  self.clients.claim();
});

// ── Événement "fetch" ────────────────────────────────────────────────────────
// Stratégie différenciée selon le type de requête :
//   • Navigations HTML        → Network Only (toujours fraîche, jamais en cache)
//   • ActiveStorage / uploads → ignoré (géré directement par le navigateur)
//   • Assets statiques (JS/CSS/images de l'app) → Network First avec fallback cache
self.addEventListener("fetch", (event) => {
  // On ignore les requêtes non-GET
  if (event.request.method !== "GET") return;

  // On ignore les WebSockets ActionCable
  if (event.request.url.includes("/cable")) return;

  // On ignore les requêtes vers d'autres domaines (Cloudinary, CDN...)
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  // ── CAS 1 : Navigations (pages HTML) ─────────────────────────────────────
  // Les pages HTML contiennent du contenu propre à l'utilisateur connecté
  // (avatar, nom, notifications...). On ne les met JAMAIS en cache pour éviter
  // d'afficher du contenu périmé (ex: photo de profil incorrecte après connexion).
  // En cas d'échec réseau → on renvoie la page offline.
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match("/offline"))
    );
    return;
  }

  // ── CAS 2 : ActiveStorage blobs (photos uploadées par les utilisateurs) ───
  // Ces URLs sont dynamiques et spécifiques à chaque utilisateur.
  // On laisse le navigateur les gérer directement sans passer par le cache SW.
  if (url.pathname.startsWith("/rails/active_storage/")) {
    return; // le navigateur gère la requête normalement
  }

  // ── CAS 3 : Assets statiques (JS, CSS, fonts, images de l'app) ───────────
  // Network First : on essaie le réseau, on met en cache si succès.
  // En cas d'échec réseau → on utilise le cache (mode offline).
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        // Succès réseau → on met en cache pour usage offline futur
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return networkResponse;
      })
      .catch(() => {
        // Réseau indisponible → on cherche dans le cache
        return caches.match(event.request);
      })
  );
});
