/* Store tests — persistence, the event log, undo, and the failure paths.
 * The failure paths matter most: a tap that did not save must never be reported
 * as one that did. */
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import * as store from '../assets/js/store.js';

function fakeStorage({ failWrites = false } = {}) {
  const map = new Map();
  return {
    map,
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => {
      if (failWrites) throw new Error('QuotaExceededError');
      map.set(k, String(v));
    },
    removeItem: (k) => map.delete(k)
  };
}

beforeEach(() => { store._setBacking(fakeStorage()); });

function seed() {
  store.saveAccount({ name: 'Keith Herman', email: 'keith@example.com' });
  const athlete = store.saveAthlete({
    name: 'Dominic Herman', jerseyNumber: '24', team: 'Varsity Football',
    level: 'Varsity', season: '2026 Season', primaryPosition: 'LB', secondaryPosition: 'RB'
  });
  const game = store.createGame({ athleteId: athlete.id, opponent: 'Lancaster', date: '2026-09-11', homeAway: 'home' });
  return { athlete, game };
}

test('an empty device returns a well-formed empty state, not undefined', () => {
  assert.equal(store.getAccount(), null);
  assert.deepEqual(store.listAthletes(), []);
  assert.deepEqual(store.listGames(), []);
  assert.equal(store.activeAthlete(), null);
  assert.equal(store.inProgressGame(), null);
});

test('account and athlete round-trip through storage', () => {
  const { athlete } = seed();
  assert.equal(store.getAccount().name, 'Keith Herman');
  assert.equal(store.getAthlete(athlete.id).jerseyNumber, '24');
  assert.equal(store.activeAthlete().id, athlete.id, 'first athlete becomes the active one');
  assert.deepEqual(store.athletePositions(athlete), ['LB', 'RB']);
});

test('a new game starts in progress, on Q1, with the athlete in', () => {
  const { game } = seed();
  assert.equal(game.status, store.GAME_STATUS.IN_PROGRESS);
  assert.equal(store.inProgressGame().id, game.id);
  const state = store.getGameState(game.id);
  assert.equal(state.quarter, 'Q1');
  assert.equal(state.athleteIn, true);
  assert.equal(state.unit, 'defense', 'a linebacker opens on defense (§8)');
});

test('the event log is append-only and sequenced', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: false });
  store.recordStat(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true, statId: 'solo_tackle' });

  const events = store.getEvents(game.id);
  assert.equal(events.length, 3);
  assert.deepEqual(events.map((e) => e.seq), [1, 2, 3]);
  assert.deepEqual(events.map((e) => e.type), ['play', 'play', 'stat']);
  assert.ok(events.every((e) => e.id && e.ts), 'every event carries an id and a timestamp');
});

test('every event carries the context that was true when it happened (§26)', () => {
  const { game } = seed();
  store.recordStat(game.id, { unit: 'special_teams', quarter: 'Q3', athleteIn: true, statId: 'st_tackle' });
  const [ev] = store.getEvents(game.id);
  assert.equal(ev.unit, 'special_teams');
  assert.equal(ev.quarter, 'Q3');
  assert.equal(ev.athleteIn, true);
});

test('yardage is stored when given and null when not, never coerced to zero', () => {
  const { game } = seed();
  store.recordStat(game.id, { unit: 'offense', quarter: 'Q1', athleteIn: true, statId: 'rush_att', yards: 7 });
  store.recordStat(game.id, { unit: 'offense', quarter: 'Q1', athleteIn: true, statId: 'rush_att' });
  store.recordStat(game.id, { unit: 'offense', quarter: 'Q1', athleteIn: true, statId: 'rush_att', yards: 0 });
  const [a, b, c] = store.getEvents(game.id);
  assert.equal(a.yards, 7);
  assert.equal(b.yards, null, 'no yardage entered stays null');
  assert.equal(c.yards, 0, 'an explicit zero-yard gain is a real value');
});

test('undo removes exactly the last event and returns it (§13)', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.recordStat(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true, statId: 'sack' });

  const removed = store.undoLast(game.id);
  assert.equal(removed.statId, 'sack');
  assert.equal(store.getEvents(game.id).length, 1);
  assert.equal(store.getEvents(game.id)[0].type, 'play');
});

test('undo on an empty log returns null instead of throwing', () => {
  const { game } = seed();
  assert.equal(store.undoLast(game.id), null);
});

test('repeated undo walks the log back to empty, and seq restarts cleanly after', () => {
  const { game } = seed();
  for (let i = 0; i < 3; i++) store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.undoLast(game.id); store.undoLast(game.id); store.undoLast(game.id);
  assert.equal(store.getEvents(game.id).length, 0);

  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  assert.equal(store.getEvents(game.id)[0].seq, 1);
});

test('live game state survives being re-read (a locked phone mid-game)', () => {
  const { game } = seed();
  store.setGameState(game.id, { unit: 'offense', quarter: 'Q3', athleteIn: false });
  const state = store.getGameState(game.id);
  assert.equal(state.unit, 'offense');
  assert.equal(state.quarter, 'Q3');
  assert.equal(state.athleteIn, false);
});

test('ending a game marks it final and clears the in-progress slot', () => {
  const { game } = seed();
  const ended = store.endGame(game.id);
  assert.equal(ended.status, store.GAME_STATUS.FINAL);
  assert.ok(ended.endedAt);
  assert.equal(store.inProgressGame(), null);
});

test('a finished game can be reopened to correct a mistake', () => {
  const { game } = seed();
  store.endGame(game.id);
  const reopened = store.reopenGame(game.id);
  assert.equal(reopened.status, store.GAME_STATUS.IN_PROGRESS);
  assert.equal(reopened.endedAt, null);
  assert.equal(store.inProgressGame().id, game.id);
});

test('a failed write returns null so the UI can say the tap was not saved', () => {
  const { game } = seed();
  store._setBacking(fakeStorage({ failWrites: true }));
  const stored = store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  assert.equal(stored, null, 'appendEvent reports failure rather than pretending');
  assert.match(store.lastStorageError(), /Quota/);
});

test('corrupt stored data degrades to empty instead of taking the app down', () => {
  const backing = fakeStorage();
  backing.map.set('pt.v1.root', '{not json');
  store._setBacking(backing);
  assert.deepEqual(store.listAthletes(), []);
  assert.equal(store.getAccount(), null);
});

test('deleting a game removes its event log too', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.deleteGame(game.id);
  assert.equal(store.getGame(game.id), null);
  assert.deepEqual(store.getEvents(game.id), []);
});

test('deleting an athlete removes their games and reports how many', () => {
  const { athlete, game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  const result = store.deleteAthlete(athlete.id);
  assert.equal(result.deletedGames, 1);
  assert.deepEqual(store.listAthletes(), []);
  assert.deepEqual(store.listGames(), []);
});

test('export then import into a clean device reproduces the season exactly', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.recordStat(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true, statId: 'solo_tackle' });
  store.endGame(game.id);
  const payload = JSON.parse(JSON.stringify(store.exportAll()));

  store._setBacking(fakeStorage());              // a brand new device
  const result = store.importAll(payload);
  assert.equal(result.importedGames, 1);
  assert.equal(store.listAthletes()[0].name, 'Dominic Herman');
  assert.equal(store.getAccount().email, 'keith@example.com');
  assert.equal(store.getEvents(store.listGames()[0].id).length, 2);
});

test('importing the same backup twice does not duplicate games', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  const payload = JSON.parse(JSON.stringify(store.exportAll()));
  store.importAll(payload, { merge: true });
  assert.equal(store.listGames().length, 1);
});

test('a foreign or newer file is refused with a plain-English reason', () => {
  assert.throws(() => store.importAll({ format: 'something-else' }), /not a PlayingTime export/);
  assert.throws(
    () => store.importAll({ format: 'playingtime-football-export', version: 99 }),
    /newer version/
  );
});

test('games list is newest first', () => {
  const { athlete } = seed();
  store.createGame({ athleteId: athlete.id, opponent: 'Orchard Park', date: '2026-10-02' });
  const dates = store.listGames(athlete.id).map((g) => g.date);
  assert.deepEqual(dates, ['2026-10-02', '2026-09-11']);
});

test('reset clears everything this app stored', () => {
  const { game } = seed();
  store.recordPlay(game.id, { unit: 'defense', quarter: 'Q1', athleteIn: true });
  store.resetAll();
  assert.equal(store.getAccount(), null);
  assert.deepEqual(store.listGames(), []);
});
