/* ============================================================================
 * HomeHuddle — shared/native.js
 * Native bridge for the Capacitor iOS shell. Loaded by the existing web pages;
 * a NO-OP on the web (where window.Capacitor is absent), so the same HTML runs
 * unchanged in a browser and inside the app.
 *
 * Responsibilities:
 *   • platform detection            VW.native.isNative()
 *   • billing router                VW.native.startSubscription() / restore()
 *   • RevenueCat (iOS StoreKit)     identify · offerings · purchase · entitlement
 *   • deep links (OTP return)       App.addListener('appUrlOpen')
 *   • push (APNs) registration      permission · token → backend
 *   • error reporting hook          forwards to VW.observe if present
 *
 * SECURITY: only the RevenueCat *public* SDK key lives here (publishable, safe
 * for clients). NO service_role key, NO Stripe secret, NO Apple private key.
 * Real key values come from window.VW_NATIVE_CONFIG (see native-config.example.js),
 * which is generated at build time and NOT committed.
 *
 * Canonical entitlement id: "homehuddle". Future products ("athletehuddle",
 * "highlightai") plug in via VW.native.hasEntitlement(product) with no rewrite.
 * ========================================================================== */
;(function (global) {
  'use strict';

  var VW = global.VW = global.VW || {};
  var CFG = global.VW_NATIVE_CONFIG || {};

  var Cap = global.Capacitor || null;
  function plugins() { return (Cap && Cap.Plugins) || {}; }
  function isNative() {
    return !!(Cap && typeof Cap.isNativePlatform === 'function' && Cap.isNativePlatform());
  }
  function platform() { return (Cap && Cap.getPlatform && Cap.getPlatform()) || 'web'; }

  var ENTITLEMENT = (CFG.entitlement || 'homehuddle');
  var _rcReady = false;

  function log(){ try { (VW.observe && VW.observe.breadcrumb ? VW.observe.breadcrumb : console.log).apply(null, ['[native]'].concat([].slice.call(arguments))); } catch(e){} }
  function report(err, ctx){ try { if (VW.observe && VW.observe.captureError) VW.observe.captureError(err, ctx); else console.error('[native]', ctx || '', err); } catch(e){} }

  // ── RevenueCat (iOS) ──────────────────────────────────────────────────────
  async function rcConfigure(appUserId) {
    if (!isNative()) return false;
    var Purchases = plugins().Purchases;
    if (!Purchases) { log('RevenueCat plugin not present'); return false; }
    if (!CFG.revenueCatApiKeyIos) { report(new Error('missing revenueCatApiKeyIos'), 'rcConfigure'); return false; }
    try {
      await Purchases.configure({ apiKey: CFG.revenueCatApiKeyIos, appUserID: appUserId || null });
      _rcReady = true;
      log('RevenueCat configured', appUserId ? '(identified)' : '(anonymous)');
      return true;
    } catch (e) { report(e, 'rcConfigure'); return false; }
  }

  // Identify the RevenueCat customer with our OWN stable id (the Supabase family_id)
  // so a purchase on iOS maps to the exact same family/entitlement as the web account.
  async function identify(appUserId) {
    if (!isNative() || !appUserId) return;
    var Purchases = plugins().Purchases;
    try {
      if (!_rcReady) await rcConfigure(appUserId);
      else await Purchases.logIn({ appUserID: String(appUserId) });
      log('RevenueCat identify', appUserId);
    } catch (e) { report(e, 'identify'); }
  }

  async function getOfferings() {
    if (!isNative()) return null;
    try { return await plugins().Purchases.getOfferings(); }
    catch (e) { report(e, 'getOfferings'); return null; }
  }

  async function hasEntitlement(product) {
    product = product || ENTITLEMENT;
    if (!isNative()) return null; // web decides via Supabase subscriptions table
    try {
      var res = await plugins().Purchases.getCustomerInfo();
      var info = res && res.customerInfo ? res.customerInfo : res;
      var active = (info && info.entitlements && info.entitlements.active) || {};
      return !!active[product];
    } catch (e) { report(e, 'hasEntitlement'); return null; }
  }

  // ── Billing router ────────────────────────────────────────────────────────
  // WEB  → existing Stripe flow (caller passes a webFallback fn).
  // iOS  → RevenueCat / StoreKit purchase. NEVER opens Stripe checkout on iOS.
  async function startSubscription(opts) {
    opts = opts || {};
    if (!isNative()) { if (typeof opts.webFallback === 'function') return opts.webFallback(); return { platform: 'web' }; }
    try {
      var offerings = await getOfferings();
      var current = offerings && offerings.current;
      if (!current || !current.availablePackages || !current.availablePackages.length) {
        report(new Error('no RevenueCat packages'), 'startSubscription');
        return { ok: false, reason: 'no_products' };
      }
      // Package selection (Founding vs Standard) is decided by the server-issued
      // offering; see docs. Default to the offering's default package.
      var pkg = pickPackage(current, opts.packageId);
      var result = await plugins().Purchases.purchasePackage({ aPackage: pkg });
      var info = result && (result.customerInfo || result);
      var entitled = !!(info && info.entitlements && info.entitlements.active && info.entitlements.active[ENTITLEMENT]);
      return { ok: entitled, platform: 'ios', customerInfo: info };
    } catch (e) {
      if (e && (e.userCancelled || e.code === '1')) return { ok: false, reason: 'cancelled' };
      report(e, 'startSubscription'); return { ok: false, reason: 'error' };
    }
  }

  function pickPackage(offering, packageId) {
    if (packageId && offering.availablePackages) {
      for (var i=0;i<offering.availablePackages.length;i++)
        if (offering.availablePackages[i].identifier === packageId) return offering.availablePackages[i];
    }
    return offering.availablePackages[0];
  }

  async function restorePurchases() {
    if (!isNative()) return { ok: false, reason: 'web' };
    try {
      var res = await plugins().Purchases.restorePurchases();
      var info = res && (res.customerInfo || res);
      var entitled = !!(info && info.entitlements && info.entitlements.active && info.entitlements.active[ENTITLEMENT]);
      return { ok: entitled, customerInfo: info };
    } catch (e) { report(e, 'restorePurchases'); return { ok: false, reason: 'error' }; }
  }

  // ── Deep links (OTP / notification return) ───────────────────────────────
  function initDeepLinks(handler) {
    if (!isNative()) return;
    var App = plugins().App;
    if (!App || !App.addListener) return;
    App.addListener('appUrlOpen', function (data) {
      log('appUrlOpen', data && data.url);
      try { if (typeof handler === 'function') handler(data.url); } catch (e) { report(e, 'appUrlOpen'); }
    });
  }

  // ── Push notifications (APNs) ─────────────────────────────────────────────
  // Registers for APNs and hands the device token to the backend so the same
  // family gets notifications. Falls back silently if permission is denied.
  // BLOCKED until Apple certs/APNs key exist — see docs/appstore/.
  async function initPush(opts) {
    opts = opts || {};
    if (!isNative()) return { ok: false, reason: 'web' };
    var Push = plugins().PushNotifications;
    if (!Push) return { ok: false, reason: 'no_plugin' };
    try {
      var perm = await Push.checkPermissions();
      if (perm.receive !== 'granted') perm = await Push.requestPermissions();
      if (perm.receive !== 'granted') return { ok: false, reason: 'denied' };

      var registered = false;
      Push.addListener('registration', function (token) {
        if (registered) return; // no duplicate registration
        registered = true;
        log('APNs token acquired');
        if (typeof opts.onToken === 'function') opts.onToken(token.value, platform());
      });
      Push.addListener('registrationError', function (err) { report(err, 'push.registrationError'); });
      Push.addListener('pushNotificationActionPerformed', function (action) {
        var url = action && action.notification && action.notification.data && action.notification.data.url;
        if (url && typeof opts.onTap === 'function') opts.onTap(url);
      });
      await Push.register();
      return { ok: true };
    } catch (e) { report(e, 'initPush'); return { ok: false, reason: 'error' }; }
  }

  // Hide any element marked data-web-only (e.g. Stripe CTAs) when running on iOS.
  function applyPlatformVisibility() {
    if (!isNative()) return;
    try {
      var nodes = document.querySelectorAll('[data-web-only]');
      for (var i=0;i<nodes.length;i++) nodes[i].style.display = 'none';
      document.documentElement.setAttribute('data-platform', 'ios');
    } catch (e) {}
  }

  VW.native = {
    isNative: isNative,
    platform: platform,
    entitlement: ENTITLEMENT,
    configure: rcConfigure,
    identify: identify,
    getOfferings: getOfferings,
    hasEntitlement: hasEntitlement,
    startSubscription: startSubscription,
    restorePurchases: restorePurchases,
    initDeepLinks: initDeepLinks,
    initPush: initPush,
    applyPlatformVisibility: applyPlatformVisibility,
  };

  if (typeof document !== 'undefined') {
    if (document.readyState !== 'loading') applyPlatformVisibility();
    else document.addEventListener('DOMContentLoaded', applyPlatformVisibility);
  }

})(typeof window !== 'undefined' ? window : this);
