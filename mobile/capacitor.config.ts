import type { CapacitorConfig } from '@capacitor/cli';

/**
 * HomeHuddle — Capacitor iOS configuration.
 *
 * STRATEGY: bundle the existing HomeHuddle web app (built into ./www by
 * build-www.sh) into the native binary. We do NOT use server.url to point at
 * venuewise.net — bundling the assets is what Apple expects and keeps the
 * iOS app on the StoreKit billing path (no live-web Stripe checkout leaks).
 *
 * appId is a PLACEHOLDER-VALID reverse-DNS identifier for Venuewise LLC.
 * It is technically valid. App Store *availability/registration* of this
 * identifier still requires Apple Developer / App Store Connect access
 * (organization enrollment is pending) — see docs/appstore/.
 */
const config: CapacitorConfig = {
  appId: 'net.venuewise.homehuddle',
  appName: 'HomeHuddle',
  webDir: 'www',
  // iosScheme 'capacitor' (default) serves bundled assets from capacitor://localhost
  ios: {
    contentInset: 'always',
    limitsNavigationsToAppBoundDomains: false,
  },
  server: {
    // Keep the app on its own origin. Allow navigation to Supabase + Stripe portal
    // (web billing management is fine to open in the system browser via @capacitor/browser).
    // NOTE: no `url` key on purpose — assets are bundled, not remotely served.
    allowNavigation: [
      'urwnbskrtoplgnkkxuvl.supabase.co',
    ],
  },
  plugins: {
    PushNotifications: {
      presentationOptions: ['badge', 'sound', 'alert'],
    },
  },
};

export default config;
