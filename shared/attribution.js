/* ============================================================================
 * Venuewise Core — shared/attribution.js
 * UTM capture, page_view tracking, and first-touch signup attribution.
 *
 * Depends on shared/config.js (for supabaseUrl + anon key). Deliberately does
 * NOT require supabase-js: this runs on the founders landing page, where the
 * only thing that matters is that the page paints fast.
 *
 * Usage:
 *     <script src="/shared/config.js"></script>
 *     <script src="/shared/attribution.js"></script>
 *     <script>VW.attribution.init({ page: 'founders' });</script>
 *
 * and at signup, once create_family_onboarding has returned a family_id:
 *     await VW.attribution.recordSignup(familyId);
 *
 * ---------------------------------------------------------------------------
 * WHY IT LOOKS LIKE THIS
 *
 * First touch, never overwritten. The first visit this browser makes is the
 * one credited, even if that visit was organic and a later one carried an ad
 * tag. That is what first-touch means, and it is the honest answer: if the
 * user found us organically first, the ad did not earn the signup.
 *
 * Failures are logged, never swallowed. Several past bugs in this platform
 * failed silently with no error, so every failure path here writes a
 * console.warn and records VW.attribution.lastError. A landing page has no
 * good way to surface a tracking failure to a visitor, but it must not lie
 * to us about having succeeded.
 *
 * NOTE: signup_attribution has no utm_term column. utm_term is captured on
 * page_views only. That is a schema fact, not an oversight here.
 * ========================================================================= */
;(function (global) {
  'use strict';

  var VW = global.VW = global.VW || {};

  var UTM_KEYS   = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'];
  var TOUCH_KEY  = 'vw_first_touch';
  var SESS_KEY   = 'vw_session_id';

  var A = VW.attribution = {
    lastError: null,
    ready: false
  };

  /* --- storage helpers: private browsing / blocked cookies must not throw --- */

  function get(store, key) {
    try { return global[store].getItem(key); } catch (e) { return null; }
  }
  function set(store, key, value) {
    try { global[store].setItem(key, value); return true; } catch (e) { return false; }
  }

  function fail(where, err) {
    A.lastError = { where: where, error: String(err && err.message || err), at: new Date().toISOString() };
    try { console.warn('[VW.attribution] ' + where + ' failed:', err); } catch (e) {}
  }

  /* --- session id: matches the shape already in page_views (base36) --- */

  function sessionId() {
    var id = get('sessionStorage', SESS_KEY);
    if (!id) {
      id = Math.random().toString(36).slice(2) + Date.now().toString(36);
      set('sessionStorage', SESS_KEY, id);
    }
    return id;
  }
  A.sessionId = sessionId;

  /* --- UTMs on the current URL --- */

  function utmsFromUrl() {
    var out = {};
    try {
      var q = new URLSearchParams(global.location.search);
      UTM_KEYS.forEach(function (k) {
        var v = q.get(k);
        if (v) { out[k] = String(v).trim().slice(0, 120); }
      });
    } catch (e) {
      fail('utmsFromUrl', e);
    }
    return out;
  }

  function hasAny(obj) {
    for (var k in obj) { if (Object.prototype.hasOwnProperty.call(obj, k)) { return true; } }
    return false;
  }

  /**
   * The first touch for this browser. Written once and never rewritten.
   * Returns {} if nothing has ever been stored and storage is unavailable.
   */
  function firstTouch() {
    var stored = null;
    try {
      stored = JSON.parse(get('localStorage', TOUCH_KEY) || 'null');
    } catch (e) {
      fail('firstTouch:parse', e);
    }
    if (stored) { return stored; }

    var touch = utmsFromUrl();
    try {
      touch.referrer     = (global.document && global.document.referrer) || null;
      touch.landing_page = global.location.pathname + (global.location.search || '');
      touch.first_seen   = new Date().toISOString();
    } catch (e) {
      fail('firstTouch:build', e);
    }
    set('localStorage', TOUCH_KEY, JSON.stringify(touch));
    return touch;
  }
  A.firstTouch = firstTouch;

  /**
   * UTMs to stamp on a page_view: what is on this URL right now, falling back
   * to the stored first touch so every page in an attributed session stays
   * attributed. creative_funnel counts sessions as
   * count(distinct session_id) where utm_content is not null — without this
   * fallback, a visitor who lands on an ad link and then clicks through to
   * join.html would drop out of the denominator.
   */
  function effectiveUtms() {
    var url = utmsFromUrl();
    if (hasAny(url)) { return url; }
    var touch = firstTouch();
    var out = {};
    UTM_KEYS.forEach(function (k) { if (touch[k]) { out[k] = touch[k]; } });
    return out;
  }
  A.effectiveUtms = effectiveUtms;

  /* --- REST plumbing --- */

  function conf() {
    if (!VW.config || !VW.config.supabaseUrl || !VW.config.supabaseAnonKey) {
      throw new Error('shared/config.js must be loaded before shared/attribution.js');
    }
    return VW.config;
  }

  function post(path, body, extraHeaders) {
    var c = conf();
    var headers = {
      'Content-Type': 'application/json',
      'apikey': c.supabaseAnonKey,
      'Authorization': 'Bearer ' + c.supabaseAnonKey
    };
    for (var h in (extraHeaders || {})) { headers[h] = extraHeaders[h]; }
    return fetch(c.supabaseUrl + path, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify(body)
    });
  }

  /**
   * Insert one page_views row. Fire-and-forget, but loud on failure.
   * Resolves true on success, false on any failure — never rejects.
   */
  A.trackPageView = function trackPageView(page) {
    var utms = effectiveUtms();
    var touch = firstTouch();
    var row = {
      page: String(page || 'unknown').slice(0, 120),
      session_id: sessionId(),
      user_agent: (global.navigator && global.navigator.userAgent) || null,
      referrer: (global.document && global.document.referrer) || null,
      landing_page: touch.landing_page || null
    };
    UTM_KEYS.forEach(function (k) { row[k] = utms[k] || null; });

    return post('/rest/v1/page_views', row, { 'Prefer': 'return=minimal' })
      .then(function (res) {
        if (!res.ok) {
          return res.text().then(function (t) {
            fail('trackPageView(' + row.page + ') HTTP ' + res.status, t);
            return false;
          });
        }
        return true;
      })
      .catch(function (e) { fail('trackPageView(' + row.page + ')', e); return false; });
  };

  /**
   * Write the first-touch signup_attribution row for a family.
   *
   * Goes through the record_signup_attribution RPC, not a direct table insert:
   * signup_attribution has RLS enabled with no anon policy, so a direct insert
   * is rejected with "new row violates row-level security policy". The RPC is
   * SECURITY DEFINER, validates family_id against families, and is first-touch
   * only, so calling it twice is a no-op rather than an overwrite.
   *
   * Resolves the RPC's JSON ({ok, first_touch, id} or {ok:false, reason}),
   * or {ok:false, reason:'request failed'} — never rejects, because a
   * tracking failure must not break a signup that already succeeded.
   */
  A.recordSignup = function recordSignup(familyId) {
    var touch = firstTouch();
    var utms = effectiveUtms();
    var payload = {
      family_id: familyId,
      session_id: sessionId(),
      referrer: touch.referrer || null,
      landing_page: touch.landing_page || null
    };
    // utm_term is intentionally omitted: signup_attribution has no such column.
    ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content'].forEach(function (k) {
      payload[k] = utms[k] || null;
    });

    return post('/rest/v1/rpc/record_signup_attribution', { p_payload: payload })
      .then(function (res) {
        return res.text().then(function (text) {
          var parsed = null;
          try { parsed = JSON.parse(text); } catch (e) {}
          if (!res.ok) {
            fail('recordSignup HTTP ' + res.status, text);
            return { ok: false, reason: 'http ' + res.status };
          }
          if (parsed && parsed.ok === false) {
            fail('recordSignup rejected', parsed.reason);
          }
          return parsed || { ok: false, reason: 'unparseable response' };
        });
      })
      .catch(function (e) {
        fail('recordSignup', e);
        return { ok: false, reason: 'request failed' };
      });
  };

  /**
   * Capture the first touch and record a page view. Safe to call on any page.
   */
  A.init = function init(opts) {
    opts = opts || {};
    firstTouch();
    A.ready = true;
    if (opts.page) { A.trackPageView(opts.page); }
    return A;
  };

})(typeof window !== 'undefined' ? window : this);
