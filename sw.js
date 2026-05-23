// ═══════════════════════════════════════════════════════════════════
// HomeHuddle Service Worker — handles push notifications
// Place this file at the ROOT of your site: venuewise.net/sw.js
// ═══════════════════════════════════════════════════════════════════

self.addEventListener('push', function(event) {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch(e) {
    data = { title: 'HomeHuddle', body: event.data ? event.data.text() : 'You have a new update.' };
  }

  const title   = data.title || 'HomeHuddle';
  const options = {
    body:    data.body    || 'Tap to view your schedule.',
    icon:    data.icon    || '/icon-192.png',
    badge:   data.badge   || '/icon-192.png',
    tag:     data.tag     || 'homehuddle',
    data:    { url: data.url || 'https://venuewise.net/calendar.html' },
    requireInteraction: false,
    vibrate: [200, 100, 200],
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const url = event.notification.data?.url || 'https://venuewise.net/calendar.html';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (const client of clientList) {
        if (client.url.includes('venuewise.net') && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});

self.addEventListener('install',  function() { self.skipWaiting(); });
self.addEventListener('activate', function(event) { event.waitUntil(clients.claim()); });
