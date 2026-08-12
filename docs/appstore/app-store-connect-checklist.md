# App Store Connect readiness checklist

Legend: ✅ ready in-repo · 🟡 draft/needs asset · ⛔ blocked on Apple org approval

| Item | State | Notes |
|---|---|---|
| App name | ✅ | Listing: "HomeHuddle Family Calendar"; on-device: HomeHuddle |
| Subtitle | 🟡 | Proposed: "Your family's schedule, finally organized." (from manifest) |
| Bundle ID `com.venuewise.homehuddle` | ✅ | Registered in App Store Connect (Team: Venuewise LLC) |
| SKU | ✅ | `HOMEHUDDLE-IOS-001` (set in ASC) |
| Primary category | 🟡 | Proposed: Productivity (secondary: Sports) |
| Age rating | ✅ | **4+** — no objectionable content. Do NOT enroll in Kids Category |
| Privacy Policy URL | ✅ | https://venuewise.net/homehuddle-privacy.html |
| Terms (EULA) URL | ✅ | https://venuewise.net/homehuddle-terms.html (standard Apple EULA acceptable) |
| Support URL | 🟡 | Need a support **page** (not just mailto). Proposed https://venuewise.net/support.html |
| Marketing URL | ✅ | https://venuewise.net/homehuddle/ |
| App icon 1024×1024 | 🟡 | Source art exists (`HomeHuddle App Logo.png`, `icon-512.png`); export flat 1024 (no alpha) |
| Screenshots (6.7" + 6.5" + iPad if universal) | 🟡 | Capture on a real TestFlight build — do NOT fabricate |
| App Privacy questionnaire | ✅ | See `app-privacy.md` |
| ATT / tracking | ✅ | "Data not used to track you." No IDFA / ad SDKs |
| Sign in with Apple | ✅ | Not required — no third-party IdP (phone OTP only) |
| Subscriptions (StoreKit) | ⛔ | Create products per `revenuecat-setup.md` |
| Subscription terms in metadata | ✅ | $9.99/mo standard; $4.99/mo founding (first 100); 14-day free trial |
| App Review notes + demo access | ✅ | See `app-review-notes.md` |
| Export compliance | 🟡 | Standard HTTPS only → "uses exempt encryption" = Yes/exempt |
| Version / build | ✅ | 1.0.0 / build 1 |

## Version & build strategy
- Marketing version starts `1.0.0`; bump patch for review re-submissions.
- `CFBundleVersion` is a monotonically increasing integer per upload.
- Every web change ships by re-running `mobile: npm run sync` and uploading a new build.
