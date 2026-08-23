/* ============================================================================
 * PlayingTime Football — catalog.js
 * The vocabulary of the product: units, quarters, positions and statistics.
 *
 * This file is pure data plus small pure lookups. It has no DOM and no storage
 * dependency, so the engine tests import it directly under `node --test`.
 *
 * Design rule (build brief §8): the game screen shows only the statistics that
 * belong to the athlete's position. A parent tracking a linebacker must never
 * scroll past receiving stats to reach TACKLE.
 * ========================================================================== */

export const UNITS = [
  { id: 'offense',       label: 'Offense',       short: 'OFF' },
  { id: 'defense',       label: 'Defense',       short: 'DEF' },
  { id: 'special_teams', label: 'Special Teams', short: 'ST'  }
];

export const UNIT_IDS = UNITS.map((u) => u.id);

export const QUARTERS = ['Q1', 'Q2', 'Q3', 'Q4', 'OT'];

/* Positions a parent can pick for their athlete. `units` is the set of units the
 * position normally plays, used to pick sensible defaults on the game screen. */
export const POSITIONS = [
  { id: 'QB',  label: 'QB — Quarterback',      units: ['offense'] },
  { id: 'RB',  label: 'RB — Running Back',     units: ['offense', 'special_teams'] },
  { id: 'FB',  label: 'FB — Fullback',         units: ['offense', 'special_teams'] },
  { id: 'WR',  label: 'WR — Wide Receiver',    units: ['offense', 'special_teams'] },
  { id: 'TE',  label: 'TE — Tight End',        units: ['offense', 'special_teams'] },
  { id: 'OL',  label: 'OL — Offensive Line',   units: ['offense', 'special_teams'] },
  { id: 'DL',  label: 'DL — Defensive Line',   units: ['defense', 'special_teams'] },
  { id: 'LB',  label: 'LB — Linebacker',       units: ['defense', 'special_teams'] },
  { id: 'CB',  label: 'CB — Cornerback',       units: ['defense', 'special_teams'] },
  { id: 'S',   label: 'S — Safety',            units: ['defense', 'special_teams'] },
  { id: 'K',   label: 'K — Kicker',            units: ['special_teams'] },
  { id: 'P',   label: 'P — Punter',            units: ['special_teams'] },
  { id: 'RET', label: 'RET — Returner',        units: ['special_teams'] },
  { id: 'ATH', label: 'ATH — Athlete / Multiple positions', units: ['offense', 'defense', 'special_teams'] }
];

export const POSITION_IDS = POSITIONS.map((p) => p.id);

/* ---------------------------------------------------------------------------
 * Statistics
 *
 * id        stable key stored in the event log — never rename one in place
 * label     what the button says (kept short: it has to read at arm's length)
 * unit      which unit the stat belongs to
 * group     section heading in reports
 * yardage   true  -> tapping it opens the quick yardage sheet (§12)
 * positions positions that see this button; [] means "every position on the unit"
 * tone      button colour intent: 'good' | 'bad' | 'neutral'
 * ------------------------------------------------------------------------- */
export const STATS = [
  /* ---------------------------- Defense (§9) --------------------------- */
  { id: 'solo_tackle',   label: 'TACKLE',    unit: 'defense', group: 'Tackling',  yardage: false, positions: [], tone: 'good' },
  { id: 'assist_tackle', label: 'ASSIST',    unit: 'defense', group: 'Tackling',  yardage: false, positions: [], tone: 'good' },
  { id: 'tfl',           label: 'TFL',       unit: 'defense', group: 'Tackling',  yardage: false, positions: [], tone: 'good' },
  { id: 'sack',          label: 'SACK',      unit: 'defense', group: 'Pressure',  yardage: false, positions: [], tone: 'good' },
  { id: 'pressure',      label: 'PRESSURE',  unit: 'defense', group: 'Pressure',  yardage: false, positions: [], tone: 'good' },
  { id: 'pbu',           label: 'PBU',       unit: 'defense', group: 'Coverage',  yardage: false, positions: [], tone: 'good' },
  { id: 'interception',  label: 'INT',       unit: 'defense', group: 'Coverage',  yardage: false, positions: [], tone: 'good' },
  { id: 'forced_fumble', label: 'FF',        unit: 'defense', group: 'Takeaways', yardage: false, positions: [], tone: 'good' },
  { id: 'fumble_rec',    label: 'FR',        unit: 'defense', group: 'Takeaways', yardage: false, positions: [], tone: 'good' },
  { id: 'def_td',        label: 'DEF TD',    unit: 'defense', group: 'Scoring',   yardage: false, positions: [], tone: 'good' },

  /* ---------------------------- Offense (§10) -------------------------- */
  /* Passing. A completion implies an attempt, so the parent taps once and the
   * engine derives attempts = completions + incompletions. */
  { id: 'pass_complete',   label: 'COMPLETE',   unit: 'offense', group: 'Passing',   yardage: true,  positions: ['QB'], tone: 'good' },
  { id: 'pass_incomplete', label: 'INCOMPLETE', unit: 'offense', group: 'Passing',   yardage: false, positions: ['QB'], tone: 'neutral' },
  { id: 'pass_td',         label: 'PASS TD',    unit: 'offense', group: 'Passing',   yardage: false, positions: ['QB'], tone: 'good' },
  { id: 'pass_int',        label: 'INT THROWN', unit: 'offense', group: 'Passing',   yardage: false, positions: ['QB'], tone: 'bad'  },
  { id: 'sack_taken',      label: 'SACKED',     unit: 'offense', group: 'Passing',   yardage: false, positions: ['QB'], tone: 'bad'  },

  /* Rushing. */
  { id: 'rush_att', label: 'RUSH',    unit: 'offense', group: 'Rushing', yardage: true,  positions: ['QB', 'RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'good' },
  { id: 'rush_td',  label: 'RUSH TD', unit: 'offense', group: 'Rushing', yardage: false, positions: ['QB', 'RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'good' },

  /* Receiving. */
  { id: 'target',    label: 'TARGET',  unit: 'offense', group: 'Receiving', yardage: false, positions: ['RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'neutral' },
  { id: 'reception', label: 'CATCH',   unit: 'offense', group: 'Receiving', yardage: true,  positions: ['RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'good' },
  { id: 'rec_td',    label: 'REC TD',  unit: 'offense', group: 'Receiving', yardage: false, positions: ['RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'good' },
  { id: 'drop',      label: 'DROP',    unit: 'offense', group: 'Receiving', yardage: false, positions: ['RB', 'FB', 'WR', 'TE', 'ATH'], tone: 'bad'  },

  /* Shared offensive outcomes. */
  { id: 'two_point', label: '2-PT',   unit: 'offense', group: 'Scoring',   yardage: false, positions: [], tone: 'good' },
  { id: 'fumble',    label: 'FUMBLE', unit: 'offense', group: 'Ball security', yardage: false, positions: [], tone: 'bad' },

  /* ------------------------ Special teams (§11) ------------------------ */
  /* Note: there is deliberately no "special teams play" button. Special-teams
   * plays are counted by NEXT PLAY on the special-teams unit; a second button
   * for the same thing would double-count. */
  { id: 'kick_return',  label: 'KICK RET', unit: 'special_teams', group: 'Returns',  yardage: true,  positions: ['RB', 'WR', 'TE', 'CB', 'S', 'RET', 'ATH'], tone: 'good' },
  { id: 'punt_return',  label: 'PUNT RET', unit: 'special_teams', group: 'Returns',  yardage: true,  positions: ['RB', 'WR', 'TE', 'CB', 'S', 'RET', 'ATH'], tone: 'good' },
  { id: 'st_tackle',    label: 'ST TACKLE', unit: 'special_teams', group: 'Coverage', yardage: false, positions: ['RB', 'FB', 'WR', 'TE', 'DL', 'LB', 'CB', 'S', 'ATH'], tone: 'good' },
  { id: 'st_td',        label: 'ST TD',    unit: 'special_teams', group: 'Scoring',  yardage: false, positions: ['RB', 'WR', 'TE', 'CB', 'S', 'RET', 'ATH'], tone: 'good' },
  { id: 'fg_made',      label: 'FG MADE',  unit: 'special_teams', group: 'Kicking',  yardage: false, positions: ['K'], tone: 'good' },
  { id: 'fg_missed',    label: 'FG MISS',  unit: 'special_teams', group: 'Kicking',  yardage: false, positions: ['K'], tone: 'bad'  },
  { id: 'pat_made',     label: 'PAT MADE', unit: 'special_teams', group: 'Kicking',  yardage: false, positions: ['K'], tone: 'good' },
  { id: 'pat_missed',   label: 'PAT MISS', unit: 'special_teams', group: 'Kicking',  yardage: false, positions: ['K'], tone: 'bad'  }
];

export const STATS_BY_ID = Object.fromEntries(STATS.map((s) => [s.id, s]));

/* Quick yardage values offered when a yardage stat is tapped (§12). CUSTOM and
 * "no yards" are rendered by the UI, not listed here. "No yards" matters: a
 * parent who did not see the gain must still be able to record the attempt. */
export const YARDAGE_QUICK_VALUES = [-5, -2, 0, 2, 5, 10, 15, 20];

/**
 * The stat buttons to show for a unit given the athlete's positions.
 *
 * A stat with an empty `positions` list belongs to every position on that unit.
 * If the athlete plays no position associated with the unit — a linebacker whose
 * parent switches to OFFENSE — we return the unit's full set rather than an
 * empty panel. Showing nothing would look like a broken screen; showing the full
 * set is honest and still usable.
 *
 * @param {string} unitId
 * @param {string[]} positions athlete's positions, e.g. ['LB', 'RB']
 * @returns {Array} stat definitions, in catalog order
 */
export function statsForUnit(unitId, positions) {
  const unitStats = STATS.filter((s) => s.unit === unitId);
  const owned = (positions || []).filter(Boolean);
  if (owned.length === 0) return unitStats;

  const matched = unitStats.filter(
    (s) => s.positions.length === 0 || s.positions.some((p) => owned.includes(p))
  );

  /* Every stat left is a universal one (empty `positions`) => the athlete has no
   * position that actually plays this unit. Fall back to the whole unit. */
  const hasPositionSpecific = matched.some((s) => s.positions.length > 0);
  return hasPositionSpecific ? matched : unitStats;
}

/**
 * The unit a game screen should open on, given the athlete's positions.
 * A linebacker's parent should not have to tap DEFENSE first.
 */
export function defaultUnitFor(positions) {
  const owned = (positions || []).filter(Boolean);
  for (const id of owned) {
    const pos = POSITIONS.find((p) => p.id === id);
    if (pos && pos.units.length > 0 && pos.units[0] !== 'special_teams') return pos.units[0];
  }
  const first = POSITIONS.find((p) => p.id === owned[0]);
  return (first && first.units[0]) || 'defense';
}

export function positionLabel(id) {
  const p = POSITIONS.find((x) => x.id === id);
  return p ? p.label : id;
}

export function unitLabel(id) {
  const u = UNITS.find((x) => x.id === id);
  return u ? u.label : id;
}
