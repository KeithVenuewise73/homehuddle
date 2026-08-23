/* ============================================================================
 * PlayingTime Football — store.js
 * Durable local storage for accounts, athletes, games and the play/stat log.
 *
 * WHY LOCAL FIRST
 * A parent tracks a game from the stands, on a phone, inside a concrete stadium
 * where signal is often gone by the second quarter. A tracker that needs a round
 * trip per tap is a tracker that loses the game. So the authoritative copy of a
 * live game is on the device, written synchronously on every tap, and cloud sync
 * (sync.js) is an additive layer on top — never a prerequisite for tracking.
 *
 * LAYOUT (localStorage)
 *   pt.v1.root                  account, athletes, game metadata, settings
 *   pt.v1.game.<id>.events      that game's append-only event log
 *   pt.v1.game.<id>.state       live UI state (unit / quarter / in-out)
 *
 * Event logs are kept in their own keys so the hot path — a tap during a play —
 * rewrites a few kilobytes rather than the whole season.
 * ========================================================================== */

import { defaultUnitFor } from './catalog.js';

export const SCHEMA_VERSION = 1;
const ROOT_KEY = 'pt.v1.root';
const gameEventsKey = (id) => `pt.v1.game.${id}.events`;
const gameStateKey  = (id) => `pt.v1.game.${id}.state`;

/* ---------------------------------------------------------------------------
 * Backing store. localStorage in the browser; an in-memory map under `node
 * --test` so the store itself is testable rather than only the pure engine.
 * ------------------------------------------------------------------------- */
function memoryBacking() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
    key: (i) => Array.from(map.keys())[i] ?? null,
    get length() { return map.size; }
  };
}

let backing =
  typeof globalThis.localStorage !== 'undefined' ? globalThis.localStorage : memoryBacking();

/** Swap the backing store. Used by tests; also the seam for a future adapter. */
export function _setBacking(next) { backing = next || memoryBacking(); }

function readJSON(key, fallback) {
  try {
    const raw = backing.getItem(key);
    if (raw === null || raw === undefined) return fallback;
    const parsed = JSON.parse(raw);
    return parsed === null || parsed === undefined ? fallback : parsed;
  } catch {
    /* Corrupt or truncated value: fall back rather than take the app down mid
     * game. The caller still sees a well-formed empty structure. */
    return fallback;
  }
}

function writeJSON(key, value) {
  try {
    backing.setItem(key, JSON.stringify(value));
    return { ok: true };
  } catch (err) {
    /* Quota exhausted or storage disabled (private browsing). The UI surfaces
     * this: a tap that did not persist must not look like one that did. */
    return { ok: false, error: String((err && err.message) || err) };
  }
}

/* Last write failure, so the UI can tell the truth about durability. */
let lastWriteError = null;
export function lastStorageError() { return lastWriteError; }

function persist(key, value) {
  const res = writeJSON(key, value);
  lastWriteError = res.ok ? null : res.error;
  return res.ok;
}

/** Is persistent storage actually available? Probed, not assumed. */
export function storageAvailable() {
  try {
    const probe = 'pt.v1.probe';
    backing.setItem(probe, '1');
    backing.removeItem(probe);
    return true;
  } catch {
    return false;
  }
}

/* ---------------------------------------------------------------------------
 * Ids. Random, prefixed, sortable enough for a log that also carries `seq`.
 * ------------------------------------------------------------------------- */
export function newId(prefix) {
  const rand =
    typeof globalThis.crypto !== 'undefined' && globalThis.crypto.randomUUID
      ? globalThis.crypto.randomUUID().replace(/-/g, '').slice(0, 12)
      : Math.random().toString(36).slice(2, 14).padEnd(12, '0');
  return `${prefix}_${rand}`;
}

/* ---------------------------------------------------------------------------
 * Root document
 * ------------------------------------------------------------------------- */
function emptyRoot() {
  return {
    version: SCHEMA_VERSION,
    account: null,
    athletes: [],
    games: [],
    settings: { activeAthleteId: null, cloudSync: false }
  };
}

export function getRoot() {
  const root = readJSON(ROOT_KEY, null);
  if (!root || typeof root !== 'object') return emptyRoot();
  return {
    ...emptyRoot(),
    ...root,
    athletes: Array.isArray(root.athletes) ? root.athletes : [],
    games: Array.isArray(root.games) ? root.games : [],
    settings: { ...emptyRoot().settings, ...(root.settings || {}) }
  };
}

function saveRoot(root) {
  return persist(ROOT_KEY, { ...root, version: SCHEMA_VERSION });
}

/* ---------------------------------------------------------------------------
 * Account (§4 step 1). V1 is a local profile: it names the person using the app
 * and nothing more. There is no password here because there is no server here —
 * see sync.js for what an account will mean once cloud sync is switched on.
 * ------------------------------------------------------------------------- */
export function getAccount() { return getRoot().account; }

export function saveAccount({ name, email, phone }) {
  const root = getRoot();
  const now = new Date().toISOString();
  root.account = {
    id: (root.account && root.account.id) || newId('usr'),
    name: (name || '').trim(),
    email: (email || '').trim(),
    phone: (phone || '').trim(),
    createdAt: (root.account && root.account.createdAt) || now,
    updatedAt: now
  };
  saveRoot(root);
  return root.account;
}

/* ---------------------------------------------------------------------------
 * Athletes (§4 step 2)
 * ------------------------------------------------------------------------- */
export function listAthletes() { return getRoot().athletes; }

export function getAthlete(id) {
  return getRoot().athletes.find((a) => a.id === id) || null;
}

export function activeAthlete() {
  const root = getRoot();
  const id = root.settings.activeAthleteId;
  return root.athletes.find((a) => a.id === id) || root.athletes[0] || null;
}

export function setActiveAthlete(id) {
  const root = getRoot();
  root.settings.activeAthleteId = id;
  saveRoot(root);
}

export function saveAthlete(input) {
  const root = getRoot();
  const now = new Date().toISOString();
  const existing = input.id ? root.athletes.find((a) => a.id === input.id) : null;

  const athlete = {
    id: (existing && existing.id) || newId('ath'),
    name: (input.name || '').trim(),
    jerseyNumber: (input.jerseyNumber ?? '').toString().trim(),
    team: (input.team || '').trim(),
    level: (input.level || '').trim(),
    season: (input.season || '').trim(),
    primaryPosition: input.primaryPosition || '',
    secondaryPosition: input.secondaryPosition || '',
    photo: input.photo ?? (existing ? existing.photo : null),
    createdAt: (existing && existing.createdAt) || now,
    updatedAt: now
  };

  if (existing) {
    root.athletes = root.athletes.map((a) => (a.id === athlete.id ? athlete : a));
  } else {
    root.athletes.push(athlete);
    if (!root.settings.activeAthleteId) root.settings.activeAthleteId = athlete.id;
  }
  saveRoot(root);
  return athlete;
}

/** An athlete's positions, primary first, with blanks dropped. */
export function athletePositions(athlete) {
  if (!athlete) return [];
  return [athlete.primaryPosition, athlete.secondaryPosition].filter(Boolean);
}

export function deleteAthlete(id) {
  const root = getRoot();
  const games = root.games.filter((g) => g.athleteId === id);
  for (const g of games) {
    backing.removeItem(gameEventsKey(g.id));
    backing.removeItem(gameStateKey(g.id));
  }
  root.games = root.games.filter((g) => g.athleteId !== id);
  root.athletes = root.athletes.filter((a) => a.id !== id);
  if (root.settings.activeAthleteId === id) {
    root.settings.activeAthleteId = root.athletes.length ? root.athletes[0].id : null;
  }
  saveRoot(root);
  return { deletedGames: games.length };
}

/* ---------------------------------------------------------------------------
 * Games (§4 step 3)
 * ------------------------------------------------------------------------- */
export const GAME_STATUS = { IN_PROGRESS: 'in_progress', FINAL: 'final' };

export function listGames(athleteId) {
  const games = getRoot().games;
  const filtered = athleteId ? games.filter((g) => g.athleteId === athleteId) : games;
  /* Most recent first: history reads newest-down (§19). */
  return [...filtered].sort((a, b) => String(b.date).localeCompare(String(a.date)) ||
    String(b.createdAt).localeCompare(String(a.createdAt)));
}

export function getGame(id) { return getRoot().games.find((g) => g.id === id) || null; }

/** The game still being tracked, if any. At most one is in progress at a time. */
export function inProgressGame() {
  return getRoot().games.find((g) => g.status === GAME_STATUS.IN_PROGRESS) || null;
}

export function createGame(input) {
  const root = getRoot();
  const athlete = root.athletes.find((a) => a.id === input.athleteId);
  const now = new Date().toISOString();
  const game = {
    id: newId('gm'),
    athleteId: input.athleteId,
    opponent: (input.opponent || '').trim(),
    date: input.date || now.slice(0, 10),
    homeAway: input.homeAway === 'away' ? 'away' : 'home',
    location: (input.location || '').trim(),
    status: GAME_STATUS.IN_PROGRESS,
    createdAt: now,
    endedAt: null,
    season: (athlete && athlete.season) || ''
  };
  root.games.push(game);
  saveRoot(root);

  persist(gameEventsKey(game.id), []);
  persist(gameStateKey(game.id), {
    unit: defaultUnitFor(athletePositions(athlete)),
    quarter: 'Q1',
    athleteIn: true
  });
  return game;
}

export function updateGame(id, patch) {
  const root = getRoot();
  let updated = null;
  root.games = root.games.map((g) => {
    if (g.id !== id) return g;
    updated = { ...g, ...patch, id: g.id };
    return updated;
  });
  saveRoot(root);
  return updated;
}

export function endGame(id) {
  return updateGame(id, { status: GAME_STATUS.FINAL, endedAt: new Date().toISOString() });
}

/** Reopen a finished game so a mistake found in the report can be corrected. */
export function reopenGame(id) {
  return updateGame(id, { status: GAME_STATUS.IN_PROGRESS, endedAt: null });
}

export function deleteGame(id) {
  const root = getRoot();
  root.games = root.games.filter((g) => g.id !== id);
  saveRoot(root);
  backing.removeItem(gameEventsKey(id));
  backing.removeItem(gameStateKey(id));
}

/* ---------------------------------------------------------------------------
 * Live game state — what the screen is currently set to. Persisted so that a
 * locked phone, a browser tab eviction or a dropped connection mid-game does not
 * lose which unit is on the field or whether the athlete is in.
 * ------------------------------------------------------------------------- */
export function getGameState(gameId) {
  return readJSON(gameStateKey(gameId), { unit: 'defense', quarter: 'Q1', athleteIn: true });
}

export function setGameState(gameId, patch) {
  const next = { ...getGameState(gameId), ...patch };
  persist(gameStateKey(gameId), next);
  return next;
}

/* ---------------------------------------------------------------------------
 * The event log (§26)
 * ------------------------------------------------------------------------- */
export function getEvents(gameId) {
  const events = readJSON(gameEventsKey(gameId), []);
  return Array.isArray(events) ? events : [];
}

function nextSeq(events) {
  return events.reduce((max, e) => Math.max(max, Number(e.seq) || 0), 0) + 1;
}

/**
 * Append an event. Returns the stored event, or null if it could not be
 * persisted — the caller must treat null as "this tap did not happen" and say so
 * rather than updating the count on screen.
 */
export function appendEvent(gameId, event) {
  const events = getEvents(gameId);
  const stored = {
    id: newId('ev'),
    seq: nextSeq(events),
    ts: new Date().toISOString(),
    ...event
  };
  events.push(stored);
  return persist(gameEventsKey(gameId), events) ? stored : null;
}

/** Record one play for the unit on the field (§6). */
export function recordPlay(gameId, { unit, quarter, athleteIn }) {
  return appendEvent(gameId, { type: 'play', unit, quarter, athleteIn: !!athleteIn });
}

/** Record one statistic. `yards` is null when the parent did not enter it. */
export function recordStat(gameId, { unit, quarter, athleteIn, statId, yards }) {
  return appendEvent(gameId, {
    type: 'stat',
    unit,
    quarter,
    athleteIn: !!athleteIn,
    statId,
    yards: typeof yards === 'number' && Number.isFinite(yards) ? yards : null
  });
}

export function recordScore(gameId, { quarter, side, points }) {
  return appendEvent(gameId, { type: 'score', quarter, side, points: Number(points) || 0 });
}

/**
 * Undo the most recent event (§13 — mandatory).
 * Removes it from the log and returns it so the UI can name what it undid.
 * Undo is a hard requirement of live tracking: mistakes happen at speed, and a
 * tracker you cannot correct is a tracker that gets abandoned mid-game.
 */
export function undoLast(gameId) {
  const events = getEvents(gameId);
  if (events.length === 0) return null;
  events.sort((a, b) => a.seq - b.seq);
  const removed = events.pop();
  return persist(gameEventsKey(gameId), events) ? removed : null;
}

/* ---------------------------------------------------------------------------
 * Export / import — the parent's data belongs to the parent, and while cloud
 * sync is off this is also the only backup that exists. Settings makes that
 * plain rather than implying the data is safe somewhere else.
 * ------------------------------------------------------------------------- */
export function exportAll() {
  const root = getRoot();
  return {
    format: 'playingtime-football-export',
    version: SCHEMA_VERSION,
    exportedAt: new Date().toISOString(),
    account: root.account,
    athletes: root.athletes,
    settings: root.settings,
    games: root.games.map((g) => ({
      ...g,
      events: getEvents(g.id),
      state: getGameState(g.id)
    }))
  };
}

export function importAll(payload, { merge = false } = {}) {
  if (!payload || payload.format !== 'playingtime-football-export') {
    throw new Error('That file is not a PlayingTime export.');
  }
  if (Number(payload.version) > SCHEMA_VERSION) {
    throw new Error('That export came from a newer version of PlayingTime.');
  }

  const root = merge ? getRoot() : emptyRoot();
  root.account = payload.account || root.account;
  root.settings = { ...root.settings, ...(payload.settings || {}) };

  const athleteIds = new Set(root.athletes.map((a) => a.id));
  for (const a of payload.athletes || []) {
    if (!athleteIds.has(a.id)) { root.athletes.push(a); athleteIds.add(a.id); }
  }

  const gameIds = new Set(root.games.map((g) => g.id));
  let importedGames = 0;
  for (const g of payload.games || []) {
    const { events, state, ...meta } = g;
    if (gameIds.has(meta.id)) continue;
    root.games.push(meta);
    gameIds.add(meta.id);
    persist(gameEventsKey(meta.id), Array.isArray(events) ? events : []);
    if (state) persist(gameStateKey(meta.id), state);
    importedGames += 1;
  }

  saveRoot(root);
  return { athletes: root.athletes.length, importedGames };
}

/** Wipe everything this app stores on this device. Used by Settings, on confirm. */
export function resetAll() {
  const root = getRoot();
  for (const g of root.games) {
    backing.removeItem(gameEventsKey(g.id));
    backing.removeItem(gameStateKey(g.id));
  }
  backing.removeItem(ROOT_KEY);
}

/** Rough footprint of stored data, so Settings can report something true. */
export function storageFootprint() {
  const root = getRoot();
  let bytes = (backing.getItem(ROOT_KEY) || '').length;
  let events = 0;
  for (const g of root.games) {
    const raw = backing.getItem(gameEventsKey(g.id)) || '';
    bytes += raw.length;
    events += getEvents(g.id).length;
  }
  return { bytes, events, games: root.games.length, athletes: root.athletes.length };
}
