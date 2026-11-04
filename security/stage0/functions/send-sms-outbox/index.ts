// send-sms-outbox — PROPOSED v7 (SEC-10 + Twilio containment). NOT DEPLOYED.
// Changes vs deployed v6:
//   1. OUTBOX_SECRET is REQUIRED (fail-closed) — the optional guard is removed.
//   2. Circuit breaker: if the last BREAKER_WINDOW attempts were all failures, stop
//      before calling Twilio (prevents 720 failed calls/day during a provider outage).
//   3. Stale-message guard: rows older than MAX_AGE_HOURS are marked 'expired' instead of sent
//      (prevents old reminders/consent requests being delivered after a restoration).
//   4. Per-phone daily cap (DAILY_CAP_PER_PHONE).
// Send loop, opt-in re-check, retry/attempt logic otherwise unchanged from v6.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { json, requireSharedSecret } from "../_shared/guards.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TWILIO_SID   = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN")!;
const TWILIO_FROM  = Deno.env.get("TWILIO_FROM_NUMBER")!;
const OUTBOX_SECRET = Deno.env.get("OUTBOX_SECRET");

const BATCH = 20;
const MAX_ATTEMPTS = 3;
const MAX_AGE_HOURS = Number(Deno.env.get("OUTBOX_MAX_AGE_HOURS") ?? "48");
const BREAKER_WINDOW = Number(Deno.env.get("OUTBOX_BREAKER_WINDOW") ?? "10");
const DAILY_CAP_PER_PHONE = Number(Deno.env.get("OUTBOX_DAILY_CAP") ?? "10");

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const denied = requireSharedSecret(req, "x-outbox-secret", OUTBOX_SECRET);
  if (denied) return denied;

  const sb = createClient(SUPABASE_URL, SERVICE_KEY);
  const nowIso = () => new Date().toISOString();

  // Circuit breaker on recent outcomes.
  const { data: recent } = await sb
    .from("sms_outbox").select("status").not("sent_at", "is", null)
    .order("sent_at", { ascending: false }).limit(BREAKER_WINDOW);
  if (recent && recent.length >= BREAKER_WINDOW && recent.every((r: any) => r.status === "failed")) {
    return json({ sent: 0, failed: 0, skipped: 0, note: "breaker_open: last attempts all failed; not calling provider" });
  }

  const { data: rows, error } = await sb
    .from("sms_outbox")
    .select("id, person_id, phone, message, attempts, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .limit(BATCH);
  if (error) return json({ error: error.message }, 500);
  if (!rows || rows.length === 0) return json({ sent: 0, failed: 0, skipped: 0, note: "nothing pending" });

  let sent = 0, failed = 0, skipped = 0, expired = 0;
  const cutoff = Date.now() - MAX_AGE_HOURS * 3600 * 1000;

  for (const row of rows) {
    // Stale guard.
    if (new Date(row.created_at).getTime() < cutoff) {
      await sb.from("sms_outbox").update({ status: "expired", error: `older_than_${MAX_AGE_HOURS}h`, sent_at: nowIso() }).eq("id", row.id);
      expired++;
      continue;
    }
    // Opt-in re-check at send time.
    const { data: person } = await sb.from("people").select("sms_opt_in").eq("id", row.person_id).single();
    if (person && person.sms_opt_in === false) {
      await sb.from("sms_outbox").update({ status: "skipped", error: "opted_out", sent_at: nowIso() }).eq("id", row.id);
      skipped++;
      continue;
    }
    // Daily cap per phone.
    const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const { count } = await sb.from("sms_outbox").select("id", { count: "exact", head: true })
      .eq("phone", row.phone).eq("status", "sent").gte("sent_at", since);
    if ((count ?? 0) >= DAILY_CAP_PER_PHONE) {
      await sb.from("sms_outbox").update({ status: "skipped", error: "daily_cap", sent_at: nowIso() }).eq("id", row.id);
      skipped++;
      continue;
    }

    const attempts = (row.attempts || 0) + 1;
    try {
      const body = new URLSearchParams({ To: row.phone, From: TWILIO_FROM, Body: row.message });
      const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${TWILIO_SID}/Messages.json`, {
        method: "POST",
        headers: {
          "Authorization": "Basic " + btoa(`${TWILIO_SID}:${TWILIO_TOKEN}`),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: body.toString(),
      });
      const result = await resp.json().catch(() => ({}));
      if (resp.ok) {
        await sb.from("sms_outbox").update({ status: "sent", sent_at: nowIso(), attempts }).eq("id", row.id);
        sent++;
      } else {
        const status = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
        await sb.from("sms_outbox").update({ status, attempts, error: String(result?.message || result?.code || "twilio_error"), sent_at: status === "failed" ? nowIso() : null }).eq("id", row.id);
        failed++;
      }
    } catch (e) {
      const status = attempts >= MAX_ATTEMPTS ? "failed" : "pending";
      await sb.from("sms_outbox").update({ status, attempts, error: String(e), sent_at: status === "failed" ? nowIso() : null }).eq("id", row.id);
      failed++;
    }
    await new Promise((r) => setTimeout(r, 250));
  }

  return json({ sent, failed, skipped, expired, processed: rows.length });
});
