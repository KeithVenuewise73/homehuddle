/* ============================================================================
 * PlayingTime Football — sync.js
 * The honest account of where this athlete's data actually lives.
 *
 * There is no "Sync now" button in V1, because there is nothing on the other end
 * of it yet. The PlayingTime schema is written (playingtime/db/0001_playingtime.sql)
 * but it has not been applied to any database — HL-BOS standing constraint: no
 * migration is applied without explicit approval.
 *
 * So this module reports status. It does not pretend. A button that cannot do its
 * job reads as protection that is not there, and this app is a parent's only copy
 * of their child's season.
 *
 * When the migration is approved and applied, this module is where the real
 * client goes: `probe()` starts returning `available: true`, Settings grows a
 * real control, and store.js gains a push/pull adapter behind the same seam.
 * ========================================================================== */

/* The Venuewise Platform project that HomeHuddle already uses. PlayingTime would
 * be an additive schema inside it. Declared here so the eventual switch is a
 * one-file change, and so the Settings panel can name the project it is waiting
 * on rather than saying a vague "not connected". */
export const TARGET = {
  project: 'Venuewise Platform',
  projectRef: 'urwnbskrtoplgnkkxuvl',
  migration: 'playingtime/db/0001_playingtime.sql'
};

export const SYNC_STATE = {
  UNCONFIGURED: 'unconfigured',
  READY: 'ready'
};

/**
 * What is true about cloud sync right now.
 *
 * This is deliberately not a network call. Sync is not "down"; it has never been
 * switched on, and the reason is a decision nobody has taken yet rather than a
 * failure to reach a server. Reporting a connection error would be a lie about
 * a different problem.
 */
export function status() {
  return {
    state: SYNC_STATE.UNCONFIGURED,
    available: false,
    headline: 'Your data is on this device only.',
    detail:
      'Cloud sync is not switched on. The PlayingTime database schema is written and ' +
      'reviewed, but it has not been applied to any database — applying it is a decision ' +
      'for the account owner, not something this app does on its own.',
    unblockedBy:
      `Apply ${TARGET.migration} to the ${TARGET.project} project, then sign-in and sync can be enabled.`,
    /* What the parent should do in the meantime — a real, working alternative,
     * not a placeholder. Export produces a file they can keep. */
    mitigation: 'Until then, use Export data in Settings to keep your own backup.'
  };
}

/**
 * Whether the UI should offer any cloud control at all. False in V1, and every
 * caller checks it — that is what keeps a dead button off the screen.
 */
export function isAvailable() {
  return status().available;
}
