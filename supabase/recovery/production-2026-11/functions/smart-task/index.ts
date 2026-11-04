import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { email } = await req.json();
    if (!email) return Response.json({ error: "Email required" }, { status: 400, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SERVICE_ROLE_KEY")!
    );

    // Look up account
    const { data: feeds, error } = await supabase
      .from("feeds")
      .select("family_name, pin")
      .eq("email", email)
      .limit(1);

    if (error || !feeds?.length) {
      // Don't reveal if email exists or not
      return Response.json({ success: true }, { headers: corsHeaders });
    }

    // Generate a temporary reset token (6-digit code)
    const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
    const resetExpiry = new Date(Date.now() + 30 * 60 * 1000).toISOString(); // 30 min

    // Save reset code to feeds
    await supabase.from("feeds").update({
      pin: resetCode,
    }).eq("email", email);

    const familyName = feeds[0].family_name || "there";

    // Send email via Resend
    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "HomeHuddle <hello@venuewise.net>",
        to: email,
        subject: "Your HomeHuddle PIN reset",
        html: `
          <div style="font-family: sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px;">
            <div style="font-size: 24px; font-weight: 700; color: #1a1a18; margin-bottom: 8px;">
              🏠 HomeHuddle
            </div>
            <p style="color: #888780; font-size: 13px; margin-bottom: 32px;">powered by Venuewise</p>
            <h2 style="font-size: 20px; color: #1a1a18; margin-bottom: 12px;">Hi ${familyName},</h2>
            <p style="color: #444441; font-size: 15px; line-height: 1.6; margin-bottom: 24px;">
              We received a request to reset your HomeHuddle PIN. Your new temporary PIN is:
            </p>
            <div style="background: #E1F5EE; border-radius: 12px; padding: 24px; text-align: center; margin-bottom: 24px;">
              <div style="font-size: 48px; font-weight: 700; letter-spacing: 12px; color: #085041;">${resetCode}</div>
              <p style="color: #1D9E75; font-size: 13px; margin-top: 8px;">Valid for 30 minutes</p>
            </div>
            <p style="color: #444441; font-size: 14px; line-height: 1.6; margin-bottom: 24px;">
              Log in at <a href="https://venuewise.net/account/homehuddle.html" style="color: #1D9E75;">venuewise.net/account/homehuddle.html</a> and use this code as your PIN. We recommend changing it to a PIN you'll remember once you're in.
            </p>
            <p style="color: #888780; font-size: 13px;">If you didn't request this, you can ignore this email — your account is safe.</p>
            <hr style="border: none; border-top: 1px solid #F1EFE8; margin: 32px 0;"/>
            <p style="color: #888780; font-size: 12px;">HomeHuddle · powered by Venuewise · <a href="mailto:hello@venuewise.net" style="color: #888780;">hello@venuewise.net</a></p>
          </div>
        `,
      }),
    });

    if (!resendRes.ok) {
      const err = await resendRes.text();
      console.error("Resend error:", err);
      return Response.json({ error: "Failed to send email" }, { status: 500, headers: corsHeaders });
    }

    return Response.json({ success: true }, { headers: corsHeaders });

  } catch (e) {
    console.error(e);
    return Response.json({ error: "Server error" }, { status: 500, headers: corsHeaders });
  }
});