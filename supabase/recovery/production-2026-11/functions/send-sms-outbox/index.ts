import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TWILIO_SID   = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN")!;
const TWILIO_FROM  = Deno.env.get("TWILIO_FROM_NUMBER")!;
const OUTBOX_SECRET = Deno.env.get("OUTBOX_SECRET") || "";

const BATCH = 20;          // max sends per invocation (rate safety)
const MAX_ATTEMPTS = 3;    // give up on a row after this many tries

Deno.serve(async (req: Request) => {
  // Optional shared-secret guard. Enforced ONLY if OUTBOX_SECRET is configured,
  // so it can be hardened (set the secret + pass x-outbox-secret from cron)
  // without code changes.
  if (OUTBOX_SECRET) {
    const provided = req.headers.get("x-outbox-secret") || "";
    if (provided !== OUTBOX_SECRET) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }
  }

  const sb = createClient(SUPABASE_URL, SERVICE_KEY);

  const { data: rows, error } = await sb
    .from("sms_outbox")
    .select("id, person_id, phone, message, attempts")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(BATCH);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ sent: 0, failed: 0, skipped: 0, note: "nothing pending" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  let sent = 0, failed = 0, skipped = 0;
  const nowIso = () => new Date().toISOString();

  for (const row of rows) {
    // Re-check opt-in at send time (person may have opted out after enqueue).
    const { data: person } = await sb
      .from("people").select("sms_opt_in").eq("id", row.person_id).single();
    if (person && person.sms_opt_in === false) {
      await sb.from("sms_outbox")
        .update({ status: "skipped", error: "opted_out", sent_at: nowIso() })
        .eq("id", row.id);
      skipped++;
      continue;
    }

    const attempts = (row.attempts || 0) + 1;
    try {
      const body = new URLSearchParams({ To: row.phone, From: TWILIO_FROM, Body: row.message });
      const resp = await fetch(
        `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json`,
        {
          method: "POST",
          headers: {
            "Authorization": "Basic " + btoa(`${TWILIO_SID}:${TWILIO_TOKEN}`),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: body.toString(),
        },
      );
      const result = await resp.json().catch(() => ({}));
      if (resp.ok) {
        await sb.from("sms_outbox")
          .update({ status: "sent", sent_at: nowIso(), attempts })
          .eq("id", row.id);
        sent++;
      } else {
        const status = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
        await sb.from("sms_outbox")
          .update({ status, attempts, error: String(result?.message || result?.code || "twilio_error") })
          .eq("id", row.id);
        failed++;
      }
    } catch (e) {
      const status = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
      await sb.from("sms_outbox")
        .update({ status, attempts, error: String(e) })
        .eq("id", row.id);
      failed++;
    }

    await new Promise((r) => setTimeout(r, 250)); // gentle pacing
  }

  return new Response(JSON.stringify({ sent, failed, skipped, processed: rows.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
