/* ============================================================================
 * PlayingTime Football — V1 acceptance test (build brief §31)
 *
 * Drives the real application in a real browser, at phone size, through the
 * complete list the brief says V1 must satisfy. Every number asserted here is
 * read back off the screen the parent actually sees.
 *
 * Run:  node playingtime/tests/acceptance.mjs
 * ========================================================================== */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require_ = createRequire(import.meta.url);
const { chromium, devices } = require_('/opt/node22/lib/node_modules/playwright');

const ROOT = normalize(join(fileURLToPath(new URL('.', import.meta.url)), '..', '..'));
const PORT = 8791;
const BASE = `http://127.0.0.1:${PORT}`;

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml'
};

const server = createServer(async (req, res) => {
  try {
    let path = decodeURIComponent(req.url.split('?')[0]);
    if (path.endsWith('/')) path += 'index.html';
    const file = join(ROOT, normalize(path).replace(/^(\.\.[/\\])+/, ''));
    if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' }).end('not found');
  }
});

/* ------------------------------------------------------------ assertions -- */
let passed = 0;
const failures = [];
function check(label, actual, expected) {
  const ok = String(actual) === String(expected);
  if (ok) { passed++; console.log(`  ok   ${label}`); }
  else { failures.push(`${label}\n         expected: ${expected}\n         actual:   ${actual}`);
         console.log(`  FAIL ${label} — expected ${expected}, got ${actual}`); }
}
function checkTrue(label, value) { check(label, !!value, true); }
function step(name) { console.log(`\n# ${name}`); }

/* ------------------------------------------------------------------ run --- */
const consoleErrors = [];
const pageErrors = [];

await new Promise((r) => server.listen(PORT, '127.0.0.1', r));
const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const context = await browser.newContext({ ...devices['Pixel 5'] });
const page = await context.newPage();
page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', (e) => pageErrors.push(String(e)));
const failedRequests = [];
page.on('requestfailed', (r) => failedRequests.push(r.url()));

const text = (sel) => page.textContent(sel).then((t) => (t || '').replace(/\s+/g, ' ').trim());
const tap = async (sel) => { await page.click(sel); await page.waitForTimeout(45); };

try {
  /* ---------------------------------------------------------------------- */
  step('Create an account');
  await page.goto(`${BASE}/playingtime/`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#ob-go');
  await page.fill('#ob-name', 'Keith Herman');
  await page.fill('#ob-email', 'keith@example.com');
  await tap('#ob-go');
  await page.waitForSelector('#af-save');
  checkTrue('account created and routed to add-athlete', await page.isVisible('#af-save'));

  /* ---------------------------------------------------------------------- */
  step('Add an athlete');
  await page.fill('#af-name', 'Dominic Herman');
  await page.fill('#af-num', '24');
  await page.fill('#af-team', 'Lancaster Legends');
  await page.fill('#af-level', 'Varsity Football');
  await page.fill('#af-season', '2026 Season');
  await page.selectOption('#af-pos1', 'LB');
  await page.selectOption('#af-pos2', 'RB');
  await tap('#af-save');
  await page.waitForSelector('#home-start');
  check('home shows the athlete', await text('.ah-name'), 'Dominic Herman');
  checkTrue('home shows jersey number', (await text('.jersey')).includes('24'));
  checkTrue('season panel says there is nothing yet', (await text('.empty')).includes('No completed games yet'));

  /* ---------------------------------------------------------------------- */
  step('Create a football game');
  await tap('#home-start');
  await page.waitForSelector('#gs-start');
  await page.fill('#gs-opp', 'Lancaster');
  await page.fill('#gs-date', '2026-09-11');
  await tap('[data-ha="away"]');
  await page.fill('#gs-loc', 'Memorial Field');
  await tap('#gs-start');
  await page.waitForSelector('#g-next');
  check('game header names the opponent', await text('.game-opponent'), 'at Lancaster');

  /* ---------------------------------------------------------------------- */
  step('Game opens on the right unit, quarter and status');
  check('opens on Defense for a linebacker', await text('#g-units button.on'), 'DEFENSE 0 / 0');
  check('opens on Q1', await text('#g-quarters button.on'), 'Q1');
  check('athlete starts IN', await text('#g-inout-label'), 'PLAYER IN');

  /* ---------------------------------------------------------------------- */
  step('Advance plays with one tap, counting participation automatically');
  for (let i = 0; i < 10; i++) await tap('#g-next');
  check('team plays after 10 taps', await text('#g-team-plays'), '10');
  check('player plays after 10 taps', await text('#g-athlete-plays'), '10');
  check('participation', await text('#g-participation'), '100%');

  /* ---------------------------------------------------------------------- */
  step('Mark the athlete OUT — plays count for the team only');
  await tap('#g-inout');
  check('toggle reads OUT', await text('#g-inout-label'), 'PLAYER OUT');
  for (let i = 0; i < 5; i++) await tap('#g-next');
  check('team plays', await text('#g-team-plays'), '15');
  check('player plays unchanged while OUT', await text('#g-athlete-plays'), '10');
  check('participation recalculated', await text('#g-participation'), '66.7%');
  await page.screenshot({ path: 'playingtime/tests/screens/game-out.png' });

  await tap('#g-inout');
  for (let i = 0; i < 2; i++) await tap('#g-next');
  check('back IN and counting again', await text('#g-athlete-plays'), '12');
  check('team plays', await text('#g-team-plays'), '17');

  /* ---------------------------------------------------------------------- */
  step('Record defensive statistics');
  for (let i = 0; i < 3; i++) await tap('[data-stat="solo_tackle"]');
  await tap('[data-stat="assist_tackle"]');
  await tap('[data-stat="tfl"]');
  await tap('[data-stat="sack"]');
  check('tackle tally on the button', await text('[data-tally="solo_tackle"]'), '3');
  check('sack tally on the button', await text('[data-tally="sack"]'), '1');
  checkTrue('a linebacker is not offered receiving stats', !(await page.isVisible('[data-stat="reception"]')));

  /* ---------------------------------------------------------------------- */
  step('Change quarter without interrupting tracking (§14)');
  await tap('[data-q="Q2"]');
  check('quarter is Q2', await text('#g-quarters button.on'), 'Q2');
  check('counts survive the quarter change', await text('#g-team-plays'), '17');

  /* ---------------------------------------------------------------------- */
  step('Switch to offense — stat buttons follow the position (§8)');
  await tap('[data-unit="offense"]');
  checkTrue('rush button appears', await page.isVisible('[data-stat="rush_att"]'));
  checkTrue('reception button appears for the RB half of LB/RB', await page.isVisible('[data-stat="reception"]'));
  checkTrue('passing stats stay hidden for a non-QB', !(await page.isVisible('[data-stat="pass_complete"]')));
  check('offense counter starts at zero', await text('#g-team-plays'), '0');

  /* ---------------------------------------------------------------------- */
  step('Record offensive statistics with quick yardage entry (§12)');
  for (let i = 0; i < 4; i++) await tap('#g-next');
  await tap('[data-stat="rush_att"]');
  await page.waitForSelector('#sheet.open');
  checkTrue('yardage sheet offers quick values', await page.isVisible('[data-y="5"]'));
  await tap('[data-y="5"]');
  await tap('[data-stat="rush_att"]');
  await tap('[data-y="-2"]');
  await tap('[data-stat="rush_att"]');
  await tap('#y-none');                       // parent did not see the gain
  check('three rushes recorded', await text('[data-tally="rush_att"]'), '3');

  /* custom yardage keypad */
  await tap('[data-stat="reception"]');
  await tap('#y-custom');
  await page.waitForSelector('#k-save');
  await tap('[data-k="1"]');
  await tap('[data-k="8"]');
  await tap('#k-save');
  check('reception recorded from the keypad', await text('[data-tally="reception"]'), '1');

  /* ---------------------------------------------------------------------- */
  step('Record special-teams statistics');
  await tap('[data-unit="special_teams"]');
  for (let i = 0; i < 3; i++) await tap('#g-next');
  await tap('[data-stat="st_tackle"]');
  await tap('[data-stat="kick_return"]');
  await tap('[data-y="15"]');
  check('special teams plays', await text('#g-team-plays'), '3');
  check('special teams tackle', await text('[data-tally="st_tackle"]'), '1');

  /* ---------------------------------------------------------------------- */
  step('Undo a mistake (§13)');
  await tap('[data-stat="st_tackle"]');
  check('mistaken second tackle recorded', await text('[data-tally="st_tackle"]'), '2');
  await tap('#g-undo');
  check('undo removed exactly the last action', await text('[data-tally="st_tackle"]'), '1');
  check('undo did not touch the play count', await text('#g-team-plays'), '3');

  /* ---------------------------------------------------------------------- */
  step('Optional score tracking (§15)');
  await tap('#g-score-btn');
  await page.waitForSelector('[data-side="us"][data-p="6"]');
  await tap('[data-side="us"][data-p="6"]');
  await tap('[data-side="us"][data-p="1"]');
  await tap('[data-side="them"][data-p="3"]');
  await tap('#sc-close');
  check('our score', await text('#g-score-us'), '7');
  check('opponent score', await text('#g-score-them'), '3');

  await page.screenshot({ path: 'playingtime/tests/screens/game.png' });

  /* ---------------------------------------------------------------------- */
  step('Data survives a reload mid-game');
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('#g-next');
  check('still on the live game', await text('.game-opponent'), 'at Lancaster');
  check('special-teams plays persisted', await text('#g-team-plays'), '3');
  check('unit selection persisted', await text('#g-units button.on'), 'SPECIAL TEAMS 3 / 3');

  /* ---------------------------------------------------------------------- */
  step('End the game and read the report (§16, §17)');
  await tap('#g-end');
  await page.waitForSelector('#sheet-yes');
  await tap('#sheet-yes');
  await page.waitForSelector('#rp-card');

  const bigStats = await page.$$eval('#view-report .big-stat b', (els) => els.map((e) => e.textContent.trim()));
  check('report: player plays  (12 def + 4 off + 3 st)', bigStats[0], '19');
  check('report: opportunities (17 def + 4 off + 3 st)', bigStats[1], '24');
  check('report: participation', bigStats[2], '79.2%');

  const report = await text('#view-report .wrap');
  checkTrue('report names the athlete', report.includes('Dominic Herman'));
  checkTrue('report shows the opponent', report.includes('at Lancaster'));
  checkTrue('report breaks participation down by unit', report.includes('Defense') && report.includes('Special Teams'));
  checkTrue('report shows defensive statistics', report.includes('TACKLE') && report.includes('SACK'));
  checkTrue('report shows the rushing yardage that was entered', report.includes('+3 yds'));
  checkTrue('report is honest that one rush has no yardage', report.includes('(2/3 entered)'));
  checkTrue('report shows the final score', report.includes('Final score'));

  await page.screenshot({ path: 'playingtime/tests/screens/report.png', fullPage: true });

  /* ---------------------------------------------------------------------- */
  step('Shareable game card (§21)');
  await tap('#rp-card');
  await page.waitForSelector('#card-img');
  const card = await page.evaluate(() => {
    const img = document.getElementById('card-img');
    return { src: img.src.slice(0, 22), w: img.naturalWidth, h: img.naturalHeight };
  });
  check('card is a rendered PNG', card.src, 'data:image/png;base64,');
  check('card width', card.w, 1080);
  check('card height', card.h, 1350);
  await page.evaluate(() => {
    const img = document.getElementById('card-img');
    const a = document.createElement('canvas');
    a.width = img.naturalWidth; a.height = img.naturalHeight;
    a.getContext('2d').drawImage(img, 0, 0);
    window.__card = a.toDataURL('image/png');
  });
  const cardData = await page.evaluate(() => window.__card);
  await (await import('node:fs/promises')).writeFile(
    'playingtime/tests/screens/gamecard.png',
    Buffer.from(cardData.split(',')[1], 'base64')
  );
  await tap('#card-close');

  /* ---------------------------------------------------------------------- */
  step('Game history and returning later (§19)');
  await tap('#rp-back');
  await page.waitForTimeout(120);
  await page.goto(`${BASE}/playingtime/#/history`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#view-history [data-game]');
  const historyText = await text('#view-history .wrap');
  checkTrue('history lists the game', historyText.includes('at Lancaster'));
  checkTrue('history shows plays', historyText.includes('19 plays'));
  checkTrue('history shows tackles', historyText.includes('4 tackles'));
  checkTrue('history groups by season', historyText.includes('2026 Season'));

  await tap('#view-history [data-game]');
  await page.waitForSelector('#rp-card');
  checkTrue('tapping a game opens its full report', (await text('#view-report .wrap')).includes('Dominic Herman'));

  /* ---------------------------------------------------------------------- */
  step('Season totals and participation on the athlete profile (§18, §20)');
  await page.goto(`${BASE}/playingtime/#/athlete`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#at-edit');
  const seasonStats = await page.$$eval('#view-athlete .big-stat b', (els) => els.map((e) => e.textContent.trim()));
  check('season: games played', seasonStats[0], '1');
  check('season: total plays', seasonStats[1], '19');
  check('season: participation', seasonStats[2], '79.2%');
  const profile = await text('#view-athlete .wrap');
  checkTrue('profile shows team and position', profile.includes('Lancaster Legends') && profile.includes('LB / RB'));
  checkTrue('profile shows season statistics', profile.includes('TACKLE'));

  await page.goto(`${BASE}/playingtime/#/home`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#home-start');
  const home = await text('#view-home .wrap');
  checkTrue('home shows the season summary', home.includes('2026 Season so far'));
  checkTrue('home shows participation', home.includes('79.2%'));
  await page.screenshot({ path: 'playingtime/tests/screens/home.png', fullPage: true });

  /* ---------------------------------------------------------------------- */
  step('Settings tells the truth about where the data lives');
  await page.goto(`${BASE}/playingtime/#/settings`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#st-export');
  const settings = await text('#view-settings .wrap');
  checkTrue('settings says data is device-only', settings.includes('Your data is on this device only'));
  checkTrue('settings explains why sync is off', settings.includes('has not been applied to any database'));
  checkTrue('settings reports the real footprint', /1 game, \d+ recorded actions/.test(settings));
  checkTrue('settings carries the attribution', settings.includes('Venuewise') && settings.includes('Herman Legacy Digital'));
  checkTrue('there is no cloud-sync button that would do nothing', !(await page.isVisible('text=Sync now')));
  await page.screenshot({ path: 'playingtime/tests/screens/settings.png', fullPage: true });

  /* ---------------------------------------------------------------------- */
  step('Starting a second game and returning to previous ones');
  await page.goto(`${BASE}/playingtime/#/game-setup`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#gs-start');
  await page.fill('#gs-opp', 'Orchard Park');
  await page.fill('#gs-date', '2026-09-18');
  await tap('#gs-start');
  await page.waitForSelector('#g-next');
  for (let i = 0; i < 6; i++) await tap('#g-next');
  check('the new game starts from zero', await text('#g-team-plays'), '6');

  await page.goto(`${BASE}/playingtime/#/history`, { waitUntil: 'networkidle' });
  await page.waitForSelector('#view-history [data-game]');
  const twoGames = await page.$$eval('#view-history [data-game]', (els) => els.length);
  check('history holds both games', twoGames, 2);
  checkTrue('the live game is marked as such', (await text('#view-history .wrap')).includes('Live'));

  /* ---------------------------------------------------------------------- */
  step('No JavaScript errors anywhere in that run');
  check('page errors', pageErrors.length, 0);
  if (pageErrors.length) console.log(pageErrors.join('\n'));
  /* Only this app's own resources are in scope. Google Fonts is a progressive
   * enhancement with a full fallback stack, and this sandbox has no route to it. */
  const ownFailures = failedRequests.filter((u) => u.startsWith(BASE));
  check('no app resource failed to load', ownFailures.length, 0);
  if (ownFailures.length) console.log(ownFailures.join('\n'));
  const offsite = failedRequests.filter((u) => !u.startsWith(BASE));
  if (offsite.length) {
    console.log(`  note  ${offsite.length} off-site request(s) blocked by this sandbox `
      + `(${[...new Set(offsite.map((u) => new URL(u).host))].join(', ')}) — the app has font fallbacks and renders without them.`);
  }
} finally {
  await browser.close();
  server.close();
}

console.log(`\n${'─'.repeat(64)}`);
if (failures.length) {
  console.log(`FAILED — ${passed} passed, ${failures.length} failed\n`);
  failures.forEach((f) => console.log(`  ✗ ${f}`));
  process.exit(1);
}
console.log(`PASSED — ${passed} acceptance checks, 0 failures`);
