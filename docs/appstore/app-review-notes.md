# App Review notes (paste into App Store Connect → App Review Information)

HomeHuddle is a family sports-schedule organizer. Parents sign in with their
mobile number and receive a one-time SMS code (no password).

## Reviewer sign-in (deterministic — no need to contact us)
We use phone OTP, so please use the seeded review account below. It bypasses SMS
by accepting a fixed code in the review build (this path is enabled ONLY for the
seeded review number and grants no elevated privileges).

- Phone: **+1 555 0100 (or the number we finalize)**
- One-time code: **000000**
- The account is pre-seeded with a family, two members, and a sample calendar.

> Setup task for us before submission (see test-plan.md): seed this family in the
> production/`sandbox` project and enable the fixed-code path for this one number.

## Subscriptions
- HomeHuddle offers an auto-renewable subscription via **In-App Purchase**:
  Standard $9.99/month and a limited Founding Family $4.99/month, each with a
  14-day free trial.
- Purchases use StoreKit (via RevenueCat). "Restore Purchases" is on the Account
  screen. There are **no external purchase links** in the iOS app.
- The same account can also be managed on our website with a different payment
  processor; the app never links to it for purchasing.

## Notifications
Optional. The app requests notification permission to remind families about
games/practices; it functions if permission is denied.

## What HomeHuddle does NOT access
No camera, microphone, contacts, photos, or location. Calendar data comes from
schedule feeds the user subscribes to — not the device calendar.

## Account deletion
Account → **Delete account** (in-app, per Guideline 5.1.1(v)). Deletion is
owner-only and completes after a 7-day grace window.
