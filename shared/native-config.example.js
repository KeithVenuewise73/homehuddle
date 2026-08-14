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

  // RevenueCat ENTITLEMENT IDENTIFIER — must match the identifier configured in
  // the RevenueCat dashboard EXACTLY (CEO-verified 2026-08). This is the RevenueCat
  // entitlement id, NOT the Supabase product key ('homehuddle') and NOT the bundle id.
  entitlement: 'HomeHuddle Family Calendar Pro',

  // RevenueCat offering that contains the Standard + Founding packages.
  offering: 'homehuddle_default',

  // Canonical Apple StoreKit product identifiers (bundle: com.venuewise.homehuddle).
  // The app matches RevenueCat packages to these product ids so Founding vs
  // Standard selection is explicit and server-authoritative (the webhook keys
  // Founder detection off the ".founding" suffix, not client choice).
  products: {
    standard: 'com.venuewise.homehuddle.sub.standard',  // $9.99/mo, 14-day free trial
    founding: 'com.venuewise.homehuddle.sub.founding',  // $4.99/mo, first 100 paid
  },
};
