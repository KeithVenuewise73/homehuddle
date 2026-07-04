/* ============================================================================
 * Venuewise Core — shared/workspace.js
 * The first real Core service. Resolves, for a signed-in person:
 *   • which workspaces they belong to
 *   • their role(s) in each
 *   • each workspace's branding
 *   • the parent/child workspace tree
 *
 * ⚠️ Read-only. Reads are RLS-scoped (workspace read-policies), so each query only
 * returns rows the signed-in person may see.
 *
 * Usage — pass the page's already-authenticated Supabase client (preferred), so the
 * resolver runs on the live session:
 *     const result = await VW.workspace.resolve(sb);
 * Or omit it to build one from /shared/config.js (requires config.js + a session):
 *     const result = await VW.workspace.resolve();
 * With no session it returns a well-formed EMPTY result rather than throwing.
 * ============================================================================ */
;(function (global) {
  'use strict';
  var VW = global.VW = global.VW || {};

  async function resolve(client) {
    // Prefer a client passed by the page (carries the live auth session);
    // otherwise fall back to a client built from /shared/config.js.
    var sb = client || (typeof VW.createClient === 'function' ? VW.createClient() : null);
    if (!sb) {
      throw new Error('[VW.workspace] pass a Supabase client to resolve(sb), or load /shared/config.js first.');
    }

    var EMPTY = {
      signedIn: false, personId: null, displayName: null,
      workspaces: [], roots: [], bySlug: {},
      get: function () { return null; }, hasRole: function () { return false; },
      isOwner: function () { return false; }, children: function () { return []; }
    };

    // Must be signed in. Anonymous visitors get an empty (not errored) result.
    const userRes = await sb.auth.getUser();
    const authUser = userRes && userRes.data && userRes.data.user;
    if (!authUser) return EMPTY;

    // Resolve this person's id (own row; allowed by existing people RLS).
    const { data: people } = await sb.from('people')
      .select('id, display_name').eq('auth_user_id', authUser.id).limit(1);
    const person = people && people[0];
    if (!person) return Object.assign({}, EMPTY, { signedIn: true });

    // Pull the pieces. Each query is RLS-scoped to what this person may see.
    const [wsRes, roleRes, brandRes] = await Promise.all([
      sb.from('business_workspaces')
        .select('id,slug,name,workspace_type,parent_workspace_id,industry_pack,status'),
      sb.from('workspace_roles').select('workspace_id,role'),
      sb.from('workspace_branding')
        .select('workspace_id,logo_url,primary_color,theme,footer_line,custom_domain')
    ]);

    const workspaces = wsRes.data || [];
    const roleByWs = {};
    (roleRes.data || []).forEach(function (r) {
      (roleByWs[r.workspace_id] = roleByWs[r.workspace_id] || []).push(r.role);
    });
    const brandByWs = {};
    (brandRes.data || []).forEach(function (b) { brandByWs[b.workspace_id] = b; });

    const byId = {};
    const list = workspaces.map(function (w) {
      const node = {
        id: w.id, slug: w.slug, name: w.name, type: w.workspace_type,
        industryPack: w.industry_pack, status: w.status, parentId: w.parent_workspace_id,
        roles: roleByWs[w.id] || [], branding: brandByWs[w.id] || null, children: []
      };
      byId[w.id] = node;
      return node;
    });
    list.forEach(function (n) {
      if (n.parentId && byId[n.parentId]) byId[n.parentId].children.push(n);
    });

    const bySlug = {};
    list.forEach(function (n) { bySlug[n.slug] = n; });

    return {
      signedIn: true,
      personId: person.id,
      displayName: person.display_name || null,
      workspaces: list,
      roots: list.filter(function (n) { return !n.parentId || !byId[n.parentId]; }),
      bySlug: bySlug,
      get: function (slug) { return bySlug[slug] || null; },
      hasRole: function (slug, role) {
        return !!bySlug[slug] && bySlug[slug].roles.indexOf(role) !== -1;
      },
      isOwner: function (slug) { return this.hasRole(slug, 'owner'); },
      children: function (slug) { return bySlug[slug] ? bySlug[slug].children : []; }
    };
  }

  VW.workspace = { resolve: resolve };

})(typeof window !== 'undefined' ? window : this);
