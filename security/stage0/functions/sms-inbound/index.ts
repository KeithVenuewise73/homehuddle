// sms-inbound — PROPOSED v5 (SEC-9 remediation). NOT DEPLOYED.
// Change vs deployed v4: every request must carry a valid X-Twilio-Signature computed
// over the public webhook URL (SMS_INBOUND_PUBLIC_URL) and the form parameters.
// Behaviour after the signature check is byte-for-byte the deployed v4 logic.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { formToRecord, verifyTwilioSignature } from "../_shared/guards.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN");
// The exact URL configured in the Twilio console for inbound messages, e.g.
// https://<ref>.supabase.co/functions/v1/sms-inbound  (gateway strips nothing Twilio signed)
const PUBLIC_URL = Deno.env.get("SMS_INBOUND_PUBLIC_URL") ?? `${SUPABASE_URL}/functions/v1/sms-inbound`;

const OPT_OUT = ["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"];
const OPT_IN  = ["YES", "START", "UNSTOP"];

function normPhone(p: string): string {
  const d = (p || "").replace(/\D/g, "");
  if (d.length === 10) return "+1" + d;
  if (d.length === 11 && d[0] === "1") return "+" + d;
  if ((p || "").startsWith("+")) return p;
  return p;
}

const twiml = () =>
  new Response('<?xml version="1.0" encoding="UTF-8"?><Response/>', {
    headers: { "Content-Type": "text/xml" },
  });

async function familiesGovernedBy(sb: any, phone: string): Promise<string[]> {
  const ids = new Set<string>();
  const { data: person } = await sb.from("people").select("id").eq("phone", phone).maybeSingle();
  if (person?.id) {
    const { data: acc } = await sb
      .from("family_access").select("family_id")
      .eq("person_id", person.id).eq("role", "owner").eq("status", "active");
    (acc || []).forEach((r: any) => ids.add(r.family_id));
  }
  const { data: mem } = await sb
    .from("family_members").select("family_id")
    .eq("phone", phone).in("role", ["parent", "guardian"]);
  (mem || []).forEach((r: any) => ids.add(r.family_id));
  return [...ids];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  let params: Record<string, string>;
  try {
    params = formToRecord(await req.formData());
  } catch (_) {
    return new Response("Bad request", { status: 400 });
  }

  // SEC-9: reject anything Twilio did not sign. Fail closed if the token is not configured.
  const ok = await verifyTwilioSignature(TWILIO_AUTH_TOKEN, PUBLIC_URL, params, req.headers.get("x-twilio-signature"));
  if (!ok) return new Response("Forbidden", { status: 403 });

  const from = String(params["From"] || "");
  const body = String(params["Body"] || "").trim().toUpperCase();
  if (!from) return twiml();

  const phone = normPhone(from);
  const sb = createClient(SUPABASE_URL, SERVICE_KEY);

  if (OPT_OUT.includes(body)) {
    await sb.from("people").update({ sms_opt_in: false }).eq("phone", phone);
    await sb.from("family_members").update({ sms_status: "declined" }).eq("phone", phone);
    try {
      const fams = await familiesGovernedBy(sb, phone);
      if (fams.length) {
        await sb.from("family_members").update({ sms_status: "declined" })
          .in("family_id", fams).eq("sms_status", "awaiting_parent");
      }
    } catch (_) { /* never break the STOP path */ }
  } else if (OPT_IN.includes(body)) {
    await sb.from("people").update({ sms_opt_in: true }).eq("phone", phone);
    await sb.from("family_members").update({ sms_status: "confirmed" }).eq("phone", phone);
    try {
      const fams = await familiesGovernedBy(sb, phone);
      if (fams.length) {
        await sb.from("family_members").update({ sms_status: "confirmed" })
          .in("family_id", fams).eq("sms_status", "awaiting_parent");
      }
    } catch (_) { /* never break the opt-in path */ }
  }

  return twiml();
});
