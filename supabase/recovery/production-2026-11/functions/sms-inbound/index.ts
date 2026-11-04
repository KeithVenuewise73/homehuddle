import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

// Families where this phone is the owner/parent, used to attribute a YES
// to a minor whose consent was requested from the parent's phone.
async function familiesGovernedBy(sb: any, phone: string): Promise<string[]> {
  const ids = new Set<string>();

  const { data: person } = await sb
    .from("people").select("id").eq("phone", phone).maybeSingle();

  if (person?.id) {
    const { data: acc } = await sb
      .from("family_access")
      .select("family_id")
      .eq("person_id", person.id)
      .eq("role", "owner")
      .eq("status", "active");
    (acc || []).forEach((r: any) => ids.add(r.family_id));
  }

  const { data: mem } = await sb
    .from("family_members")
    .select("family_id")
    .eq("phone", phone)
    .in("role", ["parent", "guardian"]);
  (mem || []).forEach((r: any) => ids.add(r.family_id));

  return [...ids];
}

Deno.serve(async (req: Request) => {
  let from = "", body = "";
  try {
    const form = await req.formData();
    from = String(form.get("From") || "");
    body = String(form.get("Body") || "").trim().toUpperCase();
  } catch (_) {
    return twiml();
  }
  if (!from) return twiml();

  const phone = normPhone(from);
  const sb = createClient(SUPABASE_URL, SERVICE_KEY);

  if (OPT_OUT.includes(body)) {
    // Opt out everywhere this number appears. (unchanged)
    await sb.from("people").update({ sms_opt_in: false }).eq("phone", phone);
    await sb.from("family_members").update({ sms_status: "declined" }).eq("phone", phone);

    // A parent declining also cancels any minor awaiting their consent.
    try {
      const fams = await familiesGovernedBy(sb, phone);
      if (fams.length) {
        await sb.from("family_members")
          .update({ sms_status: "declined" })
          .in("family_id", fams)
          .eq("sms_status", "awaiting_parent");
      }
    } catch (_) { /* never break the STOP path */ }

  } else if (OPT_IN.includes(body)) {
    // Double opt-in confirmation: this number agreed to reminders. (unchanged)
    await sb.from("people").update({ sms_opt_in: true }).eq("phone", phone);
    await sb.from("family_members").update({ sms_status: "confirmed" }).eq("phone", phone);

    // NEW: a parent's YES also confirms minors whose consent was requested
    // from this phone. The minor_confirmed_notice trigger then sends the
    // child a notice (not a request) with opt-out instructions.
    try {
      const fams = await familiesGovernedBy(sb, phone);
      if (fams.length) {
        await sb.from("family_members")
          .update({ sms_status: "confirmed" })
          .in("family_id", fams)
          .eq("sms_status", "awaiting_parent");
      }
    } catch (_) { /* never break the opt-in path */ }
  }

  // Empty TwiML — Twilio sends its own standard STOP/START confirmation.
  return twiml();
});
