// ═══════════════════════════════════════════════════════════════════
// HomeHuddle — send-push edge function
// Sends web push notifications to subscribed devices
// Called from sync-schedules after generating reminders
// ═══════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Minimal VAPID JWT + web-push implementation for Deno
async function makeVapidJwt(audience: string, subject: string, privateKeyB64: string): Promise<string> {
  const header  = { typ: "JWT", alg: "ES256" };
  const payload = {
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: subject,
  };

  const encode = (obj: object) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  const unsigned = encode(header) + "." + encode(payload);

  // Import private key
  const keyBytes = Uint8Array.from(atob(privateKeyB64.replace(/-/g,"+").replace(/_/g,"/")), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false, ["sign"]
  );

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(unsigned)
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  return unsigned + "." + sigB64;
}

async function sendPushToSubscription(
  sub: { endpoint: string; keys: { p256dh: string; auth: string } },
  payload: object,
  vapidPublic: string,
  vapidPrivate: string,
  vapidEmail: string
): Promise<boolean> {
  try {
    const url      = new URL(sub.endpoint);
    const audience = url.origin;
    const jwt      = await makeVapidJwt(audience, `mailto:${vapidEmail}`, vapidPrivate);

    const body = JSON.stringify(payload);

    const res = await fetch(sub.endpoint, {
      method: "POST",
      headers: {
        "Authorization": `vapid t=${jwt},k=${vapidPublic}`,
        "Content-Type":  "application/json",
        "TTL":           "86400",
      },
      body,
    });

    if (res.status === 410 || res.status === 404) {
      // Subscription expired — caller should delete it
      return false;
    }

    return res.ok;
  } catch(e) {
    console.error("Push send error:", e);
    return false;
  }
}

const corsHeaders = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { email, title, body, url } = await req.json();

    if (!email || !title || !body) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const vapidPublic  = Deno.env.get("VAPID_PUBLIC_KEY")!;
    const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY")!;
    const vapidEmail   = "keith@venuewise.net";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Load subscriptions for this email
    const { data: subs, error } = await supabase
      .from("push_subscriptions")
      .select("id, endpoint, keys")
      .eq("email", email);

    if (error || !subs?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = { title, body, url: url || "https://venuewise.net/calendar.html?email=" + encodeURIComponent(email) };
    let sent = 0;
    const expired: string[] = [];

    for (const sub of subs) {
      const ok = await sendPushToSubscription(sub, payload, vapidPublic, vapidPrivate, vapidEmail);
      if (ok) {
        sent++;
      } else {
        expired.push(sub.id);
      }
    }

    // Clean up expired subscriptions
    if (expired.length > 0) {
      await supabase.from("push_subscriptions").delete().in("id", expired);
    }

    console.log(`Push sent ${sent}/${subs.length} for ${email}`);

    return new Response(JSON.stringify({ ok: true, sent, expired: expired.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch(err) {
    console.error("send-push error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});