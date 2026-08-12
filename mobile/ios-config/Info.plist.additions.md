# iOS `Info.plist` + entitlements — values to apply on the Mac build

> The `mobile/ios/` Xcode project is generated on macOS by `npx cap add ios`
> (it is `.gitignore`d). After generating it, apply the keys below in
> `ios/App/App/Info.plist` and the capabilities in Xcode. These are the only
> native config values HomeHuddle needs for Sprint 01.

## Purpose strings (required — App Review rejects missing ones)

| Key | Value |
|-----|-------|
| `NSUserNotificationsUsageDescription` | HomeHuddle sends reminders about your family's games and practices so nobody misses an event. |

> HomeHuddle does **not** request camera, microphone, contacts, photo library,
> location, calendar (EventKit), or tracking. Do **not** add those usage keys or
> the corresponding capabilities — adding an unused permission is itself a
> review risk. Calendar integration is via subscribed iCal/webcal feeds, not
> EventKit, so no `NSCalendarsUsageDescription` is needed.

## App Transport Security
Default ATS is fine — all traffic is HTTPS (`*.supabase.co`, `venuewise.net`).
Do not add ATS exceptions.

## Capabilities to enable in Xcode (Signing & Capabilities)
- **Push Notifications** (creates the APNs entitlement) — blocked until the
  Apple org is approved and an APNs key exists.
- **In-App Purchase** (StoreKit) — added automatically once IAP products exist
  in App Store Connect; RevenueCat uses this.
- **Associated Domains** (only if you later add Universal Links):
  `applinks:venuewise.net`. Not required for Sprint 01 (OTP deep links use the
  Capacitor `appUrlOpen` custom-scheme path).

## URL scheme (deep links for OTP return)
Add a custom URL scheme so Supabase OTP/redirects re-enter the app:
- `CFBundleURLTypes` → `CFBundleURLSchemes` = `homehuddle`
- Supabase Auth → URL Configuration → add redirect `homehuddle://login-callback`
  (and keep the existing web redirect for the web app).

## Bundle identifier
`com.venuewise.homehuddle` — canonical Apple Bundle ID, registered in App Store Connect (Team: Venuewise LLC). Must match `appId` in `mobile/capacitor.config.ts`.

## Version / build
- Marketing version (`CFBundleShortVersionString`): `1.0.0`
- Build (`CFBundleVersion`): integer, bump every TestFlight upload (`1`, `2`, …)
- Keep `VW_APP_VERSION` (injected into the web bundle by `build-www.sh`) in sync
  so `client_errors.app_version` is meaningful.
