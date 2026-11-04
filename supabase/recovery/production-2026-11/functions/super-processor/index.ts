// ═══════════════════════════════════════════════════════════════════
// HomeHuddle — send-invite edge function
// Sends a family calendar invite via SMS using Twilio
// ═══════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function normalizePhone(p: string): string {
  const digits = p.replace(/\D/g, "");
  if (digits.length === 10) return "+1" + digits;
  if (digits.length === 11 && digits[0] === "1") return "+" + digits;
  return p;
}

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { to_phone, family_name, kid_name, sent_by, calendar_url } = await req.json();

    if (!to_phone || !family_name || !sent_by || !calendar_url) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const phone = normalizePhone(to_phone);
    const kidPart = kid_name ? kid_name + "'s" : "their";
    const message =
      "Hey! " + family_name + " shared " + kidPart + " HomeHuddle schedule with you.\n\n" +
      "View it here: " + calendar_url + "\n\n" +
      "You can personalize the colors and get reminders for every game and practice. Powered by Venuewise.";

    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
    const authToken  = Deno.env.get("TWILIO_AUTH_TOKEN");
    const fromNumber = Deno.env.get("TWILIO_FROM_NUMBER");

    if (!accountSid || !authToken || !fromNumber) {
      return new Response(JSON.stringify({ error: "Twilio not configured" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const twilioRes = await fetch(
      "https://api.twilio.com/2010-04-01/Accounts/" + accountSid + "/Messages.json",
      {
        method: "POST",
        headers: {
          "Authorization": "Basic " + btoa(accountSid + ":" + authToken),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ From: fromNumber, To: phone, Body: message }).toString(),
      }
    );

    const twilioData = await twilioRes.json();

    if (twilioData.error_code) {
      console.error("Twilio error:", twilioData.message);
      return new Response(JSON.stringify({ error: twilioData.message }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    await supabase.from("invite_log").upsert({
      sent_by,
      family_name,
      kid_name:     kid_name || null,
      to_phone:     phone,
      calendar_url,
      message,
    }, { onConflict: "sent_by,to_phone" });

    console.log("Invite sent to " + phone + " -- " + twilioData.sid);

    return new Response(JSON.stringify({ ok: true, sid: twilioData.sid }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("send-invite error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});