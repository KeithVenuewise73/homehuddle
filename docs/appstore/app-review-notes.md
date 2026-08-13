# App Review notes (paste into App Store Connect → App Review Information)

HomeHuddle is a family sports-schedule organizer. Parents sign in with their
mobile number and receive a one-time SMS code (no password).

## Reviewer sign-in — scoped, no production auth weakening
We do **NOT** add any code-level OTP bypass. Instead we use **Supabase Auth's
built-in test phone numbers** (Auth → Providers → Phone → *Test OTP*), which lets
us register ONE dedicated review number with a fixed code. This is config, not
code: it applies only to that exact number, never sends real SMS for it, and
does not affect the OTP path for any real customer number. It can be rotated or
removed after review.

- **Review phone:** `+1 555 010 0100` (finalize the exact test number)
- **Fixed code:** `424242` (set in the Supabase test-OTP config)
- The number maps to a **dedicated demo family** seeded with synthetic data only
  (see `supabase/seed/demo_review_family.sql`) — no real customer data.

Why this is safe (Validation 9):
- No general bypass exists; only the one configured test number accepts the
  fixed code. Every other number still requires a real SMS OTP.
- The demo identity owns only its own synthetic family — RLS prevents it from
  reading any other family's data.
- Removing the test number in the Supabase dashboard fully disables it post-review.

## Subscriptions
- Auto-renewable IAP: Standard $9.99/mo **with a 14-day free trial**, and a
  limited Founding Family $4.99/mo **with no trial** (a locked founder rate for
  the first 100 members). Purchases use StoreKit 2 via RevenueCat.
- "Restore Purchases" is on the Account screen. There are **no external purchase
  links** in the iOS app.
- The same account can also be managed on our website with a different processor;
  the app never links out for purchasing.

## Notifications
Optional. Requests notification permission to remind families about games/
practices; the app works if permission is denied.

## Not accessed
No camera, microphone, contacts, photos, or location. Calendar data comes from
schedule feeds the user subscribes to — not the device calendar.

## Account deletion
Account → **Delete account** (in-app, Guideline 5.1.1(v)). Owner deletion is
scheduled with a 7-day grace (cancel by signing back in); a non-owner member's
"Delete account" removes only their own membership.
