/* Engine tests — participation arithmetic, stat aggregation, season rollups.
 * These are the numbers a parent trusts, so they are pinned to the worked
 * examples in the build brief (§6, §17, §18) rather than to whatever the code
 * happens to produce. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  deriveGame, deriveSeason, participation, computeDerived, statLines
} from '../assets/js/engine.js';

let seq = 0;
const reset = () => { seq = 0; };
const play = (unit, quarter, athleteIn) =>
  ({ id: `e${seq}`, seq: seq++, ts: '', type: 'play', unit, quarter, athleteIn });
const stat = (unit, quarter, statId, yards = null) =>
  ({ id: `e${seq}`, seq: seq++, ts: '', type: 'stat', unit, quarter, athleteIn: true, statId, yards });
const score = (quarter, side, points) =>
  ({ id: `e${seq}`, seq: seq++, ts: '', type: 'score', quarter, side, points });

test('participation: no team plays is 0, never a divide-by-zero or a fake 100%', () => {
  assert.equal(participation(0, 0), 0);
  assert.equal(participation(5, 0), 0);
});

test('participation rounds to one decimal', () => {
  assert.equal(participation(37, 51), 72.5);
  assert.equal(participation(8, 12), 66.7);
  assert.equal(participation(1, 3), 33.3);
  assert.equal(participation(1, 1), 100);
});

test('brief §6 worked example: 37 of 52 defensive plays is 71.2%', () => {
  reset();
  const events = [];
  for (let i = 0; i < 52; i++) events.push(play('defense', 'Q1', i < 37));
  const d = deriveGame(events);
  assert.equal(d.units.defense.teamPlays, 52);
  assert.equal(d.units.defense.athletePlays, 37);
  assert.equal(d.units.defense.participation, 71.2);
});

test('brief §17 worked example: full game report reproduces exactly', () => {
  reset();
  const events = [];
  for (let i = 0; i < 51; i++) events.push(play('defense', 'Q1', i < 37));
  for (let i = 0; i < 12; i++) events.push(play('special_teams', 'Q2', i < 8));
  for (let i = 0; i < 5; i++) events.push(stat('defense', 'Q1', 'solo_tackle'));
  for (let i = 0; i < 3; i++) events.push(stat('defense', 'Q1', 'assist_tackle'));
  events.push(stat('defense', 'Q2', 'tfl'), stat('defense', 'Q2', 'tfl'));
  events.push(stat('defense', 'Q3', 'sack'));
  events.push(stat('defense', 'Q3', 'pressure'), stat('defense', 'Q4', 'pressure'));
  events.push(stat('defense', 'Q4', 'pbu'));

  const d = deriveGame(events);
  assert.equal(d.units.defense.athletePlays, 37);
  assert.equal(d.units.defense.teamPlays, 51);
  assert.equal(d.units.defense.participation, 72.5);
  assert.equal(d.units.special_teams.athletePlays, 8);
  assert.equal(d.units.special_teams.teamPlays, 12);
  assert.equal(d.units.special_teams.participation, 66.7);
  assert.equal(d.totals.athletePlays, 45);
  assert.equal(d.totals.teamPlays, 63);

  assert.equal(d.derived.tackles, 8);
  assert.equal(d.derived.soloTackles, 5);
  assert.equal(d.derived.assistedTackles, 3);
  assert.equal(d.stats.tfl.count, 2);
  assert.equal(d.stats.sack.count, 1);
  assert.equal(d.stats.pressure.count, 2);
  assert.equal(d.stats.pbu.count, 1);
});

test('plays recorded while the athlete is OUT count for the team only', () => {
  reset();
  const d = deriveGame([
    play('offense', 'Q1', true), play('offense', 'Q1', false), play('offense', 'Q1', false)
  ]);
  assert.equal(d.units.offense.teamPlays, 3);
  assert.equal(d.units.offense.athletePlays, 1);
  assert.equal(d.units.offense.participation, 33.3);
});

test('each unit counts separately and totals are the sum of the three', () => {
  reset();
  const d = deriveGame([
    play('offense', 'Q1', true), play('offense', 'Q1', true),
    play('defense', 'Q1', true), play('defense', 'Q1', false),
    play('special_teams', 'Q1', true)
  ]);
  assert.equal(d.units.offense.athletePlays, 2);
  assert.equal(d.units.defense.athletePlays, 1);
  assert.equal(d.units.special_teams.athletePlays, 1);
  assert.equal(d.totals.teamPlays, 5);
  assert.equal(d.totals.athletePlays, 4);
});

test('yardage sums, and missing yardage is tracked rather than counted as zero', () => {
  reset();
  const d = deriveGame([
    stat('offense', 'Q1', 'rush_att', 5),
    stat('offense', 'Q1', 'rush_att', -2),
    stat('offense', 'Q1', 'rush_att', null)   // parent did not see the gain
  ]);
  assert.equal(d.stats.rush_att.count, 3);
  assert.equal(d.stats.rush_att.yards, 3);
  assert.equal(d.stats.rush_att.yardsKnown, 2);

  const [line] = statLines(d.stats, 'offense');
  assert.equal(line.id, 'rush_att');
  assert.equal(line.yardsPartial, true, 'report must say the yardage is incomplete');
  assert.equal(line.yardsKnown, 2);
});

test('pass attempts are derived from completions plus incompletions', () => {
  reset();
  const d = deriveGame([
    stat('offense', 'Q1', 'pass_complete', 12),
    stat('offense', 'Q1', 'pass_complete', 8),
    stat('offense', 'Q1', 'pass_incomplete')
  ]);
  assert.equal(d.derived.passAttempts, 3);
  assert.equal(d.derived.passCompletions, 2);
  assert.equal(d.derived.passYards, 20);
});

test('points scored counts touchdowns, field goals, PATs and two-point plays', () => {
  const stats = computeDerived({
    rush_td: { count: 1, yards: 0, yardsKnown: 0 },
    rec_td: { count: 1, yards: 0, yardsKnown: 0 },
    def_td: { count: 0, yards: 0, yardsKnown: 0 },
    st_td: { count: 0, yards: 0, yardsKnown: 0 },
    fg_made: { count: 2, yards: 0, yardsKnown: 0 },
    two_point: { count: 1, yards: 0, yardsKnown: 0 },
    pat_made: { count: 3, yards: 0, yardsKnown: 0 }
  });
  assert.equal(stats.pointsScored, 6 + 6 + 6 + 2 + 3);
});

test('quarter breakdown attributes each event to the quarter it happened in', () => {
  reset();
  const d = deriveGame([
    play('defense', 'Q1', true), play('defense', 'Q1', true),
    play('defense', 'Q3', true), play('defense', 'Q3', false),
    stat('defense', 'Q3', 'sack')
  ]);
  assert.equal(d.byQuarter.Q1.units.defense.teamPlays, 2);
  assert.equal(d.byQuarter.Q1.units.defense.participation, 100);
  assert.equal(d.byQuarter.Q3.units.defense.teamPlays, 2);
  assert.equal(d.byQuarter.Q3.units.defense.participation, 50);
  assert.equal(d.byQuarter.Q3.stats.sack.count, 1);
  assert.equal(d.byQuarter.Q2.units.defense.teamPlays, 0);
});

test('score is tracked per side and per quarter', () => {
  reset();
  const d = deriveGame([score('Q1', 'us', 6), score('Q1', 'us', 1), score('Q2', 'them', 3)]);
  assert.equal(d.score.us, 7);
  assert.equal(d.score.them, 3);
  assert.equal(d.byQuarter.Q1.score.us, 7);
  assert.equal(d.byQuarter.Q2.score.them, 3);
});

test('events are folded in seq order regardless of the order they arrive in', () => {
  reset();
  const a = play('defense', 'Q1', true);
  const b = play('defense', 'Q1', false);
  assert.deepEqual(deriveGame([b, a]).units.defense, deriveGame([a, b]).units.defense);
});

test('unknown units and unknown stat ids are ignored, never invented', () => {
  reset();
  const d = deriveGame([
    { id: 'x', seq: 1, type: 'play', unit: 'kickoff_team', quarter: 'Q1', athleteIn: true },
    { id: 'y', seq: 2, type: 'stat', unit: 'defense', quarter: 'Q1', statId: 'hurdle', yards: null }
  ]);
  assert.equal(d.totals.teamPlays, 0);
  assert.equal(statLines(d.stats, null).length, 0);
});

test('an empty game reports nothing rather than zeroes that look like results', () => {
  const d = deriveGame([]);
  assert.equal(d.eventCount, 0);
  assert.equal(d.totals.participation, 0);
  assert.equal(statLines(d.stats, null).length, 0);
});

test('season totals add up across games (brief §18)', () => {
  reset();
  const g1 = [];
  for (let i = 0; i < 50; i++) g1.push(play('defense', 'Q1', i < 40));
  g1.push(stat('defense', 'Q1', 'solo_tackle'), stat('defense', 'Q1', 'solo_tackle'));

  const g2 = [];
  for (let i = 0; i < 50; i++) g2.push(play('defense', 'Q1', i < 30));
  g2.push(stat('defense', 'Q1', 'solo_tackle'), stat('defense', 'Q1', 'assist_tackle'));

  const season = deriveSeason(
    [{ id: 'a' }, { id: 'b' }],
    { a: g1, b: g2 }
  );
  assert.equal(season.gamesPlayed, 2);
  assert.equal(season.units.defense.teamPlays, 100);
  assert.equal(season.units.defense.athletePlays, 70);
  assert.equal(season.units.defense.participation, 70);
  assert.equal(season.derived.tackles, 4);
  assert.equal(season.derived.soloTackles, 3);
});

test('season participation is plays over opportunities, not the mean of game percentages', () => {
  reset();
  /* 1 of 2 in a short game, 90 of 100 in a long one. The mean of the two game
   * percentages is 70%; the honest season rate is 89.2%. */
  const short_ = [play('defense', 'Q1', true), play('defense', 'Q1', false)];
  const long_ = [];
  for (let i = 0; i < 100; i++) long_.push(play('defense', 'Q1', i < 90));
  const season = deriveSeason([{ id: 'a' }, { id: 'b' }], { a: short_, b: long_ });
  assert.equal(season.totals.participation, 89.2);
});

test('a season with no games reports zero games, not an empty-looking average', () => {
  const season = deriveSeason([], {});
  assert.equal(season.gamesPlayed, 0);
  assert.equal(season.totals.participation, 0);
});
