# iOS build-time configuration (HomeHuddle) — the single Mac checklist

Everything the Mac/Xcode build needs, in one place. **Only publishable client
values appear here.** No server secret is ever bundled into the iOS binary.

## The ONE file you must create on the Mac
`shared/native-config.js` (git-ignored; created from the committed example).

```bash
cp shared/native-config.example.js shared/native-config.js
# then edit shared/native-config.js and set revenueCatApiKeyIos to the REAL key
```

| Key in `shared/native-config.js` | Value | Source | Status |
|---|---|---|---|
| `revenueCatApiKeyIos` | RevenueCat **public** SDK key (starts `appl_`) | RevenueCat → Project → API keys → Apple | **CEO ACTION REQUIRED** — real key not in repo |
| `entitlement` | `homehuddle` | canonical (already in example) | ✅ repo |
| `offering` | `homehuddle_default` | canonical (already in example) | ✅ repo |
| `products.standard` | `com.venuewise.homehuddle.sub.standard` | canonical | ✅ repo |
| `products.founding` | `com.venuewise.homehuddle.sub.founding` | canonical | ✅ repo |

`build-www.sh` copies `shared/native-config.js` into the bundle and injects its
`<script>` include before `native.js`. If the file is missing it falls back to the
**placeholder** example and prints a loud warning — a build made that way will run
but **in-app purchases will not initialize** until the real key is set.

## Already baked into the web bundle (no action needed)
- **Supabase URL** `https://urwnbskrtoplgnkkxuvl.supabase.co` — in `shared/config.js` + `homehuddle/calendar.html`.
- **Supabase anon (publishable) key** — already in the web bundle; publishable by design (RLS-guarded).
- **VW_APP_VERSION** `1.0.0` — injected by `build-www.sh` (keep in sync with the Xcode build's marketing version).

## NEVER put in the client / this file (server-only)
`STRIPE_SECRET_KEY` · `STRIPE_WEBHOOK_SECRET` · `SUPABASE_SERVICE_ROLE_KEY` ·
`REVENUECAT_WEBHOOK_AUTH` · RevenueCat **secret** API key · Apple In-App-Purchase
Key / private key. These live only in Supabase Edge secrets / RevenueCat / Apple.

## Build sequence (Mac)
```bash
cd mobile
cp ../shared/native-config.example.js ../shared/native-config.js   # then set the real appl_ key
npm install
npm run build:web        # runs build-www.sh → mobile/www
npx cap add ios          # generates mobile/ios (first time only)
npx cap sync ios
npx cap open ios         # opens Xcode
```
Then apply `mobile/ios-config/Info.plist.additions.md` in Xcode.
