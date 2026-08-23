/* ============================================================================
 * PlayingTime Football — engine.js
 * Every number the product shows is derived here, from the event log.
 *
 * Build brief §26: do not store totals. Store plays and stat events, and compute
 * participation, statistics and season aggregates on read. That is what makes
 * quarter-by-quarter analysis, correction and later AI work possible without
 * rebuilding the database.
 *
 * This module is pure: same events in, same numbers out. No DOM, no storage, no
 * clock. That is why it can be tested directly (playingtime/tests).
 * ========================================================================== */

import { UNIT_IDS, QUARTERS, STATS_BY_ID, STATS } from './catalog.js';

/* --------------------------------------------------------------------------
 * Event shapes written by the store. Every event carries the context that was
 * true when it happened, so nothing has to be reconstructed by replaying UI
 * state.
 *
 *   { id, seq, ts, type: 'play', unit, quarter, athleteIn }
 *   { id, seq, ts, type: 'stat', unit, quarter, athleteIn, statId, yards|null }
 *   { id, seq, ts, type: 'score', quarter, side: 'us'|'them', points }
 * ------------------------------------------------------------------------ */

export const EVENT_TYPES = ['play', 'stat', 'score'];

function emptyUnitTally() {
  return { teamPlays: 0, athletePlays: 0, participation: 0 };
}

function emptyUnits() {
  const out = {};
  for (const id of UNIT_IDS) out[id] = emptyUnitTally();
  return out;
}

/**
 * Participation as a percentage, rounded to one decimal.
 * Zero team plays means the athlete's unit has not been on the field yet — that
 * is 0, not a divide-by-zero and not "100%".
 */
export function participation(athletePlays, teamPlays) {
  if (!teamPlays || teamPlays <= 0) return 0;
  return Math.round((athletePlays / teamPlays) * 1000) / 10;
}

/**
 * Blank stat tally: every stat id present with zeroes, so report rendering never
 * has to guard for missing keys and a stat with no events reads as 0, not blank.
 */
function emptyStats() {
  const out = {};
  for (const s of STATS) out[s.id] = { count: 0, yards: 0, yardsKnown: 0 };
  return out;
}

/**
 * Derived numbers a report shows that are not stored directly — totals that are
 * sums or unions of raw stats. Kept in one place so the game report, the season
 * dashboard and the share card can never disagree with each other.
 */
export function computeDerived(stats) {
  const c = (id) => (stats[id] ? stats[id].count : 0);
  const y = (id) => (stats[id] ? stats[id].yards : 0);
  return {
    /* Defense */
    tackles: c('solo_tackle') + c('assist_tackle'),
    soloTackles: c('solo_tackle'),
    assistedTackles: c('assist_tackle'),
    /* Passing */
    passAttempts: c('pass_complete') + c('pass_incomplete'),
    passCompletions: c('pass_complete'),
    passYards: y('pass_complete'),
    /* Rushing */
    rushAttempts: c('rush_att'),
    rushYards: y('rush_att'),
    /* Receiving */
    receptions: c('reception'),
    recYards: y('reception'),
    targets: c('target'),
    /* Special teams */
    kickReturnYards: y('kick_return'),
    puntReturnYards: y('punt_return'),
    /* Points the athlete personally accounted for. Kicking and 2-pt included. */
    pointsScored:
      6 * (c('rush_td') + c('rec_td') + c('def_td') + c('st_td')) +
      3 * c('fg_made') +
      2 * c('two_point') +
      1 * c('pat_made')
  };
}

/**
 * Fold one game's event log into everything the game screen and report display.
 *
 * @param {Array} events append-only log for a single game, any order
 * @returns {{units, totals, stats, derived, score, byQuarter, eventCount, lastEvent}}
 */
export function deriveGame(events) {
  const log = [...(events || [])].sort((a, b) => a.seq - b.seq);

  const units = emptyUnits();
  const stats = emptyStats();
  const score = { us: 0, them: 0 };
  const byQuarter = {};
  for (const q of QUARTERS) {
    byQuarter[q] = { units: emptyUnits(), stats: emptyStats(), score: { us: 0, them: 0 } };
  }

  for (const ev of log) {
    const q = byQuarter[ev.quarter] || null;

    if (ev.type === 'play') {
      const u = units[ev.unit];
      if (!u) continue;                       // unknown unit: ignore, never invent
      u.teamPlays += 1;
      if (ev.athleteIn) u.athletePlays += 1;
      if (q && q.units[ev.unit]) {
        q.units[ev.unit].teamPlays += 1;
        if (ev.athleteIn) q.units[ev.unit].athletePlays += 1;
      }
    } else if (ev.type === 'stat') {
      if (!STATS_BY_ID[ev.statId]) continue;  // unknown stat id: ignore
      const bump = (bucket) => {
        const s = bucket[ev.statId];
        s.count += 1;
        if (typeof ev.yards === 'number' && Number.isFinite(ev.yards)) {
          s.yards += ev.yards;
          s.yardsKnown += 1;
        }
      };
      bump(stats);
      if (q) bump(q.stats);
    } else if (ev.type === 'score') {
      const side = ev.side === 'them' ? 'them' : 'us';
      const pts = Number(ev.points) || 0;
      score[side] += pts;
      if (q) q.score[side] += pts;
    }
  }

  /* Participation percentages, per unit and overall. */
  let teamPlays = 0;
  let athletePlays = 0;
  for (const id of UNIT_IDS) {
    units[id].participation = participation(units[id].athletePlays, units[id].teamPlays);
    teamPlays += units[id].teamPlays;
    athletePlays += units[id].athletePlays;
  }
  for (const q of QUARTERS) {
    for (const id of UNIT_IDS) {
      const t = byQuarter[q].units[id];
      t.participation = participation(t.athletePlays, t.teamPlays);
    }
  }

  return {
    units,
    totals: { teamPlays, athletePlays, participation: participation(athletePlays, teamPlays) },
    stats,
    derived: computeDerived(stats),
    score,
    byQuarter,
    eventCount: log.length,
    lastEvent: log.length ? log[log.length - 1] : null
  };
}

/**
 * Fold many games into a season view (§18).
 *
 * `games` are metadata records; `eventsByGameId` maps game id -> event log.
 * Only games the caller passes in are counted — this never guesses at games it
 * cannot see.
 */
export function deriveSeason(games, eventsByGameId) {
  const units = emptyUnits();
  const stats = emptyStats();
  const perGame = [];

  for (const game of games || []) {
    const d = deriveGame(eventsByGameId[game.id] || []);
    for (const id of UNIT_IDS) {
      units[id].teamPlays += d.units[id].teamPlays;
      units[id].athletePlays += d.units[id].athletePlays;
    }
    for (const s of STATS) {
      stats[s.id].count += d.stats[s.id].count;
      stats[s.id].yards += d.stats[s.id].yards;
      stats[s.id].yardsKnown += d.stats[s.id].yardsKnown;
    }
    perGame.push({ game, derived: d });
  }

  let teamPlays = 0;
  let athletePlays = 0;
  for (const id of UNIT_IDS) {
    units[id].participation = participation(units[id].athletePlays, units[id].teamPlays);
    teamPlays += units[id].teamPlays;
    athletePlays += units[id].athletePlays;
  }

  return {
    gamesPlayed: perGame.length,
    units,
    totals: { teamPlays, athletePlays, participation: participation(athletePlays, teamPlays) },
    stats,
    derived: computeDerived(stats),
    perGame
  };
}

/**
 * The non-zero statistics for a unit, grouped for display. Reports show what the
 * athlete actually did; a wall of zeroes is noise, not information.
 */
export function statLines(stats, unitId) {
  const lines = [];
  for (const s of STATS) {
    if (unitId && s.unit !== unitId) continue;
    const tally = stats[s.id];
    if (!tally || tally.count === 0) continue;
    lines.push({
      id: s.id,
      label: s.label,
      group: s.group,
      unit: s.unit,
      count: tally.count,
      yards: s.yardage ? tally.yards : null,
      /* Yardage was optional at entry; say so rather than implying we know it. */
      yardsPartial: s.yardage && tally.yardsKnown < tally.count,
      yardsKnown: tally.yardsKnown
    });
  }
  return lines;
}

/** Did this game record anything at all? Drives "no data yet" copy. */
export function isEmptyGame(derived) {
  return derived.eventCount === 0;
}
