/* ============================================================================
 * shared/observability.js  — minimum viable error visibility for a paid launch.
 * Zero-dependency, no external paid account required. Captures:
 *   • uncaught errors + unhandled promise rejections
 *   • explicitly reported failures (billing, feed sync, push) via VW.observe.captureError
 * and posts a compact record to the Supabase `client_errors` table (anon INSERT,
 * see migration 0003). Client-throttled to avoid loops/spam.
 *
 * Optional upgrade path: if window.VW_SENTRY_DSN is set, forward there instead.
 * (Sentry has a free tier; enabling it is a CEO/ops action — see docs/appstore.)
 * ========================================================================== */
;(function (global) {
  'use strict';
  var VW = global.VW = global.VW || {};
  // Resolve Supabase config LAZILY at send time (page defines it after load).
  function creds() {
    var c = (VW && VW.config) || (global.VW_ENV) || {};
    return {
      url: c.supabaseUrl || global.SURL || '',
      key: c.supabaseAnonKey || global.SKEY || '',
    };
  }

  var MAX_PER_SESSION = 25;
  var sent = 0;
  var lastKey = '';

  function ctxInfo() {
    var native = !!(global.Capacitor && global.Capacitor.isNativePlatform && global.Capacitor.isNativePlatform());
    return {
      platform: native ? ((global.Capacitor.getPlatform && global.Capacitor.getPlatform()) || 'native') : 'web',
      path: (global.location && location.pathname) || '',
      ua: (global.navigator && navigator.userAgent) || '',
      app_version: (global.VW_APP_VERSION || 'web'),
    };
  }

  function post(record) {
    if (sent >= MAX_PER_SESSION) return;
    var key = (record.kind || '') + '|' + (record.message || '').slice(0, 120);
    if (key === lastKey) return;        // collapse identical consecutive errors
    lastKey = key; sent++;
    if (global.VW_SENTRY_DSN && global.Sentry && global.Sentry.captureException) {
      try { global.Sentry.captureException(record._err || new Error(record.message)); return; } catch (e) {}
    }
    var cr = creds();
    if (!cr.url || !cr.key) { try { console.warn('[observe]', record); } catch(e){} return; }
    try {
      fetch(cr.url + '/rest/v1/client_errors', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': cr.key, 'Authorization': 'Bearer ' + cr.key, 'Prefer': 'return=minimal' },
        body: JSON.stringify(Object.assign({ created_at: new Date().toISOString() }, ctxInfo(), record)),
        keepalive: true,
      }).catch(function(){});
    } catch (e) {}
  }

  VW.observe = {
    captureError: function (err, context) {
      var msg = (err && err.message) ? err.message : String(err);
      post({ kind: 'error', message: msg, context: String(context || ''), stack: (err && err.stack ? String(err.stack).slice(0, 1000) : null), _err: err });
    },
    // Domain-specific helpers so failures are queryable in the admin dashboard.
    captureBillingFailure: function (detail) { post({ kind: 'billing', message: String(detail || 'billing failure') }); },
    captureSyncFailure: function (detail) { post({ kind: 'feed_sync', message: String(detail || 'feed sync failure') }); },
    capturePushFailure: function (detail) { post({ kind: 'push', message: String(detail || 'push failure') }); },
    breadcrumb: function () { try { console.log.apply(console, arguments); } catch (e) {} },
  };

  global.addEventListener && global.addEventListener('error', function (e) {
    VW.observe.captureError(e.error || new Error(e.message), 'window.onerror');
  });
  global.addEventListener && global.addEventListener('unhandledrejection', function (e) {
    VW.observe.captureError(e.reason || new Error('unhandledrejection'), 'unhandledrejection');
  });

})(typeof window !== 'undefined' ? window : this);
