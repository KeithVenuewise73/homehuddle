/* ============================================================================
 * shared/native-config.example.js
 * Copy to shared/native-config.js at BUILD TIME (never commit the real file).
 * These are PUBLISHABLE client values only — safe to ship in the iOS binary.
 * NO service_role key, NO Stripe secret, NO Apple private key ever goes here.
 *
 * The RevenueCat iOS key is the "public SDK key" (starts with `appl_`), found in
 * RevenueCat → Project → API keys → Apple. It is publishable by design.
 * ========================================================================== */
window.VW_NATIVE_CONFIG = {
  // RevenueCat public (SDK) key for the Apple app. Placeholder — replace at build.
  revenueCatApiKeyIos: 'appl_XXXXXXXXXXXXXXXXXXXXXXXXXXXX',

  // Canonical entitlement identifier configured in RevenueCat.
  entitlement: 'homehuddle',

  // Optional: RevenueCat offering identifier that contains the Founding + Standard
  // packages. The SERVER decides Founding eligibility; this only names the offering.
  offering: 'homehuddle_default',
};
