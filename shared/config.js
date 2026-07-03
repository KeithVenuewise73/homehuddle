/* ============================================================================
 * Venuewise Core — shared/config.js
 * Single source of truth for Supabase connection config.
 *
 * ⚠️ ADDITIVE SCAFFOLD — NOTHING ADOPTS THIS YET.
 * No existing page references this file. HomeHuddle behavior is unchanged.
 * Pages will migrate to this module ONE AT A TIME in later milestones; until a
 * page is explicitly migrated, its own inline config remains authoritative.
 *
 * This kills the root cause of the anon-key/URL being copy-pasted across ~18
 * files: once pages adopt it, there is exactly one place to change.
 *
 * The anon key below is the PUBLIC key (JWT, role "anon"), protected by Row
 * Level Security. It is the same value already present in the existing pages and
 * is safe to expose. It is NOT a secret. (Do not ever put the service_role key
 * or any sk_live/sk_test Stripe key in a client file.)
 *
 * Usage is classic-script friendly (no build step):
 *     <script src="/shared/config.js"></script>
 *     <script>
 *       const sb = window.VW.createClient();   // requires supabase-js already loaded
 *     </script>
 * ============================================================================ */
;(function (global) {
  'use strict';

  var VW = global.VW = global.VW || {};

  VW.config = {
    // Project: "Venuewise Platform" (urwnbskrtoplgnkkxuvl), Postgres 17, us-east-1
    supabaseUrl: 'https://urwnbskrtoplgnkkxuvl.supabase.co',
    projectRef: 'urwnbskrtoplgnkkxuvl',

    // Legacy anon key (JWT) — matches the value currently used across existing pages.
    supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyd25ic2tydG9wbGdua2t4dXZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwNDgyMjMsImV4cCI6MjA5NDYyNDIyM30._BpvQsf6Ub5nwxY8jD3aGDLvyk0-_vBA4s6LREZ9ShQ',

    // Modern publishable key (recommended future rotation; independently revocable).
    // Not yet used anywhere — kept here so the eventual switch is a one-line change.
    supabasePublishableKey: 'sb_publishable_NnATRFU2t1ATOHR07mFLoQ_ptkdjGDT'
  };

  /**
   * Convenience factory for future adoption (UNUSED today).
   * Returns a memoized Supabase client built from VW.config.
   * Requires the supabase-js CDN client to already be loaded on the page.
   */
  VW.createClient = function createClient() {
    if (!global.supabase || typeof global.supabase.createClient !== 'function') {
      throw new Error('[VW] supabase-js not loaded. Include the supabase-js CDN <script> before calling VW.createClient().');
    }
    if (!VW._client) {
      VW._client = global.supabase.createClient(VW.config.supabaseUrl, VW.config.supabaseAnonKey);
    }
    return VW._client;
  };

})(typeof window !== 'undefined' ? window : this);
