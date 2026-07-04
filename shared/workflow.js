/* ============================================================================
 * Venuewise Core — shared/workflow.js  (READ-ONLY client)
 * The browser client for the Workflow Engine. This milestone is read-only:
 *   • VW.workflow.myTasks(client, opts)  — tasks assigned to the current person
 *   • VW.workflow.instance(client, id)   — one instance with stages/tasks/events
 *
 * ⚠️ ADDITIVE — adopted by NO page yet. Reads are RLS-scoped, so results only
 * include what the signed-in person may see. NO writes are performed here;
 * starting/advancing workflows arrives with the orchestrator in a later milestone.
 *
 * Usage (pass the page's authenticated client, like workspace.js):
 *   const { tasks } = await VW.workflow.myTasks(sb, { status: ['pending','in_progress'] });
 *   const inst      = await VW.workflow.instance(sb, instanceId);
 * ============================================================================ */
;(function (global) {
  'use strict';
  var VW = global.VW = global.VW || {};

  function getClient(client) {
    var sb = client || (typeof VW.createClient === 'function' ? VW.createClient() : null);
    if (!sb) throw new Error('[VW.workflow] pass a Supabase client, or load /shared/config.js first.');
    return sb;
  }

  async function currentPersonId(sb) {
    const userRes = await sb.auth.getUser();
    const authUser = userRes && userRes.data && userRes.data.user;
    if (!authUser) return null;
    const { data } = await sb.from('people').select('id').eq('auth_user_id', authUser.id).limit(1);
    return (data && data[0]) ? data[0].id : null;
  }

  // Tasks assigned to the current person. Defaults to open tasks; pass opts.status
  // (string or array) to filter, or opts.all=true for every status.
  async function myTasks(client, opts) {
    opts = opts || {};
    const sb = getClient(client);
    const personId = await currentPersonId(sb);
    if (!personId) return { signedIn: false, personId: null, tasks: [] };

    let q = sb.from('workflow_tasks')
      .select('id,instance_id,workspace_id,key,name,task_type,status,due_at,required,assignee_role,created_at')
      .eq('assignee_person_id', personId)
      .order('due_at', { ascending: true, nullsFirst: false });

    if (opts.status) {
      q = Array.isArray(opts.status) ? q.in('status', opts.status) : q.eq('status', opts.status);
    } else if (!opts.all) {
      q = q.in('status', ['pending', 'in_progress', 'blocked']); // default: open tasks
    }

    const { data, error } = await q;
    return { signedIn: true, personId: personId, tasks: data || [], error: error || null };
  }

  // One instance with its stages, tasks, approvals, and audit events (all RLS-scoped).
  async function instance(client, instanceId) {
    const sb = getClient(client);
    const [instRes, stagesRes, tasksRes, apprRes, eventsRes] = await Promise.all([
      sb.from('workflow_instances').select('*').eq('id', instanceId).limit(1),
      sb.from('workflow_instance_stages').select('*').eq('instance_id', instanceId).order('position', { ascending: true }),
      sb.from('workflow_tasks').select('*').eq('instance_id', instanceId).order('created_at', { ascending: true }),
      sb.from('workflow_approvals').select('*').eq('instance_id', instanceId),
      sb.from('workflow_events').select('*').eq('instance_id', instanceId).order('created_at', { ascending: true })
    ]);
    const inst = instRes.data && instRes.data[0];
    if (!inst) return null;
    return Object.assign({}, inst, {
      stages: stagesRes.data || [],
      tasks: tasksRes.data || [],
      approvals: apprRes.data || [],
      events: eventsRes.data || []
    });
  }

  VW.workflow = { myTasks: myTasks, instance: instance };

})(typeof window !== 'undefined' ? window : this);
