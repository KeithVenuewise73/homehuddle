# Venuewise Core — Smoke Tests (Wave 0 safety net)

These tests are the enforcement mechanism for **"nothing breaks HomeHuddle."** They are **read-only**: they navigate to critical pages and assert the page loads, renders, throws no uncaught JS errors, and (on app pages) initializes the Supabase client. They never log in with a real code, submit a form, or write data — so they are safe to run against production.

## Run
```bash
cd tests
npm install
npm run install:browsers      # one-time: installs Chromium
npm run test:smoke:prod       # runs against https://venuewise.net
```
Target a preview instead:
```bash
BASE_URL=https://<your-preview-url> npm run test:smoke
```

## What it checks
- Every critical page returns HTTP < 400
- Expected content renders (loose substring match, resilient to copy tweaks)
- **No uncaught JavaScript errors on load** (the real regression signal)
- `window.supabase` is present on pages that need it
- The PIN login page renders its inputs (without submitting)

## When to run
- **Before** any promotion to the live branch (baseline green)
- **After** every promotion (confirm still green)
- In CI on every pull request against the live branch

## Extending
As pages migrate to shared engine modules in later waves, add assertions here first (the test is the contract), then migrate the page, then confirm still green. Keep everything read-only unless you deliberately point the suite at a disposable preview + test workspace.
