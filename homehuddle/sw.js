// Cache version — bump this string on EVERY deploy to force all
// PWA installs to drop the old cache and fetch fresh from network.
const CACHE_VERSION = 'hh-v20260605-1';

self.addEventListener('install', function(e) {
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.map(function(key) {
          // Delete every cache that isn't the current version
          if (key !== CACHE_VERSION) {
            return caches.delete(key);
          }
        })
      );
    }).then(function() {
      return self.clients.claim();
    })
  );
});

self.addEventListener('fetch', function(e) {
  const url = new URL(e.request.url);

  // NEVER cache HTML or calendar requests — always network
  if (
    e.request.destination === 'document' ||
    url.pathname.endsWith('.html') ||
    url.search.includes('email=') ||
    url.search.includes('phone=') ||
    url.hostname.includes('supabase')
  ) {
    e.respondWith(
      fetch(e.request).catch(function() {
        return caches.match(e.request);
      })
    );
    return;
  }

  // Static assets: network first, fall back to cache
  e.respondWith(
    fetch(e.request).then(function(response) {
      if (response.ok) {
        const clone = response.clone();
        caches.open(CACHE_VERSION).then(function(cache) {
          cache.put(e.request, clone);
        });
      }
      return response;
    }).catch(function() {
      return caches.match(e.request);
    })
  );
});

// Push notifications
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
