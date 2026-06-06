// HomeHuddle Service Worker
// Strategy: cache static assets (icons, fonts) but NEVER cache calendar.html
// or any page with query params — those must always come fresh from the network
// so the correct family data loads every time.

const CACHE_NAME = 'hh-static-v3';

// Only cache true static assets — never HTML pages
const STATIC_ASSETS = [
  '/homehuddle/icon-192.png',
  '/homehuddle/icon-512.png',
  '/homehuddle/manifest.json'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(STATIC_ASSETS);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  // Delete all old caches so stale HTML pages can't haunt us
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) { return k !== CACHE_NAME; })
            .map(function(k) { return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(e) {
  const url = new URL(e.request.url);

  // NEVER serve HTML from cache — always fetch fresh from network
  // This prevents wrong family calendars showing up on home screen launch
  if (e.request.destination === 'document' ||
      url.pathname.endsWith('.html') ||
      url.search.includes('email=') ||
      url.search.includes('phone=')) {
    e.respondWith(fetch(e.request));
    return;
  }

  // For static assets, try cache first then network
  e.respondWith(
    caches.match(e.request).then(function(cached) {
      return cached || fetch(e.request).then(function(response) {
        // Only cache same-origin static assets
        if (response.ok && url.origin === self.location.origin) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(function(cache) {
            cache.put(e.request, clone);
          });
        }
        return response;
      });
    })
  );
});

// ── PUSH NOTIFICATIONS ────────────────────────────────────
self.addEventListener('push', function(e) {
  let data = { title: 'HomeHuddle', body: 'Schedule update', icon: '/homehuddle/icon-192.png' };
  try { if (e.data) data = Object.assign(data, e.data.json()); } catch(x) {}
  e.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: data.icon || '/homehuddle/icon-192.png',
      badge: '/homehuddle/icon-192.png',
      tag: 'hh-update',
      renotify: true,
      data: data
    })
  );
});

self.addEventListener('notificationclick', function(e) {
  e.notification.close();
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(cls) {
      for (const c of cls) {
        if (c.url.includes('/homehuddle/') && 'focus' in c) return c.focus();
      }
      return clients.openWindow('/homehuddle/calendar.html');
    })
  );
});
