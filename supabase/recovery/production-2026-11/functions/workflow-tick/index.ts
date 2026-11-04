// Venuewise Core — Edge Function: workflow-tick
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  try {
    const secret = Deno.env.get("WF_TICK_SECRET");
    if (secret && req.headers.get("x-cron-secret") !== secret) {
      return json(401, { error: "unauthorized" });
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const svcKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const svc = createClient(url, svcKey);

    const { data, error } = await svc.rpc("wf_tick");
    if (error) return json(400, { error: error.message });
    return json(200, { ok: true, result: data });
  } catch (e) {
    return json(500, { error: String(e) });
  }
});
