# HomeHuddle — iOS (Capacitor) shell

Packages the **existing** HomeHuddle web app (in `/homehuddle` + `/shared`) into
a native iOS binary for TestFlight / App Store. No UI is rewritten or forked —
`build-www.sh` assembles the real pages into `www/` and Capacitor bundles them.

## Prerequisites
- **macOS + Xcode 15+** and **CocoaPods** (the iOS platform cannot be generated
  or built on Linux — the CI/dev machine for this step must be a Mac).
- Node 20+.

## First-time setup (on a Mac)
```bash
cd mobile
npm install
cp ../shared/native-config.example.js ../shared/native-config.js   # fill in RevenueCat public key
npm run build:web         # assembles ./www from the existing web app
npx cap add ios           # generates ./ios (Xcode project)
npx cap sync ios
npx cap open ios          # opens Xcode
```
Then in Xcode apply `ios-config/Info.plist.additions.md` (purpose strings,
capabilities, URL scheme) and set the signing team once the Apple org clears.

## Rebuild after web changes
```bash
npm run sync              # build:web + cap sync ios
```

## What is committed vs generated
- **Committed:** `capacitor.config.ts`, `package.json`, `build-www.sh`,
  `ios-config/` notes.
- **Generated / git-ignored:** `www/`, `ios/`, `node_modules/`,
  `../shared/native-config.js`.

## Billing
The shell uses **RevenueCat/StoreKit** on iOS (never Stripe checkout). The web
app keeps Stripe. Both converge on the one `subscriptions` entitlement row.
See `docs/appstore/revenuecat-setup.md`.
