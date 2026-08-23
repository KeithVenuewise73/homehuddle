/* Catalog tests — the position filtering that keeps the game screen uncluttered
 * (§8), and the guarantee that it never leaves the parent with a blank panel. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  STATS, STATS_BY_ID, UNIT_IDS, QUARTERS, POSITIONS,
  statsForUnit, defaultUnitFor
} from '../assets/js/catalog.js';

const labels = (unit, positions) => statsForUnit(unit, positions).map((s) => s.label);

test('every stat has a unique id and belongs to a real unit', () => {
  const ids = STATS.map((s) => s.id);
  assert.equal(new Set(ids).size, ids.length, 'duplicate stat id');
  for (const s of STATS) {
    assert.ok(UNIT_IDS.includes(s.unit), `${s.id} has unknown unit ${s.unit}`);
    assert.ok(s.label && s.group, `${s.id} is missing a label or group`);
  }
});

test('every position referenced by a stat exists', () => {
  const known = new Set(POSITIONS.map((p) => p.id));
  for (const s of STATS) {
    for (const p of s.positions) assert.ok(known.has(p), `${s.id} references unknown position ${p}`);
  }
});

test('quarters are Q1-Q4 plus overtime (§14)', () => {
  assert.deepEqual(QUARTERS, ['Q1', 'Q2', 'Q3', 'Q4', 'OT']);
});

test('a linebacker sees the brief\'s defensive button set (§9)', () => {
  assert.deepEqual(
    labels('defense', ['LB']),
    ['TACKLE', 'ASSIST', 'TFL', 'SACK', 'PRESSURE', 'PBU', 'INT', 'FF', 'FR', 'DEF TD']
  );
});

test('a quarterback sees passing stats and no receiving stats', () => {
  const qb = labels('offense', ['QB']);
  assert.ok(qb.includes('COMPLETE'));
  assert.ok(qb.includes('SACKED'));
  assert.ok(!qb.includes('CATCH'), 'a QB should not be offered a reception button');
  assert.ok(!qb.includes('TARGET'));
});

test('a running back sees rushing and receiving but not passing', () => {
  const rb = labels('offense', ['RB']);
  assert.ok(rb.includes('RUSH') && rb.includes('CATCH') && rb.includes('TARGET'));
  assert.ok(!rb.includes('COMPLETE'), 'a RB should not be offered passing stats');
});

test('a two-position athlete gets the union of their positions', () => {
  const lbrb = labels('offense', ['LB', 'RB']);
  assert.ok(lbrb.includes('RUSH') && lbrb.includes('CATCH'));
  assert.deepEqual(labels('defense', ['LB', 'RB']), labels('defense', ['LB']));
});

test('a kicker sees only kicking stats on special teams', () => {
  assert.deepEqual(labels('special_teams', ['K']), ['FG MADE', 'FG MISS', 'PAT MADE', 'PAT MISS']);
});

test('a position with nothing on a unit falls back to the whole unit, never a blank panel', () => {
  const lbOnOffense = statsForUnit('offense', ['LB']);
  assert.ok(lbOnOffense.length > 0, 'the panel must never be empty');
  assert.equal(lbOnOffense.length, STATS.filter((s) => s.unit === 'offense').length);
});

test('an athlete with no position set still gets a full, usable panel', () => {
  for (const unit of UNIT_IDS) {
    assert.ok(statsForUnit(unit, []).length > 0);
    assert.ok(statsForUnit(unit, undefined).length > 0);
  }
});

test('the game screen opens on the unit the athlete actually plays', () => {
  assert.equal(defaultUnitFor(['LB']), 'defense');
  assert.equal(defaultUnitFor(['QB']), 'offense');
  assert.equal(defaultUnitFor(['LB', 'RB']), 'defense');
  assert.equal(defaultUnitFor(['K']), 'special_teams');
  assert.equal(defaultUnitFor([]), 'defense');
});

test('yardage stats are the ones a parent would be asked to quantify', () => {
  const yardage = STATS.filter((s) => s.yardage).map((s) => s.id).sort();
  assert.deepEqual(yardage, ['kick_return', 'pass_complete', 'punt_return', 'reception', 'rush_att']);
});

test('there is no special-teams-play button that would double-count NEXT PLAY', () => {
  assert.equal(STATS_BY_ID.st_play, undefined);
});
