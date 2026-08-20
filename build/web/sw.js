/* Monster Battle CCG — offline service worker.
 *
 * The campaign already runs entirely client-side (save state lives in
 * localStorage), so the only thing standing between this page and a real
 * offline Android app is the network fetch for the shell and its art.
 *
 * Strategy:
 *   - navigations           -> network-first, falling back to the cached shell
 *                              (so a redeploy is picked up, but a plane ride
 *                              still boots the game)
 *   - everything else       -> cache-first (the art never changes per build)
 *
 * Bump CACHE when the shell or the art pipeline changes; old caches are
 * dropped on activate.
 */
'use strict';

const CACHE = 'mbccg-shell-v1';
const SHELL = [
  './',
  './game.html',
  './manifest.webmanifest',
  './assets/logo.png',
  './assets/bg/world.png',
  './assets/bg/battle_empty.png',
  './assets/ui/crystal.png',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png',
  './assets/icons/maskable-192.png',
  './assets/icons/maskable-512.png',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE)
      // addAll is atomic: one 404 would sink the whole install, so add
      // each entry best-effort and let runtime caching pick up the rest.
      .then(cache => Promise.all(SHELL.map(url => cache.add(url).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // never touch cross-origin

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then(hit => hit || caches.match('./')))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res && res.ok && res.type === 'basic') {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
      }
      return res;
    }))
  );
});
