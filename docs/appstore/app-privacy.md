# App Privacy questionnaire (data inventory)

Tie each answer to what the app actually collects (verified in code).

| Data type | Collected? | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| Phone number | Yes | Yes | No | Account auth (SMS OTP), notifications |
| Email address | Yes | Yes | No | Account, feed identity, receipts |
| Name (parent + family members, incl. children's first names) | Yes | Yes | No | App functionality (family calendar) |
| Coarse/precise location | No | — | — | — |
| Contacts | No | — | — | — |
| Photos/Camera/Mic | No | — | — | — |
| Sports schedule / calendar content | Yes | Yes | No | Core app functionality |
| Device push token | Yes | Yes | No | Notifications (APNs) |
| Purchase history | Yes (via App Store/RevenueCat) | Yes | No | Subscription entitlement |
| Diagnostics / crash + error logs (`client_errors`) | Yes | No* | No | App stability |

\* `client_errors` stores platform/path/message; avoid writing PII into error
messages. `family_id` is optional and only for correlating a failure to an
account when the user is signed in.

**Tracking:** None. Select **"Data is not used to track you."** No ad networks,
no IDFA, no third-party analytics SDKs are present in the build.

## Children's data note
The account holder is an adult (parent). The app stores children's first names
and schedules as family data entered by the parent. HomeHuddle is a general-
audience 4+ app and must **not** enroll in the Kids Category. The privacy policy
(`homehuddle-privacy.html`) must disclose that family/child data is stored and
how deletion works.

## Third-party processors to list in the policy
Supabase (database/auth/functions), Apple (IAP), RevenueCat (subscription
management), SMS provider (OTP), Stripe (web billing only), push/APNs.
