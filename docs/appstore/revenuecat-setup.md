# RevenueCat + StoreKit setup (CEO / ops actions)

Everything below is **external account setup** the sprint cannot do in code. The
app-side integration (`shared/native.js`, `supabase/functions/revenuecat-webhook`)
is already built against this contract.

## ✅ HH-IOS-13 — reconciliation with the live RevenueCat state
The live RevenueCat config (CEO-verified) uses different NAMES than this doc's
originals, but the app is **compatible without any RevenueCat change**, because:
- **Offering:** `native.js` reads `offerings.current` (the default offering) — it
  never looks an offering up by name. So the offering id (`default` vs
  `homehuddle_default`) is **irrelevant**; the config value `offering` is unused
  at runtime. **PASS.**
- **Packages:** `getPlans()` matches packages by their **Apple product id**
  (`…sub.standard` / `…sub.founding`), not by package identifier. So the live
  identifiers `$rc_monthly` / `founding_monthly` resolve correctly. **PASS.**
- **Entitlement — the ONE hard dependency:** the app checks
  `customerInfo.entitlements.active['homehuddle']`. RevenueCat's entitlement
  **display name** ("HomeHuddle Family Calendar Pro") does **not** matter, but its
  **identifier MUST be exactly `homehuddle`**. ⚠️ **CEO ACTION — verify the
  entitlement _identifier_** (RevenueCat → Entitlements → the identifier column,
  not the display name). If it is not `homehuddle`, either rename the identifier
  to `homehuddle` OR set `entitlement: '<the real identifier>'` in
  `shared/native-config.js` at build time (no code change needed — `native.js`
  already honors `CFG.entitlement`). If this identifier is wrong, purchases will
  succeed but the app will never unlock. This is the #1 verification item.

## A. App Store Connect (Venuewise LLC org approved; bundle `com.venuewise.homehuddle` registered)
1. Register bundle id **`com.venuewise.homehuddle`** (canonical, already created in App Store Connect).
2. Create the app record: name **HomeHuddle**, primary language English (US).
3. Create **TWO auto-renewable subscription** products in one subscription group
   (`HomeHuddle`). **Trial policy is per-product** (canonical, CEO-confirmed):
   | Product ID (canonical) | Display | Price | Introductory offer |
   |---|---|---|---|
   | `com.venuewise.homehuddle.sub.standard`  | HomeHuddle Standard | $9.99/mo | **Free 2 weeks (14-day)** |
   | `com.venuewise.homehuddle.sub.founding`  | HomeHuddle Founding Family | $4.99/mo | **NONE** (locked founder rate, no trial) |
4. Fill subscription metadata (description, review screenshot) — required or the
   product stays "Missing Metadata" and IAP won't work in review.

> **Two products are REQUIRED** — not optional. The Founding rate is a permanent
> $4.99 grandfathered price, which Apple can only express as a **separate product**
> (a StoreKit "introductory offer" is time-limited and cannot model a permanent
> price). The first-100 cap is enforced **server-side** (`founder_slots_remaining`
> / `reserve_founder_slot`), not by Apple. The RevenueCat offering shows the
> Founding package only while slots remain; once sold out, only Standard is offered.
> The `revenuecat-webhook` keys Founder detection off the **`.founding`** product-id
> suffix, so the founding product id MUST end in `founding`.

> ⚠️ **Reconcile with current App Store Connect state (HH-IOS-11).** The CEO's
> existing single product **"HomeHuddle Monthly"** (1-month, "Free for the first 2
> weeks", 175 regions) matches the **Standard** tier ONLY. Two CEO actions remain:
> (a) confirm "HomeHuddle Monthly" is $9.99 with product id
> `com.venuewise.homehuddle.sub.standard` (or tell us its real id so we align
> `native-config.js`); (b) create the **second** product — Founding $4.99, id
> `com.venuewise.homehuddle.sub.founding`, **no introductory offer**. Without the
> Founding product, Apple users can never claim a founder slot and the "one shared
> global-100 pool across Stripe + Apple" rule is broken on iOS.

## B. RevenueCat  (StoreKit 2 — see credential note below)
1. Create project **HomeHuddle** → add the **Apple App Store** app.
2. Under the app's Apple config, provide the **In-App Purchase Key** (StoreKit 2
   transaction verification). Do **not** rely on the legacy App-Specific Shared
   Secret — that is only for StoreKit 1 receipt validation and is not required
   here. Optionally add an **App Store Connect API Key** (recommended: lets
   RevenueCat manage refunds/notifications, not strictly required for entitlements).
3. Create an **Entitlement** with identifier exactly **`homehuddle`**.
4. Attach both products above to that entitlement.
5. Create an **Offering** `homehuddle_default` with two packages:
   `standard` → standard product, `founding` → founding product.
6. Copy the **Apple public SDK key** (`appl_…`) into `shared/native-config.js`
   at build time (publishable — safe in the binary).
7. Configure the **webhook**: URL `https://urwnbskrtoplgnkkxuvl.supabase.co/functions/v1/revenuecat-webhook`,
   Authorization header value = the secret you also set as the Supabase edge
   secret `REVENUECAT_WEBHOOK_AUTH`.
8. Point **Apple → App Store Server Notifications** at **RevenueCat** (RevenueCat
   provides the URL). Do NOT also point them at our backend — RevenueCat is the
   single Apple-notification processor; our `revenuecat-webhook` consumes
   RevenueCat's webhook only. This avoids duplicate Apple notification handling.

### Credential summary (StoreKit 2)
| Credential | Needed? | Why |
|---|---|---|
| App-Specific Shared Secret | No (legacy) | StoreKit 1 receipt validation only |
| **In-App Purchase Key** | **Yes** | StoreKit 2 transaction verification |
| App Store Connect API Key | Optional (recommended) | Refund/management features |
| Apple Server Notifications | → RevenueCat | Single processor; we consume RC's webhook |

## C. Supabase edge secrets (set, do not commit)
```
REVENUECAT_WEBHOOK_AUTH = <same value as RevenueCat webhook Authorization>
# SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are provided by the platform
```
Then (CEO-approved deploy step, not part of this sprint):
`supabase functions deploy revenuecat-webhook delete-account`

## D. Identity mapping (already coded)
The app calls `Purchases.logIn(family_id)`, so the RevenueCat **App User ID =
Supabase `family_id`**. The webhook writes `subscriptions(source='apple')` for
that family → one entitlement across web + iOS, no duplicate identity.
