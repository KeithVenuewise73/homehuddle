/* ============================================================================
 * PlayingTime Football — app.js
 * Views, routing and the live game screen.
 *
 * The game screen is built once and then updated in place. A parent taps NEXT
 * PLAY sixty times a game; re-rendering the screen on each tap would put a
 * visible stutter between the tap and the count, and the whole product promise
 * is that the tap is instant and the eyes go straight back to the field (§35).
 * ========================================================================== */

import {
  UNITS, QUARTERS, POSITIONS, STATS_BY_ID,
  statsForUnit, defaultUnitFor, unitLabel
} from './catalog.js';
import { deriveGame, deriveSeason, statLines } from './engine.js';
import * as store from './store.js';
import * as sync from './sync.js';
import { drawShareCard } from './sharecard.js';

/* ------------------------------------------------------------- utilities -- */
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

/** Escape anything that came from a person before it reaches innerHTML. */
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function pct(n) { return `${Number(n).toFixed(1).replace(/\.0$/, '')}%`; }

function formatDate(iso) {
  if (!iso) return '';
  const d = new Date(`${String(iso).slice(0, 10)}T12:00:00`);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

function vsLine(game) {
  return `${game.homeAway === 'away' ? 'at' : 'vs'} ${game.opponent || 'Opponent'}`;
}

/** Short haptic on a recorded tap, where the device supports it. */
function buzz(ms = 12) {
  try { if (navigator.vibrate) navigator.vibrate(ms); } catch { /* not supported */ }
}

let toastTimer = null;
function toast(message, kind = '') {
  const el = $('#toast');
  el.textContent = message;
  el.className = `toast show ${kind}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.className = 'toast'; }, 1700);
}

/* ---------------------------------------------------------------- sheets -- */
function openSheet(html) {
  const backdrop = $('#sheet');
  backdrop.innerHTML = `<div class="sheet" role="dialog" aria-modal="true">${html}</div>`;
  backdrop.classList.add('open');
}
function closeSheet() {
  const backdrop = $('#sheet');
  backdrop.classList.remove('open');
  backdrop.innerHTML = '';
}

/**
 * Confirmation for anything that destroys work. Ending a game, deleting a game
 * and clearing all data each go through this — none of them is reversible.
 */
function confirmSheet({ title, body, confirmLabel, danger = true, onConfirm }) {
  openSheet(`
    <div class="sheet-title">${esc(title)}</div>
    <div class="sheet-sub">${esc(body)}</div>
    <button class="btn ${danger ? 'btn-danger' : 'btn-primary'} btn-lg" id="sheet-yes">${esc(confirmLabel)}</button>
    <button class="btn btn-ghost" id="sheet-no">Cancel</button>
  `);
  $('#sheet-yes').onclick = () => { closeSheet(); onConfirm(); };
  $('#sheet-no').onclick = closeSheet;
}

/* ================================================================ router == */
const ROUTES = ['home', 'game', 'athlete', 'history', 'settings', 'onboard', 'athlete-new', 'game-setup', 'report'];
const NAV_VIEWS = ['home', 'game', 'athlete', 'history', 'settings'];

let route = { name: 'home', arg: null };

function go(name, arg) {
  location.hash = arg ? `#/${name}/${arg}` : `#/${name}`;
}

function parseHash() {
  const raw = location.hash.replace(/^#\/?/, '');
  const [name, arg] = raw.split('/');
  if (!name || !ROUTES.includes(name)) return { name: 'home', arg: null };
  return { name, arg: arg || null };
}

function render() {
  route = parseHash();

  /* Nothing works without an account and an athlete, so the app routes there
   * itself rather than showing empty screens with dead buttons. */
  if (!store.getAccount() && route.name !== 'onboard') { go('onboard'); return; }
  if (store.getAccount() && store.listAthletes().length === 0
      && !['athlete-new', 'onboard', 'settings'].includes(route.name)) {
    go('athlete-new'); return;
  }

  $$('.view').forEach((v) => v.classList.remove('active'));
  const view = $(`#view-${route.name}`);
  if (!view) { go('home'); return; }
  view.classList.add('active');

  const showNav = NAV_VIEWS.includes(route.name) && route.name !== 'game';
  $('#nav').style.display = showNav ? 'flex' : 'none';
  $$('#nav button').forEach((b) => b.classList.toggle('on', b.dataset.nav === route.name));

  const renderers = {
    onboard: renderOnboard,
    'athlete-new': renderAthleteForm,
    home: renderHome,
    'game-setup': renderGameSetup,
    game: renderGame,
    report: renderReport,
    athlete: renderAthlete,
    history: renderHistory,
    settings: renderSettings
  };
  renderers[route.name]();

  /* Scroll views start at the top; the game screen manages its own scrolling. */
  const scroller = $('.scroll', view);
  if (scroller && route.name !== 'game') scroller.scrollTop = 0;
}

/* =============================================================== onboard == */
function renderOnboard() {
  $('#view-onboard .scroll').innerHTML = `
    <div class="wrap">
      <div class="brand" style="margin:26px 0 22px">
        <div class="brand-mark">PT</div>
        <div>
          <div class="brand-name">PlayingTime <span style="color:var(--text-faint);font-weight:500">Football</span></div>
          <div class="brand-by">Powered by Venuewise</div>
        </div>
      </div>

      <h2 style="font-family:var(--font-display);font-size:27px;line-height:1.25;margin-bottom:10px">
        Know exactly how much your athlete played.
      </h2>
      <p style="color:var(--text-dim);font-size:15px;line-height:1.6;margin-bottom:24px">
        Tap once per play. PlayingTime counts your athlete's snaps, works out their
        participation percentage and keeps their statistics — for the game and the season.
      </p>

      <div class="card">
        <div class="card-title">Create your account</div>
        <div class="err" id="onboard-err"></div>
        <div class="field">
          <label for="ob-name">Your name</label>
          <input id="ob-name" autocomplete="name" placeholder="Keith Herman" />
        </div>
        <div class="field">
          <label for="ob-email">Email</label>
          <input id="ob-email" type="email" autocomplete="email" inputmode="email" placeholder="you@example.com" />
        </div>
        <div class="field">
          <label for="ob-phone">Phone <span style="color:var(--text-faint)">(optional)</span></label>
          <input id="ob-phone" type="tel" autocomplete="tel" inputmode="tel" placeholder="716-555-0142" />
        </div>
        <button class="btn btn-primary btn-lg" id="ob-go">Continue</button>
      </div>

      <div class="notice">
        <b>This account lives on this device</b>
        PlayingTime V1 stores everything locally so it keeps working when the stadium
        has no signal. There is no password yet because there is no server yet — see
        Settings for exactly what that means and how to keep a backup.
      </div>

      <div class="footer-brand">
        <b>PlayingTime Football</b><br />
        Powered by Venuewise · Built by Herman Legacy Digital
      </div>
    </div>
  `;

  $('#ob-go').onclick = () => {
    const name = $('#ob-name').value.trim();
    const email = $('#ob-email').value.trim();
    if (!name) { $('#onboard-err').textContent = 'Please enter your name.'; return; }
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      $('#onboard-err').textContent = 'Please enter a valid email address.'; return;
    }
    if (!store.storageAvailable()) {
      $('#onboard-err').textContent =
        'This browser is blocking local storage, so PlayingTime cannot save anything. ' +
        'Turn off private browsing, or allow site data, and try again.';
      return;
    }
    store.saveAccount({ name, email, phone: $('#ob-phone').value.trim() });
    go('athlete-new');
  };
}

/* ========================================================= athlete form == */
function positionOptions(selected, includeBlank) {
  const blank = includeBlank ? '<option value="">— none —</option>' : '';
  return blank + POSITIONS.map(
    (p) => `<option value="${p.id}"${p.id === selected ? ' selected' : ''}>${esc(p.label)}</option>`
  ).join('');
}

function renderAthleteForm() {
  const editing = route.arg ? store.getAthlete(route.arg) : null;
  const a = editing || {};
  const thisYear = new Date().getFullYear();

  $('#view-athlete-new .scroll').innerHTML = `
    <div class="wrap">
      <h2 style="font-family:var(--font-display);font-size:25px;margin:14px 0 6px">
        ${editing ? 'Edit athlete' : 'Add your athlete'}
      </h2>
      <p style="color:var(--text-dim);font-size:14px;margin-bottom:20px">
        ${editing ? 'Changes apply to every game for this athlete.'
                  : 'The position decides which stat buttons you see during a game.'}
      </p>

      <div class="card">
        <div class="err" id="ath-err"></div>
        <div class="field">
          <label for="af-name">Player name</label>
          <input id="af-name" value="${esc(a.name || '')}" placeholder="Dominic Herman" />
        </div>
        <div class="field-row">
          <div class="field">
            <label for="af-num">Jersey number</label>
            <input id="af-num" inputmode="numeric" value="${esc(a.jerseyNumber || '')}" placeholder="24" />
          </div>
          <div class="field">
            <label for="af-season">Season</label>
            <input id="af-season" value="${esc(a.season || `${thisYear} Season`)}" placeholder="${thisYear} Season" />
          </div>
        </div>
        <div class="field">
          <label for="af-team">Team</label>
          <input id="af-team" value="${esc(a.team || '')}" placeholder="Lancaster Legends" />
        </div>
        <div class="field">
          <label for="af-level">Level</label>
          <input id="af-level" value="${esc(a.level || '')}" placeholder="Varsity Football" />
        </div>
        <div class="field">
          <label for="af-pos1">Primary position</label>
          <select id="af-pos1">${positionOptions(a.primaryPosition || 'LB', false)}</select>
        </div>
        <div class="field">
          <label for="af-pos2">Secondary position <span style="color:var(--text-faint)">(optional)</span></label>
          <select id="af-pos2">${positionOptions(a.secondaryPosition || '', true)}</select>
          <div class="hint">Both positions' stat buttons appear during a game.</div>
        </div>
        <button class="btn btn-primary btn-lg" id="af-save">${editing ? 'Save changes' : 'Add athlete'}</button>
        ${editing ? '<button class="btn btn-ghost" id="af-cancel">Cancel</button>' : ''}
      </div>
      ${editing ? `
      <div class="card">
        <div class="card-title">Danger zone</div>
        <button class="btn btn-danger" id="af-delete">Delete this athlete and their games</button>
      </div>` : ''}
    </div>
  `;

  $('#af-save').onclick = () => {
    const name = $('#af-name').value.trim();
    if (!name) { $('#ath-err').textContent = 'Please enter the player name.'; return; }
    const pos1 = $('#af-pos1').value;
    const pos2 = $('#af-pos2').value;
    if (pos2 && pos2 === pos1) {
      $('#ath-err').textContent = 'Pick a different secondary position, or leave it as none.'; return;
    }
    const saved = store.saveAthlete({
      id: editing ? editing.id : undefined,
      name,
      jerseyNumber: $('#af-num').value,
      team: $('#af-team').value,
      level: $('#af-level').value,
      season: $('#af-season').value,
      primaryPosition: pos1,
      secondaryPosition: pos2
    });
    store.setActiveAthlete(saved.id);
    go(editing ? 'athlete' : 'home');
  };

  if (editing) {
    $('#af-cancel').onclick = () => go('athlete');
    $('#af-delete').onclick = () => confirmSheet({
      title: `Delete ${editing.name}?`,
      body: 'Every game and every play recorded for this athlete is deleted from this device. This cannot be undone.',
      confirmLabel: 'Delete athlete',
      onConfirm: () => {
        const { deletedGames } = store.deleteAthlete(editing.id);
        toast(`Deleted athlete and ${deletedGames} game${deletedGames === 1 ? '' : 's'}`);
        go('home');
      }
    });
  }
}

/* ================================================================== home == */
function renderHome() {
  const athlete = store.activeAthlete();
  const games = store.listGames(athlete.id);
  const finals = games.filter((g) => g.status === store.GAME_STATUS.FINAL);
  const live = games.find((g) => g.status === store.GAME_STATUS.IN_PROGRESS);

  const eventsByGame = {};
  for (const g of finals) eventsByGame[g.id] = store.getEvents(g.id);
  const season = deriveSeason(finals, eventsByGame);

  const others = store.listAthletes().filter((a) => a.id !== athlete.id);

  $('#view-home .scroll').innerHTML = `
    <div class="wrap">
      <div class="athlete-hero">
        <div class="jersey">${athlete.jerseyNumber ? `#${esc(athlete.jerseyNumber)}` : esc((athlete.name || '?').slice(0, 1))}</div>
        <div style="min-width:0">
          <div class="ah-name">${esc(athlete.name)}</div>
          <div class="ah-sub">
            ${esc([athlete.team, athlete.level].filter(Boolean).join(' · ') || 'No team set')}<br />
            ${esc([athlete.primaryPosition, athlete.secondaryPosition].filter(Boolean).join(' / '))}
            ${athlete.season ? ` · ${esc(athlete.season)}` : ''}
          </div>
        </div>
      </div>

      ${live ? `
        <button class="btn btn-primary btn-lg" id="home-resume" style="margin-bottom:12px">
          Resume ${esc(vsLine(live))}
        </button>
        <p style="font-size:12.5px;color:var(--text-dim);text-align:center;margin:-4px 0 16px">
          A game is still being tracked.
        </p>
      ` : `
        <button class="btn btn-primary btn-lg" id="home-start" style="margin-bottom:18px">
          Start new game
        </button>
      `}

      ${season.gamesPlayed === 0 ? `
        <div class="empty">
          <strong>No completed games yet</strong>
          Season totals appear here once you finish tracking a game. Nothing is
          estimated — this stays empty until there is something real to show.
        </div>
      ` : `
        <div class="card-title" style="margin-top:6px">${esc(athlete.season || 'Season')} so far</div>
        <div class="big-stats">
          <div class="big-stat"><b>${season.gamesPlayed}</b><span>Games</span></div>
          <div class="big-stat"><b>${season.totals.athletePlays}</b><span>Plays</span></div>
          <div class="big-stat"><b>${pct(season.totals.participation)}</b><span>Participation</span></div>
        </div>
        <div class="card">
          <div class="card-title">Season statistics</div>
          ${renderStatLines(season.stats, null) || '<div class="card-note">No statistics recorded yet.</div>'}
        </div>
      `}

      ${finals.length ? `
        <div class="card-title" style="margin-top:4px">Recent games</div>
        ${finals.slice(0, 3).map((g) => gameItemHTML(g, eventsByGame[g.id])).join('')}
        ${finals.length > 3 ? '<button class="btn btn-ghost" id="home-all">See all games</button>' : ''}
      ` : ''}

      ${others.length ? `
        <div class="card" style="margin-top:14px">
          <div class="card-title">Switch athlete</div>
          ${others.map((o) => `
            <button class="btn btn-ghost" data-switch="${o.id}" style="margin-bottom:8px">
              ${esc(o.name)}${o.jerseyNumber ? ` · #${esc(o.jerseyNumber)}` : ''}
            </button>`).join('')}
        </div>` : ''}

      <div class="footer-brand">
        <b>PlayingTime Football</b><br />
        Powered by Venuewise · Built by Herman Legacy Digital
      </div>
    </div>
  `;

  if (live) $('#home-resume').onclick = () => go('game', live.id);
  else $('#home-start').onclick = () => go('game-setup');
  const all = $('#home-all');
  if (all) all.onclick = () => go('history');
  $$('[data-switch]').forEach((b) => {
    b.onclick = () => { store.setActiveAthlete(b.dataset.switch); render(); };
  });
}

function gameItemHTML(game, events) {
  const d = deriveGame(events || []);
  const isLive = game.status === store.GAME_STATUS.IN_PROGRESS;
  return `
    <button class="game-item" data-game="${game.id}">
      <div class="gi-main">
        <div class="gi-op">${esc(vsLine(game))}
          ${isLive ? '<span class="pill pill-live" style="margin-left:6px">Live</span>' : ''}</div>
        <div class="gi-sub">${esc(formatDate(game.date))} · ${d.totals.athletePlays} plays${
          d.derived.tackles ? ` · ${d.derived.tackles} tackles` : ''}</div>
      </div>
      <div class="gi-pct">
        <b>${d.totals.teamPlays ? pct(d.totals.participation) : '—'}</b>
        <span>Participation</span>
      </div>
    </button>
  `;
}

/** Non-zero stat lines, grouped by section heading. Zeroes are noise. */
function renderStatLines(stats, unitId) {
  const lines = statLines(stats, unitId);
  if (!lines.length) return '';
  const groups = [];
  for (const line of lines) {
    let g = groups.find((x) => x.name === line.group);
    if (!g) { g = { name: line.group, lines: [] }; groups.push(g); }
    g.lines.push(line);
  }
  return groups.map((g) => `
    <div style="margin-bottom:14px">
      <div style="font-size:11.5px;font-weight:700;color:var(--text-faint);text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px">${esc(g.name)}</div>
      ${g.lines.map((l) => `
        <div class="stat-row">
          <span class="n">${l.count}</span>
          <span class="l">${esc(l.label)}</span>
          ${l.yards !== null ? `<span class="x">${l.yards >= 0 ? '+' : ''}${l.yards} yds${
            l.yardsPartial ? ` <span style="color:var(--text-faint)">(${l.yardsKnown}/${l.count} entered)</span>` : ''}</span>` : ''}
        </div>`).join('')}
    </div>
  `).join('');
}

/* =========================================================== game setup == */
function renderGameSetup() {
  const athletes = store.listAthletes();
  const active = store.activeAthlete();
  const today = new Date().toISOString().slice(0, 10);

  $('#view-game-setup .scroll').innerHTML = `
    <div class="wrap">
      <h2 style="font-family:var(--font-display);font-size:25px;margin:14px 0 18px">New game</h2>
      <div class="card">
        <div class="err" id="gs-err"></div>
        ${athletes.length > 1 ? `
          <div class="field">
            <label for="gs-athlete">Athlete</label>
            <select id="gs-athlete">
              ${athletes.map((a) => `<option value="${a.id}"${a.id === active.id ? ' selected' : ''}>${esc(a.name)}${a.jerseyNumber ? ` · #${esc(a.jerseyNumber)}` : ''}</option>`).join('')}
            </select>
          </div>` : ''}
        <div class="field">
          <label for="gs-opp">Opponent</label>
          <input id="gs-opp" placeholder="Lancaster" />
        </div>
        <div class="field">
          <label for="gs-date">Date</label>
          <input id="gs-date" type="date" value="${today}" />
        </div>
        <div class="field">
          <label>Home or away</label>
          <div class="segment" id="gs-ha">
            <button data-ha="home" class="on">Home</button>
            <button data-ha="away">Away</button>
          </div>
        </div>
        <div class="field">
          <label for="gs-loc">Location <span style="color:var(--text-faint)">(optional)</span></label>
          <input id="gs-loc" placeholder="Memorial Field" />
        </div>
        <button class="btn btn-primary btn-lg" id="gs-start">Start game</button>
        <button class="btn btn-ghost" id="gs-cancel">Cancel</button>
      </div>
    </div>
  `;

  let homeAway = 'home';
  $$('#gs-ha button').forEach((b) => {
    b.onclick = () => {
      homeAway = b.dataset.ha;
      $$('#gs-ha button').forEach((x) => x.classList.toggle('on', x === b));
    };
  });

  $('#gs-cancel').onclick = () => go('home');
  $('#gs-start').onclick = () => {
    const opponent = $('#gs-opp').value.trim();
    if (!opponent) { $('#gs-err').textContent = 'Who are you playing?'; return; }

    /* One game at a time. Two live games would make "resume" ambiguous and let a
     * parent record plays against the wrong game without noticing. */
    const existing = store.inProgressGame();
    if (existing) {
      $('#gs-err').textContent =
        `A game (${vsLine(existing)}) is still being tracked. Finish it from the game screen first.`;
      return;
    }

    const athleteId = athletes.length > 1 ? $('#gs-athlete').value : active.id;
    const game = store.createGame({
      athleteId,
      opponent,
      date: $('#gs-date').value || today,
      homeAway,
      location: $('#gs-loc').value
    });
    store.setActiveAthlete(athleteId);
    go('game', game.id);
  };
}

/* ============================================================ live game == */
/* Everything the game screen needs, held in one place and refreshed in place. */
let live = null;

function renderGame() {
  const game = route.arg ? store.getGame(route.arg) : store.inProgressGame();
  if (!game) { go('home'); return; }
  if (game.status === store.GAME_STATUS.FINAL) { go('report', game.id); return; }

  const athlete = store.getAthlete(game.athleteId);
  if (!athlete) { go('home'); return; }

  const positions = store.athletePositions(athlete);
  const state = store.getGameState(game.id);
  if (!state.unit) state.unit = defaultUnitFor(positions);

  live = { game, athlete, positions, state, events: store.getEvents(game.id) };

  $('#view-game').innerHTML = `
    <div class="game">
      <div class="game-head">
        <button class="iconbtn" id="g-menu" aria-label="Game menu">☰</button>
        <div class="game-head-main">
          <div class="game-opponent">${esc(vsLine(game))}</div>
          <div class="game-meta">${esc(athlete.name)}${athlete.jerseyNumber ? ` · #${esc(athlete.jerseyNumber)}` : ''} · ${esc(formatDate(game.date))}</div>
        </div>
        <button class="game-score" id="g-score" aria-label="Score">
          <b id="g-score-us">0</b><span>–</span><b id="g-score-them">0</b>
        </button>
      </div>

      <div class="quarters" id="g-quarters" role="group" aria-label="Quarter">
        ${QUARTERS.map((q) => `<button data-q="${q}">${q}</button>`).join('')}
      </div>

      <div class="units" id="g-units" role="group" aria-label="Unit on the field">
        ${UNITS.map((u) => `
          <button data-unit="${u.id}">
            ${esc(u.label.toUpperCase())}
            <span class="u-count" data-ucount="${u.id}">0 / 0</span>
          </button>`).join('')}
      </div>

      <button class="inout" id="g-inout" aria-label="Toggle whether the athlete is on the field">
        <span class="dot"></span>
        <span class="stack">
          <span class="label" id="g-inout-label">PLAYER IN</span>
          <span class="who">${esc(athlete.name.split(' ')[0])} is on the field</span>
        </span>
        <span class="switch">Tap to change</span>
      </button>

      <div class="counts">
        <div class="count"><b id="g-team-plays">0</b><span>Team plays</span></div>
        <div class="count hero"><b id="g-athlete-plays">0</b><span>Player plays</span></div>
        <div class="count"><b id="g-participation">0%</b><span>Participation</span></div>
      </div>

      <div class="stats-area">
        <div class="stat-grid" id="g-stats"></div>
      </div>

      <div class="game-foot">
        <button class="nextplay" id="g-next">NEXT PLAY</button>
        <div class="foot-row">
          <button class="undo" id="g-undo">↶ Undo</button>
          <button id="g-score-btn">Score</button>
          <button id="g-end">End game</button>
        </div>
      </div>
    </div>
  `;

  /* --- wiring, once --- */
  $('#g-menu').onclick = gameMenu;
  $('#g-next').onclick = tapNextPlay;
  $('#g-undo').onclick = tapUndo;
  $('#g-inout').onclick = toggleInOut;
  $('#g-score-btn').onclick = openScoreSheet;
  $('#g-score').onclick = openScoreSheet;
  $('#g-end').onclick = confirmEndGame;

  $$('#g-quarters button').forEach((b) => {
    b.onclick = () => {
      live.state = store.setGameState(live.game.id, { quarter: b.dataset.q });
      paintChrome();
      toast(`Quarter ${b.dataset.q}`);
    };
  });
  $$('#g-units button').forEach((b) => {
    b.onclick = () => {
      live.state = store.setGameState(live.game.id, { unit: b.dataset.unit });
      paintChrome();
      paintStatButtons();
      paintCounts();
    };
  });

  paintChrome();
  paintStatButtons();
  paintCounts();
}

/** Quarter / unit / IN-OUT selection state. */
function paintChrome() {
  const { state, athlete } = live;
  $$('#g-quarters button').forEach((b) => b.classList.toggle('on', b.dataset.q === state.quarter));
  $$('#g-units button').forEach((b) => b.classList.toggle('on', b.dataset.unit === state.unit));

  const inout = $('#g-inout');
  inout.className = `inout ${state.athleteIn ? 'in' : 'out'}`;
  $('#g-inout-label').textContent = state.athleteIn ? 'PLAYER IN' : 'PLAYER OUT';
  $('.who', inout).textContent = state.athleteIn
    ? `${athlete.name.split(' ')[0]} is on the field`
    : `${athlete.name.split(' ')[0]} is off the field — plays will not count`;
}

/** The stat buttons for the current unit and the athlete's positions (§8). */
function paintStatButtons() {
  const stats = statsForUnit(live.state.unit, live.positions);
  $('#g-stats').innerHTML = stats.map((s) => `
    <button class="stat-btn ${s.tone === 'bad' ? 'bad' : ''}" data-stat="${s.id}">
      <span class="tally" data-tally="${s.id}"></span>
      ${esc(s.label)}
      ${s.yardage ? '<span class="yd">+ YARDS</span>' : ''}
    </button>
  `).join('');
  $$('#g-stats [data-stat]').forEach((b) => { b.onclick = () => tapStat(b.dataset.stat); });
}

/** Every number on the game screen, recomputed from the log. */
function paintCounts() {
  const d = deriveGame(live.events);
  const unit = d.units[live.state.unit];

  $('#g-team-plays').textContent = unit.teamPlays;
  $('#g-athlete-plays').textContent = unit.athletePlays;
  $('#g-participation').textContent = unit.teamPlays ? pct(unit.participation) : '—';

  for (const u of UNITS) {
    const el = $(`[data-ucount="${u.id}"]`);
    if (el) el.textContent = `${d.units[u.id].athletePlays} / ${d.units[u.id].teamPlays}`;
  }

  $('#g-score-us').textContent = d.score.us;
  $('#g-score-them').textContent = d.score.them;

  /* Per-button running tallies: the parent can check a number without leaving
   * the game screen, which is the whole reason the tally lives on the button. */
  $$('#g-stats [data-tally]').forEach((el) => {
    const tally = d.stats[el.dataset.tally];
    el.textContent = tally && tally.count ? tally.count : '';
  });

  $('#g-undo').disabled = live.events.length === 0;
}

/**
 * A tap that could not be saved must not look like one that was. Every recording
 * path goes through here so a full or blocked storage surfaces immediately
 * rather than silently dropping a play.
 */
function afterRecord(stored, message) {
  if (!stored) {
    toast(store.lastStorageError()
      ? 'NOT SAVED — this device is out of storage space'
      : 'NOT SAVED — try again', 'warn');
    return false;
  }
  live.events = store.getEvents(live.game.id);
  paintCounts();
  buzz();
  if (message) toast(message);
  return true;
}

function tapNextPlay() {
  const { state } = live;
  const stored = store.recordPlay(live.game.id, {
    unit: state.unit, quarter: state.quarter, athleteIn: state.athleteIn
  });
  if (!afterRecord(stored)) return;

  const btn = $('#g-next');
  btn.classList.remove('flash');
  void btn.offsetWidth;      /* restart the animation on consecutive taps */
  btn.classList.add('flash');
}

function toggleInOut() {
  live.state = store.setGameState(live.game.id, { athleteIn: !live.state.athleteIn });
  paintChrome();
  buzz(8);
}

function tapStat(statId) {
  const def = STATS_BY_ID[statId];
  if (!def) return;
  if (def.yardage) { openYardageSheet(def); return; }
  recordStat(def, null);
}

function recordStat(def, yards) {
  const { state } = live;
  const stored = store.recordStat(live.game.id, {
    unit: state.unit,
    quarter: state.quarter,
    athleteIn: state.athleteIn,
    statId: def.id,
    yards
  });
  afterRecord(stored, typeof yards === 'number'
    ? `${def.label} · ${yards >= 0 ? '+' : ''}${yards} yds`
    : def.label);
}

function tapUndo() {
  const removed = store.undoLast(live.game.id);
  if (!removed) { toast('Nothing to undo'); return; }
  live.events = store.getEvents(live.game.id);
  paintCounts();
  buzz(20);

  const what = removed.type === 'play'
    ? `play (${unitLabel(removed.unit)})`
    : removed.type === 'score'
      ? `${removed.points} point${removed.points === 1 ? '' : 's'}`
      : (STATS_BY_ID[removed.statId] ? STATS_BY_ID[removed.statId].label : removed.statId);
  toast(`Undid ${what}`);
}

/* ------------------------------------------------------------ yardage §12 */
function openYardageSheet(def) {
  const quick = [-5, -2, 0, 2, 5, 10, 15, 20];
  openSheet(`
    <div class="sheet-title">${esc(def.label)} — how many yards?</div>
    <div class="sheet-sub">Pick the closest. You can correct it later from the game report.</div>
    <div class="yard-grid">
      ${quick.map((v) => `<button class="yard-btn ${v < 0 ? 'neg' : ''}" data-y="${v}">${v > 0 ? '+' : ''}${v}</button>`).join('')}
    </div>
    <button class="btn" id="y-custom">Custom yardage</button>
    <button class="btn btn-ghost" id="y-none">Record without yards</button>
    <button class="btn btn-ghost" id="y-cancel">Cancel</button>
  `);

  $$('#sheet [data-y]').forEach((b) => {
    b.onclick = () => { closeSheet(); recordStat(def, Number(b.dataset.y)); };
  });
  /* "Record without yards" is not a cop-out — a parent who did not see the gain
   * should still get the attempt counted. Reports say how many are missing. */
  $('#y-none').onclick = () => { closeSheet(); recordStat(def, null); };
  $('#y-cancel').onclick = closeSheet;
  $('#y-custom').onclick = () => openKeypad(def);
}

function openKeypad(def) {
  let digits = '';
  let negative = false;

  openSheet(`
    <div class="sheet-title">${esc(def.label)} — custom yards</div>
    <div class="keypad-display"><span id="k-sign"></span><span id="k-val" style="font-size:40px;color:var(--text);margin:0">0</span><span>yds</span></div>
    <div class="keypad">
      ${[1,2,3,4,5,6,7,8,9].map((n) => `<button data-k="${n}">${n}</button>`).join('')}
      <button data-k="neg" id="k-neg">±</button>
      <button data-k="0">0</button>
      <button data-k="del">⌫</button>
    </div>
    <button class="btn btn-primary btn-lg" id="k-save">Record</button>
    <button class="btn btn-ghost" id="k-cancel">Cancel</button>
  `);

  const paint = () => {
    $('#k-val').textContent = (negative && digits ? '-' : '') + (digits || '0');
    $('#k-neg').style.color = negative ? 'var(--amber)' : '';
  };

  $$('#sheet [data-k]').forEach((b) => {
    b.onclick = () => {
      const k = b.dataset.k;
      if (k === 'del') digits = digits.slice(0, -1);
      else if (k === 'neg') negative = !negative;
      else if (digits.length < 3) digits += k;
      paint();
    };
  });
  $('#k-cancel').onclick = closeSheet;
  $('#k-save').onclick = () => {
    const value = Number(digits || '0') * (negative ? -1 : 1);
    closeSheet();
    recordStat(def, value);
  };
  paint();
}

/* -------------------------------------------------------------- score §15 */
function openScoreSheet() {
  const d = deriveGame(live.events);
  openSheet(`
    <div class="sheet-title">Score</div>
    <div class="sheet-sub">Optional. PlayingTime works perfectly well without it.</div>
    <div style="display:flex;justify-content:space-around;text-align:center;margin-bottom:18px">
      <div><div style="font-size:34px;font-weight:700">${d.score.us}</div><div style="font-size:12px;color:var(--text-dim)">Our team</div></div>
      <div><div style="font-size:34px;font-weight:700">${d.score.them}</div><div style="font-size:12px;color:var(--text-dim)">${esc(live.game.opponent || 'Opponent')}</div></div>
    </div>
    <div style="font-size:12px;font-weight:700;color:var(--text-faint);text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px">Our team</div>
    <div class="score-grid">
      ${[1,2,3,6].map((p) => `<button data-side="us" data-p="${p}">+${p}</button>`).join('')}
    </div>
    <div style="font-size:12px;font-weight:700;color:var(--text-faint);text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px">${esc(live.game.opponent || 'Opponent')}</div>
    <div class="score-grid">
      ${[1,2,3,6].map((p) => `<button data-side="them" data-p="${p}">+${p}</button>`).join('')}
    </div>
    <button class="btn btn-ghost" id="sc-close">Done</button>
  `);

  $$('#sheet [data-side]').forEach((b) => {
    b.onclick = () => {
      const stored = store.recordScore(live.game.id, {
        quarter: live.state.quarter, side: b.dataset.side, points: Number(b.dataset.p)
      });
      if (afterRecord(stored, `+${b.dataset.p} ${b.dataset.side === 'us' ? 'our team' : 'opponent'}`)) {
        closeSheet(); openScoreSheet();
      }
    };
  });
  $('#sc-close').onclick = closeSheet;
}

/* --------------------------------------------------------------- game menu */
function gameMenu() {
  openSheet(`
    <div class="sheet-title">Game</div>
    <div class="sheet-sub">${esc(vsLine(live.game))} · ${live.events.length} recorded action${live.events.length === 1 ? '' : 's'}</div>
    <button class="btn" id="gm-home">Leave and keep tracking later</button>
    <button class="btn btn-danger" id="gm-end">End game and see the report</button>
    <button class="btn btn-ghost" id="gm-close">Back to the game</button>
  `);
  $('#gm-home').onclick = () => { closeSheet(); go('home'); };
  $('#gm-end').onclick = () => { closeSheet(); confirmEndGame(); };
  $('#gm-close').onclick = closeSheet;
}

function confirmEndGame() {
  confirmSheet({
    title: 'Finish this game?',
    body: 'Are you sure you want to finish this game? The report is generated straight away. You can reopen the game later if you need to correct something.',
    confirmLabel: 'End game',
    onConfirm: () => { store.endGame(live.game.id); go('report', live.game.id); }
  });
}

/* ============================================================== report §17 */
function renderReport() {
  const game = store.getGame(route.arg);
  if (!game) { go('history'); return; }
  const athlete = store.getAthlete(game.athleteId);
  if (!athlete) { go('home'); return; }

  const events = store.getEvents(game.id);
  const d = deriveGame(events);
  const isLive = game.status === store.GAME_STATUS.IN_PROGRESS;

  const unitBlocks = UNITS
    .filter((u) => d.units[u.id].teamPlays > 0)
    .map((u) => {
      const t = d.units[u.id];
      return `
        <div class="part-block">
          <div class="part-head">
            <span class="u">${esc(u.label)}</span>
            <span class="v">${t.athletePlays} / ${t.teamPlays} &nbsp; <b>${pct(t.participation)}</b></span>
          </div>
          <div class="bar"><i style="width:${Math.min(100, t.participation)}%"></i></div>
        </div>`;
    }).join('');

  const quarterRows = QUARTERS
    .map((q) => {
      const qu = d.byQuarter[q].units;
      const team = UNITS.reduce((n, u) => n + qu[u.id].teamPlays, 0);
      const ath = UNITS.reduce((n, u) => n + qu[u.id].athletePlays, 0);
      return team ? { q, team, ath } : null;
    })
    .filter(Boolean);

  const statSections = UNITS
    .map((u) => {
      const html = renderStatLines(d.stats, u.id);
      return html ? `<div class="card"><div class="card-title">${esc(u.label)} statistics</div>${html}</div>` : '';
    }).join('');

  $('#view-report .scroll').innerHTML = `
    <div class="wrap">
      <button class="btn btn-ghost" id="rp-back" style="margin-bottom:14px">← Back</button>

      <div style="text-align:center;margin-bottom:20px">
        <div style="font-family:var(--font-display);font-size:27px;line-height:1.2">${esc(athlete.name)}</div>
        <div style="font-size:15px;color:var(--text-dim);margin-top:5px">${esc(vsLine(game))}</div>
        <div style="font-size:12.5px;color:var(--text-faint);margin-top:3px">
          ${esc(formatDate(game.date))}${game.location ? ` · ${esc(game.location)}` : ''}
          · <span class="pill ${isLive ? 'pill-live' : 'pill-final'}">${isLive ? 'In progress' : 'Final'}</span>
        </div>
      </div>

      ${d.eventCount === 0 ? `
        <div class="empty">
          <strong>Nothing was recorded in this game</strong>
          No plays and no statistics were tapped, so there is nothing to report.
          This panel stays empty rather than showing zeroes that look like results.
        </div>
      ` : `
        <div class="big-stats">
          <div class="big-stat"><b>${d.totals.athletePlays}</b><span>Plays</span></div>
          <div class="big-stat"><b>${d.totals.teamPlays}</b><span>Opportunities</span></div>
          <div class="big-stat"><b>${d.totals.teamPlays ? pct(d.totals.participation) : '—'}</b><span>Participation</span></div>
        </div>

        ${unitBlocks ? `<div class="card"><div class="card-title">Participation by unit</div>${unitBlocks}</div>` : ''}

        ${statSections || `<div class="card"><div class="card-note">
          Plays were counted but no individual statistics were recorded in this game.
        </div></div>`}

        ${quarterRows.length > 1 ? `
          <div class="card">
            <div class="card-title">By quarter</div>
            ${quarterRows.map((r) => `
              <div class="stat-row">
                <span class="n">${r.q}</span>
                <span class="l">${r.ath} of ${r.team} plays</span>
                <span class="x">${pct((r.ath / r.team) * 100)}</span>
              </div>`).join('')}
          </div>` : ''}

        ${(d.score.us || d.score.them) ? `
          <div class="card">
            <div class="card-title">Final score</div>
            <div style="display:flex;justify-content:space-around;text-align:center">
              <div><div style="font-size:31px;font-weight:700">${d.score.us}</div><div style="font-size:12px;color:var(--text-dim)">Our team</div></div>
              <div><div style="font-size:31px;font-weight:700">${d.score.them}</div><div style="font-size:12px;color:var(--text-dim)">${esc(game.opponent || 'Opponent')}</div></div>
            </div>
          </div>` : ''}

        <button class="btn btn-primary btn-lg" id="rp-card">Create game card</button>
      `}

      ${isLive
        ? '<button class="btn" id="rp-resume" style="margin-top:10px">Back to tracking this game</button>'
        : '<button class="btn btn-ghost" id="rp-reopen" style="margin-top:10px">Reopen to correct something</button>'}
      <button class="btn btn-danger" id="rp-delete">Delete this game</button>

      <div class="footer-brand">
        <b>PlayingTime Football</b> · Powered by Venuewise<br />Built by Herman Legacy Digital
      </div>
    </div>
  `;

  $('#rp-back').onclick = () => history.length > 1 ? history.back() : go('history');
  const cardBtn = $('#rp-card');
  if (cardBtn) cardBtn.onclick = () => openShareCard(game, athlete, d);

  const resume = $('#rp-resume');
  if (resume) resume.onclick = () => go('game', game.id);

  const reopen = $('#rp-reopen');
  if (reopen) reopen.onclick = () => confirmSheet({
    title: 'Reopen this game?',
    body: 'The game goes back to being tracked so you can add or undo actions. End it again when you are done.',
    confirmLabel: 'Reopen game',
    danger: false,
    onConfirm: () => {
      const other = store.inProgressGame();
      if (other && other.id !== game.id) {
        toast(`Finish ${vsLine(other)} first`, 'warn'); return;
      }
      store.reopenGame(game.id);
      go('game', game.id);
    }
  });

  $('#rp-delete').onclick = () => confirmSheet({
    title: 'Delete this game?',
    body: `Every play and statistic recorded ${vsLine(game)} is deleted from this device. This cannot be undone.`,
    confirmLabel: 'Delete game',
    onConfirm: () => { store.deleteGame(game.id); toast('Game deleted'); go('history'); }
  });
}

/* --------------------------------------------------------- share card §21 */
function openShareCard(game, athlete, derived) {
  const canvas = document.createElement('canvas');
  drawShareCard(canvas, { game, athlete, derived, vsLine: vsLine(game) });

  openSheet(`
    <div class="sheet-title">Game card</div>
    <div class="sheet-sub">Save it or share it. Every number on the card comes from what you tracked.</div>
    <img class="sharecard-preview" id="card-img" alt="Game card for ${esc(athlete.name)}" />
    <button class="btn btn-primary btn-lg" id="card-share" style="margin-top:14px">Share</button>
    <button class="btn" id="card-save">Save image</button>
    <button class="btn btn-ghost" id="card-close">Close</button>
  `);

  const dataUrl = canvas.toDataURL('image/png');
  $('#card-img').src = dataUrl;

  const filename = `playingtime-${(athlete.name || 'athlete').toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${game.date}.png`;

  $('#card-save').onclick = () => {
    const a = document.createElement('a');
    a.href = dataUrl;
    a.download = filename;
    a.click();
    toast('Image saved');
  };

  /* Web Share with a file is the good path on a phone. Where it is unavailable
   * we say so and fall back to saving, rather than showing a button that fails. */
  $('#card-share').onclick = async () => {
    try {
      const blob = await (await fetch(dataUrl)).blob();
      const file = new File([blob], filename, { type: 'image/png' });
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: `${athlete.name} — PlayingTime` });
        return;
      }
      toast('Sharing is not available in this browser — saving instead');
      $('#card-save').click();
    } catch (err) {
      if (err && err.name === 'AbortError') return;   /* the parent cancelled */
      toast('Could not share — saving instead', 'warn');
      $('#card-save').click();
    }
  };

  $('#card-close').onclick = closeSheet;
}

/* ============================================================= athlete §20 */
function renderAthlete() {
  const athlete = store.activeAthlete();
  const finals = store.listGames(athlete.id).filter((g) => g.status === store.GAME_STATUS.FINAL);
  const eventsByGame = {};
  for (const g of finals) eventsByGame[g.id] = store.getEvents(g.id);
  const season = deriveSeason(finals, eventsByGame);

  const unitBlocks = UNITS
    .filter((u) => season.units[u.id].teamPlays > 0)
    .map((u) => {
      const t = season.units[u.id];
      return `
        <div class="part-block">
          <div class="part-head">
            <span class="u">${esc(u.label)}</span>
            <span class="v">${t.athletePlays} / ${t.teamPlays} &nbsp; <b>${pct(t.participation)}</b></span>
          </div>
          <div class="bar"><i style="width:${Math.min(100, t.participation)}%"></i></div>
        </div>`;
    }).join('');

  $('#view-athlete .scroll').innerHTML = `
    <div class="wrap">
      <div class="athlete-hero">
        <div class="jersey">${athlete.jerseyNumber ? `#${esc(athlete.jerseyNumber)}` : esc((athlete.name || '?').slice(0, 1))}</div>
        <div style="min-width:0">
          <div class="ah-name">${esc(athlete.name)}</div>
          <div class="ah-sub">
            ${esc([athlete.team, athlete.level].filter(Boolean).join(' · ') || 'No team set')}<br />
            ${esc([athlete.primaryPosition, athlete.secondaryPosition].filter(Boolean).join(' / ') || 'No position set')}
            ${athlete.season ? ` · ${esc(athlete.season)}` : ''}
          </div>
        </div>
      </div>

      ${season.gamesPlayed === 0 ? `
        <div class="empty">
          <strong>No completed games yet</strong>
          This profile fills in from the games you track. Nothing here is estimated.
        </div>` : `
        <div class="big-stats">
          <div class="big-stat"><b>${season.gamesPlayed}</b><span>Games</span></div>
          <div class="big-stat"><b>${season.totals.athletePlays}</b><span>Total plays</span></div>
          <div class="big-stat"><b>${pct(season.totals.participation)}</b><span>Participation</span></div>
        </div>
        ${unitBlocks ? `<div class="card"><div class="card-title">Participation by unit</div>${unitBlocks}</div>` : ''}
        ${UNITS.map((u) => {
          const html = renderStatLines(season.stats, u.id);
          return html ? `<div class="card"><div class="card-title">${esc(u.label)} — season totals</div>${html}</div>` : '';
        }).join('')}
      `}

      <button class="btn" id="at-edit">Edit athlete details</button>
      <button class="btn btn-ghost" id="at-add">Add another athlete</button>
    </div>
  `;

  $('#at-edit').onclick = () => go('athlete-new', athlete.id);
  $('#at-add').onclick = () => go('athlete-new');
}

/* ============================================================= history §19 */
function renderHistory() {
  const athlete = store.activeAthlete();
  const games = store.listGames(athlete.id);
  const eventsByGame = {};
  for (const g of games) eventsByGame[g.id] = store.getEvents(g.id);

  /* Group by season so a returning parent sees this year, then last year. */
  const bySeason = [];
  for (const g of games) {
    const key = g.season || athlete.season || 'Games';
    let group = bySeason.find((s) => s.key === key);
    if (!group) { group = { key, games: [] }; bySeason.push(group); }
    group.games.push(g);
  }

  $('#view-history .scroll').innerHTML = `
    <div class="wrap">
      <h2 style="font-family:var(--font-display);font-size:25px;margin:14px 0 16px">Game history</h2>
      ${games.length === 0 ? `
        <div class="empty">
          <strong>No games yet</strong>
          Games appear here as soon as you track one.
        </div>` : bySeason.map((group) => `
          <div class="card-title">${esc(group.key)}</div>
          ${group.games.map((g) => gameItemHTML(g, eventsByGame[g.id])).join('')}
        `).join('')}
    </div>
  `;

  $$('#view-history [data-game]').forEach((b) => {
    b.onclick = () => {
      const game = store.getGame(b.dataset.game);
      go(game && game.status === store.GAME_STATUS.IN_PROGRESS ? 'game' : 'report', b.dataset.game);
    };
  });
}

/* ================================================================ settings */
function renderSettings() {
  const account = store.getAccount();
  const athletes = store.listAthletes();
  const footprint = store.storageFootprint();
  const cloud = sync.status();

  $('#view-settings .scroll').innerHTML = `
    <div class="wrap">
      <h2 style="font-family:var(--font-display);font-size:25px;margin:14px 0 16px">Settings</h2>

      <div class="card">
        <div class="card-title">Account</div>
        <div class="field">
          <label for="st-name">Your name</label>
          <input id="st-name" value="${esc(account ? account.name : '')}" />
        </div>
        <div class="field">
          <label for="st-email">Email</label>
          <input id="st-email" type="email" inputmode="email" value="${esc(account ? account.email : '')}" />
        </div>
        <div class="field">
          <label for="st-phone">Phone <span style="color:var(--text-faint)">(optional)</span></label>
          <input id="st-phone" type="tel" inputmode="tel" value="${esc(account ? account.phone : '')}" />
        </div>
        <div class="err" id="st-err"></div>
        <button class="btn" id="st-save">Save account</button>
      </div>

      <div class="card">
        <div class="card-title">Athletes</div>
        ${athletes.map((a) => `
          <button class="btn btn-ghost" data-ath="${a.id}" style="margin-bottom:8px">
            ${esc(a.name)}${a.jerseyNumber ? ` · #${esc(a.jerseyNumber)}` : ''}
          </button>`).join('')}
        <button class="btn" id="st-add-athlete">Add athlete</button>
      </div>

      <div class="card">
        <div class="card-title">Where your data lives</div>
        <div class="notice warn">
          <b>${esc(cloud.headline)}</b>
          ${esc(cloud.detail)}
        </div>
        <div class="card-note" style="margin-top:12px">
          On this device: <b style="color:var(--text)">${footprint.games}</b> game${footprint.games === 1 ? '' : 's'},
          <b style="color:var(--text)">${footprint.events}</b> recorded action${footprint.events === 1 ? '' : 's'},
          about <b style="color:var(--text)">${Math.max(1, Math.round(footprint.bytes / 1024))} KB</b>.
          ${esc(cloud.mitigation)}
        </div>
        <button class="btn" id="st-export" style="margin-top:14px">Export data</button>
        <button class="btn btn-ghost" id="st-import">Import a backup</button>
        <input type="file" id="st-file" accept="application/json,.json" class="sr-only" />
      </div>

      <div class="card">
        <div class="card-title">About</div>
        <div class="card-note">
          <b style="color:var(--text)">PlayingTime Football</b> — V1.<br />
          Know exactly how much your athlete played, and what they did while they were on the field.<br /><br />
          Powered by <b style="color:var(--text)">Venuewise</b><br />
          Built by <b style="color:var(--text)">Herman Legacy Digital</b><br />
          Marketed by <b style="color:var(--text)">5-Star Sports Media</b>
        </div>
      </div>

      <div class="card">
        <div class="card-title">Danger zone</div>
        <button class="btn btn-danger" id="st-reset">Erase everything on this device</button>
      </div>
    </div>
  `;

  $('#st-save').onclick = () => {
    const name = $('#st-name').value.trim();
    const email = $('#st-email').value.trim();
    if (!name || !email) { $('#st-err').textContent = 'Name and email are both required.'; return; }
    store.saveAccount({ name, email, phone: $('#st-phone').value });
    toast('Account saved');
  };

  $$('[data-ath]').forEach((b) => { b.onclick = () => go('athlete-new', b.dataset.ath); });
  $('#st-add-athlete').onclick = () => go('athlete-new');

  $('#st-export').onclick = () => {
    const payload = JSON.stringify(store.exportAll(), null, 2);
    const url = URL.createObjectURL(new Blob([payload], { type: 'application/json' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `playingtime-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
    toast('Backup downloaded');
  };

  $('#st-import').onclick = () => $('#st-file').click();
  $('#st-file').onchange = async (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    try {
      const result = store.importAll(JSON.parse(await file.text()), { merge: true });
      toast(`Imported ${result.importedGames} game${result.importedGames === 1 ? '' : 's'}`);
      render();
    } catch (err) {
      toast(String((err && err.message) || 'Could not read that file'), 'warn');
    } finally {
      e.target.value = '';
    }
  };

  $('#st-reset').onclick = () => confirmSheet({
    title: 'Erase everything?',
    body: 'Every athlete, game and play stored by PlayingTime on this device is deleted. Because there is no cloud copy yet, this cannot be undone. Export a backup first if you want to keep it.',
    confirmLabel: 'Erase everything',
    onConfirm: () => { store.resetAll(); location.hash = '#/onboard'; render(); }
  });
}

/* ================================================================== boot == */
function boot() {
  $$('#nav button').forEach((b) => {
    b.onclick = () => {
      /* GAME goes to the live game if there is one, otherwise to setup. */
      if (b.dataset.nav === 'game') {
        const live_ = store.inProgressGame();
        go(live_ ? 'game' : 'game-setup', live_ ? live_.id : null);
        return;
      }
      go(b.dataset.nav);
    };
  });

  $('#sheet').addEventListener('click', (e) => { if (e.target.id === 'sheet') closeSheet(); });
  window.addEventListener('hashchange', () => { closeSheet(); render(); });

  render();

  /* Offline shell. Registration failing is not fatal — the app still runs, it
   * just will not open without a connection, so we do not claim otherwise. */
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => { /* still usable online */ });
  }
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
