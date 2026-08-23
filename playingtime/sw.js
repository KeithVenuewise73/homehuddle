/* ============================================================================
 * PlayingTime Football — service worker
 *
 * Purpose: the app opens and tracks a game when the stadium has no signal.
 * The shell is cached on install; game data never travels through here — it is
 * written straight to localStorage by store.js.
 *
 * Cache name carries a version. Bump PT_CACHE when the shell changes, or a
 * returning phone keeps serving the old app.
 * ========================================================================== */
const PT_CACHE = 'playingtime-v1';

const SHELL = [
  './',
  './index.html',
  './manifest.json',
  './assets/css/app.css',
  './assets/js/app.js',
  './assets/js/catalog.js',
  './assets/js/engine.js',
  './assets/js/store.js',
  './assets/js/sync.js',
  './assets/js/sharecard.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(PT_CACHE)
      /* One missing file must not fail the whole install and leave the app with
       * no offline shell at all, so each is added individually. */
      .then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== PT_CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;   /* fonts etc. go to the network */

  /* Network first, cache as the fallback: a parent who has signal should get the
   * current app; a parent who does not should still get one that works. */
  event.respondWith(
    fetch(request)
      .then((response) => {
        if (response && response.ok) {
          const copy = response.clone();
          caches.open(PT_CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
        }
        return response;
      })
      .catch(() => caches.match(request).then((hit) => hit || caches.match('./index.html')))
  );
});
