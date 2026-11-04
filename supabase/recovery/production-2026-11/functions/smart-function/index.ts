import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { email, family_name, kid_names } = await req.json();
    if (!email) return Response.json({ error: "Email required" }, { status: 400, headers: corsHeaders });

    const calendarUrl = `https://venuewise.net/calendar.html?email=${encodeURIComponent(email)}`;
    const accountUrl = `https://venuewise.net/account/homehuddle.html`;
    const firstName = (family_name || "there").replace(/ Family$/i, "");
    const kidList = Array.isArray(kid_names) && kid_names.length
      ? kid_names.join(", ")
      : "your kids";

    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "HomeHuddle <hello@venuewise.net>",
        to: email,
        subject: "You're in! Your HomeHuddle calendar is ready 🏠",
        html: `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
</head>
<body style="margin:0;padding:0;background:#F9F9F7;font-family:'Helvetica Neue',Arial,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:32px 16px;">

    <!-- Header -->
    <div style="margin-bottom:32px;">
      <div style="display:inline-flex;align-items:center;gap:8px;">
        <div style="width:36px;height:36px;background:#1D9E75;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;">
          <span style="color:white;font-size:18px;">🏠</span>
        </div>
        <div>
          <div style="font-size:16px;font-weight:600;color:#1a1a18;">HomeHuddle</div>
          <div style="font-size:11px;color:#888780;">powered by Venuewise</div>
        </div>
      </div>
    </div>

    <!-- Main card -->
    <div style="background:white;border:1px solid #D3D1C7;border-radius:16px;padding:32px;margin-bottom:16px;">
      <h1 style="font-size:28px;color:#1a1a18;margin:0 0 8px;font-family:Georgia,serif;">
        Welcome to HomeHuddle, ${firstName}! 🎉
      </h1>
      <p style="font-size:15px;color:#888780;line-height:1.6;margin:0 0 24px;">
        Your family's sports calendar is all set. We're already syncing ${kidList}'s schedules and you'll get notified the moment anything changes.
      </p>

      <!-- Calendar button -->
      <div style="text-align:center;margin-bottom:24px;">
        <a href="${calendarUrl}" style="display:inline-block;background:#1D9E75;color:white;font-size:15px;font-weight:600;padding:14px 32px;border-radius:8px;text-decoration:none;">
          View My Family Calendar →
        </a>
        <div style="font-size:12px;color:#888780;margin-top:8px;">Bookmark this link — it's your family's schedule hub</div>
      </div>

      <hr style="border:none;border-top:1px solid #F1EFE8;margin:24px 0;"/>

      <!-- What happens next -->
      <h2 style="font-size:16px;color:#1a1a18;margin:0 0 16px;">Here's what happens next</h2>

      <div style="display:flex;flex-direction:column;gap:12px;">
        <div style="display:flex;gap:12px;align-items:flex-start;">
          <div style="width:32px;height:32px;background:#E1F5EE;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;">🔄</div>
          <div>
            <div style="font-size:14px;font-weight:600;color:#1a1a18;margin-bottom:2px;">Syncs every 30 minutes</div>
            <div style="font-size:13px;color:#888780;line-height:1.5;">We check your team calendars automatically. No action needed from you.</div>
          </div>
        </div>
        <div style="display:flex;gap:12px;align-items:flex-start;">
          <div style="width:32px;height:32px;background:#E1F5EE;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;">📲</div>
          <div>
            <div style="font-size:14px;font-weight:600;color:#1a1a18;margin-bottom:2px;">Instant alerts when things change</div>
            <div style="font-size:13px;color:#888780;line-height:1.5;">Game rescheduled? Practice cancelled? You'll get a text and push notification right away.</div>
          </div>
        </div>
        <div style="display:flex;gap:12px;align-items:flex-start;">
          <div style="width:32px;height:32px;background:#E1F5EE;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;">🔔</div>
          <div>
            <div style="font-size:14px;font-weight:600;color:#1a1a18;margin-bottom:2px;">Day-of reminders</div>
            <div style="font-size:13px;color:#888780;line-height:1.5;">We'll remind you the morning of every game and practice so nothing sneaks up on you.</div>
          </div>
        </div>
        <div style="display:flex;gap:12px;align-items:flex-start;">
          <div style="width:32px;height:32px;background:#E1F5EE;border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:14px;">👨‍👩‍👧‍👦</div>
          <div>
            <div style="font-size:14px;font-weight:600;color:#1a1a18;margin-bottom:2px;">Share with your whole family</div>
            <div style="font-size:13px;color:#888780;line-height:1.5;">Send your calendar link to grandparents, co-parents, or anyone who needs to know the schedule.</div>
          </div>
        </div>
      </div>

      <hr style="border:none;border-top:1px solid #F1EFE8;margin:24px 0;"/>

      <!-- Share link -->
      <h2 style="font-size:16px;color:#1a1a18;margin:0 0 8px;">Your family calendar link</h2>
      <p style="font-size:13px;color:#888780;margin:0 0 12px;">Share this with anyone who needs to follow ${kidList}'s schedule:</p>
      <div style="background:#F1EFE8;border-radius:8px;padding:12px 16px;font-size:13px;color:#444441;word-break:break-all;">
        ${calendarUrl}
      </div>

      <hr style="border:none;border-top:1px solid #F1EFE8;margin:24px 0;"/>

      <!-- Account link -->
      <p style="font-size:13px;color:#888780;margin:0;">
        Need to update your phone number, add a kid, or change a calendar link?
        <a href="${accountUrl}" style="color:#1D9E75;text-decoration:none;font-weight:500;">Manage your account →</a>
      </p>
    </div>

    <!-- Trial reminder -->
    <div style="background:#E1F5EE;border:1px solid #A7E3CE;border-radius:12px;padding:16px;margin-bottom:16px;text-align:center;">
      <div style="font-size:13px;color:#085041;line-height:1.6;">
        ✦ Your <strong>30-day free trial</strong> starts today. After that, it's just $4.95/month for your whole family — all kids, all sports, all season.
      </div>
    </div>

    <!-- Footer -->
    <div style="text-align:center;padding:16px 0;">
      <p style="font-size:12px;color:#888780;margin:0 0 8px;">
        Questions? Reply to this email or text us at <a href="tel:+17166711814" style="color:#888780;">+1 (716) 671-1814</a>
      </p>
      <p style="font-size:12px;color:#888780;margin:0;">
        <strong>HomeHuddle</strong> · powered by Venuewise ·
        <a href="https://venuewise.net/privacy.html" style="color:#888780;">Privacy</a> ·
        <a href="https://venuewise.net/terms.html" style="color:#888780;">Terms</a>
      </p>
    </div>

  </div>
</body>
</html>
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