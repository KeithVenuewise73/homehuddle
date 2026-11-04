// supabase/functions/verify-phone/index.ts
//
// HomeHuddle phone verification (Twilio Verify) → auto-link.
//
// Two actions, one endpoint:
//   { "action": "send",  "phone": "+1716..." }
//        → tells Twilio Verify to text a code to that number.
//   { "action": "check", "phone": "+1716...", "code": "123456", "display_name": "Laurie" }
//        → asks Twilio if the code is valid; if so, calls public.verify_and_link()
//          (upsert verified person + auto-link family_access + back-fill person_id).
//
// SECRETS REQUIRED (set with `supabase secrets set ...`, never hard-coded):
//   TWILIO_ACCOUNT_SID   = <REDACTED:twilio_sid:4a04857c02fe>
//   TWILIO_AUTH_TOKEN    = (the secret Auth Token — NEVER paste into chat)
//   TWILIO_VERIFY_SID    = VAc03f307d18392e83aa743758f5b68df6
//   SUPABASE_URL         = (auto-injected by Supabase at deploy)
//   SUPABASE_SERVICE_ROLE_KEY = (auto-injected by Supabase at deploy)
//
// NOTE: verify_and_link() is granted to service_role only, so this function
// (using the service-role key) is the trusted server-side caller. The phone
// that gets linked is the SAME phone Twilio just confirmed a code for — a
// caller cannot link a number they can't receive a text at.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_AUTH_TOKEN  = Deno.env.get("TWILIO_AUTH_TOKEN")!;
const TWILIO_VERIFY_SID  = Deno.env.get("TWILIO_VERIFY_SID")!;
const SUPABASE_URL       = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY   = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*", // tighten to https://venuewise.net before public launch
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const E164 = /^\+[1-9]\d{6,14}$/;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Twilio REST helper (Basic auth = AccountSID:AuthToken, form-encoded body).
async function twilio(path: string, form: Record<string, string>) {
  const url = `https://verify.twilio.com/v2/Services/${TWILIO_VERIFY_SID}/${path}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": "Basic " + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(form).toString(),
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST")   return json({ error: "POST only" }, 405);

  let payload: any;
  try { payload = await req.json(); }
  catch { return json({ error: "invalid JSON body" }, 400); }

  const action = String(payload.action ?? "");
  const phone  = String(payload.phone ?? "").trim();

  if (!E164.test(phone)) {
    return json({ error: "phone must be E.164, e.g. +17165551234" }, 400);
  }

  // ---- SEND: text a verification code ---------------------------------
  if (action === "send") {
    const r = await twilio("Verifications", { To: phone, Channel: "sms" });
    if (!r.ok) {
      return json({ error: "twilio_send_failed", detail: r.data?.message ?? null }, 502);
    }
    return json({ status: r.data.status }); // "pending"
  }

  // ---- CHECK: validate code, then link --------------------------------
  if (action === "check") {
    const code = String(payload.code ?? "").trim();
    if (!/^\d{4,10}$/.test(code)) {
      return json({ error: "code must be 4-10 digits" }, 400);
    }

    const r = await twilio("VerificationCheck", { To: phone, Code: code });
    if (!r.ok) {
      return json({ error: "twilio_check_failed", detail: r.data?.message ?? null }, 502);
    }
    if (r.data.status !== "approved") {
      return json({ verified: false, status: r.data.status }, 401); // wrong/expired code
    }

    // Code is valid → run the tested DB function with the service role.
    const supa = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data, error } = await supa.rpc("verify_and_link", {
      p_phone: phone,
      p_auth_user_id: payload.auth_user_id ?? null,
      p_display_name: payload.display_name ?? null,
    });

    if (error) {
      return json({ verified: true, linked: false, error: error.message }, 500);
    }
    return json({ verified: true, linked: true, person_id: data });
  }

  return json({ error: "unknown action (use 'send' or 'check')" }, 400);
});