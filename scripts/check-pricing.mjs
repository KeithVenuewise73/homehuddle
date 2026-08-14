#!/usr/bin/env node
// ============================================================================
// check-pricing.mjs — launch guard. Fails if forbidden pricing/trial strings or
// obvious secrets appear in ACTIVE HomeHuddle files. Runs locally, no network.
//   node scripts/check-pricing.mjs
// ============================================================================
import { readFileSync } from 'node:fs';

const ACTIVE = [
  'index.html', 'join.html', 'account.html', 'terms.html', 'privacy.html',
  'homehuddle/index.html', 'homehuddle/join.html', 'homehuddle/account.html',
  'homehuddle/calendar.html', 'homehuddle/login.html',
];

// Forbidden customer-facing strings (locked model: $9.99 standard / $4.99 founding / 14-day).
const FORBIDDEN = [
  { re: /\$4\.95/g, why: 'obsolete $4.95 price' },
  { re: /30[-\s]?day (free )?trial/gi, why: 'obsolete 30-day trial' },
  { re: /first 150/gi, why: 'obsolete founder cap (should be 100)' },
];

// Secrets that must NEVER be in client files.
const SECRETS = [
  { re: /service_role/g, why: 'service_role key/reference' },
  { re: /sk_live_[0-9a-zA-Z]+/g, why: 'Stripe secret key' },
  { re: /sk_test_[0-9a-zA-Z]+/g, why: 'Stripe test secret key' },
  { re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/g, why: 'private key' },
];

let failures = 0;
for (const f of ACTIVE) {
  let txt;
  try { txt = readFileSync(f, 'utf8'); } catch { continue; }
  for (const { re, why } of [...FORBIDDEN, ...SECRETS]) {
    const m = txt.match(re);
    if (m) { console.error(`✗ ${f}: ${why} (${m.length}x): ${m[0]}`); failures += m.length; }
  }
}

if (failures) { console.error(`\nFAILED: ${failures} issue(s).`); process.exit(1); }
console.log(`✓ pricing/secret guard passed across ${ACTIVE.length} active files.`);
