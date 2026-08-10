# RevenueCat + StoreKit setup (CEO / ops actions)

Everything below is **external account setup** the sprint cannot do in code. The
app-side integration (`shared/native.js`, `supabase/functions/revenuecat-webhook`)
is already built against this contract.

## A. App Store Connect (blocked until Venuewise LLC org is approved)
1. Register bundle id **`net.venuewise.homehuddle`**.
2. Create the app record: name **HomeHuddle**, primary language English (US).
3. Create **auto-renewable subscription** products in one subscription group
   (`HomeHuddle`), each with a **14-day free trial** introductory offer:
   | Product ID (proposed) | Display | Price |
   |---|---|---|
   | `net.venuewise.homehuddle.sub.standard`  | HomeHuddle Standard | $9.99/mo |
   | `net.venuewise.homehuddle.sub.founding`  | HomeHuddle Founding Family | $4.99/mo |
4. Fill subscription metadata (description, review screenshot) — required or the
   product stays "Missing Metadata" and IAP won't work in review.

> Founder cap (first 100) is enforced **server-side** (`claim_founder_slot`), not
> by Apple. The RevenueCat offering shows the Founding package only while slots
> remain; once sold out, only Standard is offered.

## B. RevenueCat
1. Create project **HomeHuddle** → add the **Apple App Store** app (paste the
   App Store Connect **In-App Purchase Key** / shared secret).
2. Create an **Entitlement** with identifier exactly **`homehuddle`**.
3. Attach both products above to that entitlement.
4. Create an **Offering** `homehuddle_default` with two packages:
   `standard` → standard product, `founding` → founding product.
5. Copy the **Apple public SDK key** (`appl_…`) into `shared/native-config.js`
   at build time (publishable — safe in the binary).
6. Configure the **webhook**: URL `https://urwnbskrtoplgnkkxuvl.supabase.co/functions/v1/revenuecat-webhook`,
   Authorization header value = the secret you also set as the Supabase edge
   secret `REVENUECAT_WEBHOOK_AUTH`.

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
