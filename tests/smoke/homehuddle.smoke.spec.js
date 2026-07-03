// ─────────────────────────────────────────────────────────────────────────────
// Venuewise Core — HomeHuddle production smoke tests
// READ-ONLY. These tests only navigate and assert page health. They never log in
// with a real code, submit a form, or write any data. Safe to run against prod.
//
// Purpose: the safety net for Wave 0+. Run before and after every promotion to
// confirm HomeHuddle still works exactly as it did.
//
// Usage:
//   BASE_URL=https://venuewise.net npx playwright test
// ─────────────────────────────────────────────────────────────────────────────

const { test, expect } = require('@playwright/test');

const BASE = process.env.BASE_URL || 'https://venuewise.net';

// Critical pages, discovered from the live repo. `mustContain` is a case-insensitive
// substring expected somewhere in the rendered page; keep these loose/resilient so a
// copy tweak doesn't fail the smoke test — the point is "page loads and renders", not
// pixel-level assertions.
const PAGES = [
  { path: '/',                          name: 'Landing (index)',        mustContain: 'huddle' },
  { path: '/calendar.html',             name: 'Family calendar',        mustContain: 'calendar' },
  { path: '/login.html',                name: 'PIN login',              mustContain: 'pin' },
  { path: '/join.html',                 name: 'Join / signup',          mustContain: 'huddle' },
  { path: '/account.html',              name: 'Account',                mustContain: 'account' },
  { path: '/homehuddle/',               name: 'HomeHuddle app home',    mustContain: 'huddle' },
  { path: '/homehuddle/calendar.html',  name: 'HomeHuddle calendar',    mustContain: 'calendar' },
  { path: '/coacheshuddle/',            name: 'CoachesHuddle',          mustContain: 'coach' },
  { path: '/facilityhuddle/',           name: 'FacilityHuddle',         mustContain: 'facility' },
  { path: '/organizationhuddle/',       name: 'OrganizationHuddle',     mustContain: 'organization' },
];

// Pages that create a Supabase client inline — assert the client library loaded.
const SUPABASE_PAGES = ['/calendar.html', '/login.html', '/account.html', '/homehuddle/calendar.html'];

for (const p of PAGES) {
  test(`loads: ${p.name} (${p.path})`, async ({ page }) => {
    const consoleErrors = [];
    page.on('console', (msg) => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
    const pageErrors = [];
    page.on('pageerror', (err) => pageErrors.push(String(err)));

    const resp = await page.goto(BASE + p.path, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // 1. HTTP is healthy
    expect(resp, `no response for ${p.path}`).toBeTruthy();
    expect(resp.status(), `bad status for ${p.path}`).toBeLessThan(400);

    // 2. Rendered content is present
    const body = (await page.textContent('body')) || '';
    expect(body.toLowerCase(), `"${p.mustContain}" not found on ${p.path}`).toContain(p.mustContain);

    // 3. No uncaught JS errors on load (this is the real regression signal)
    expect(pageErrors, `uncaught JS errors on ${p.path}:\n${pageErrors.join('\n')}`).toHaveLength(0);

    // 4. Supabase client available where expected
    if (SUPABASE_PAGES.includes(p.path)) {
      const hasSupabase = await page.evaluate(() => typeof window.supabase !== 'undefined');
      expect(hasSupabase, `window.supabase missing on ${p.path}`).toBeTruthy();
    }
  });
}

// A dedicated check that the PIN login page renders its inputs but we do NOT submit.
test('PIN login renders inputs (no submission)', async ({ page }) => {
  await page.goto(BASE + '/login.html', { waitUntil: 'domcontentloaded' });
  const emailInputs = await page.locator('input[type="email"], input#email').count();
  expect(emailInputs, 'expected an email input on the login page').toBeGreaterThan(0);
});
