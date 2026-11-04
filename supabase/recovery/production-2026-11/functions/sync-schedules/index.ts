// ═══════════════════════════════════════════════════════════════════
// HomeHuddle — sync-schedules Edge Function  [TIMEZONE-CORRECTED]
// powered by Venuewise
//
// TIMEZONE FIX 2026-08-17 (deployed):
//   parseIcalDate() discarded the TZID parameter and resolved naked
//   wall-clock times with `new Date(y, mo, d, h, min, s)`, i.e. in the
//   RUNTIME's local zone. On Supabase Edge that runtime is UTC, so
//   "8:30 PM America/New_York" was written as 20:30Z and rendered back
//   as 4:30 PM ET. Replaced with ical-time.ts, which resolves TZID /
//   floating / UTC forms distinctly using IANA data.
//   All getHours()/getMonth()-based formatting and all UTC-day windows
//   were also replaced with zone-aware equivalents.
//
//   Set SUPPRESS_CHANGE_ALERTS=true before any future bulk re-parse to
//   silence the resulting "schedule change" pushes. NOTE: it does NOT
//   suppress the public.trg_events_sms database trigger, which enqueues
//   SMS on any events.start change — pause cron job 10 for that.
//
// SMS SENDING DISABLED 2026-06-23 (see sendSMS). The every-30-min cron was
// re-sending duplicate alerts to a hardcoded number (554 segments -> Twilio
// suspension). Calendar feed sync, in-app reminders, and browser push are
// UNCHANGED. SMS is being rebuilt as a send-once, per-family, opt-out notifier.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  DEFAULT_EVENT_TZ,
  dayKeyInZone,
  formatDateTimeInZone,
  formatTimeInZone,
  normalizeTimeZone,
  parseIcalDateTime,
  shiftDayKey,
  wallTimeAt,
  zonedDayRangeUtc,
} from "./ical-time.ts";

const SUPPRESS_CHANGE_ALERTS = (Deno.env.get("SUPPRESS_CHANGE_ALERTS") || "").toLowerCase() === "true";

interface CalEvent {
  uid: string;
  name: string;
  start: Date;
  end: Date;
  isAllDay: boolean;
  sourceTimeZone: string;
  location: string;
  description: string;
  platform: string;
  kid: string;
  sport: string;
  teamName?: string;
  feedId?: string;
  familyPhone?: string;
  familyEmail?: string;
}

interface FeedRecord {
  id: string;
  family_name: string;
  email: string;
  phone: string;
  kid_name: string;
  sport: string;
  platform: string;
  ical_url: string;
  is_active: boolean;
  team_name?: string;
  timezone?: string | null;
}

function decodeIcalText(val: string): string {
  return (val || "")
    .replace(/\\n/g, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\")
    .trim();
}

function normalizeUid(uid: string, platform: string): string {
  if (platform !== "leagueapps") return uid;
  return uid.replace(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z/, "");
}

function parseIcal(
  raw: string,
  platform: string,
  kid: string,
  sport: string,
  teamName?: string,
  feedId?: string,
  familyPhone?: string,
  familyEmail?: string,
  feedTimeZone: string = DEFAULT_EVENT_TZ,
): { events: CalEvent[]; skipped: number } {
  const events: CalEvent[] = [];
  let skipped = 0;
  const blocks = raw.split("BEGIN:VEVENT");

  for (let i = 1; i < blocks.length; i++) {
    const block = blocks[i].replace(/\r?\n[ \t]/g, "");

    const getLine = (key: string): string => {
      const patterns = [
        new RegExp(`^${key}[;:][^\r\n]*`, "m"),
        new RegExp(`^${key}\\.[^:]+:[^\r\n]*`, "m"),
      ];
      for (const p of patterns) {
        const m = block.match(p);
        if (m) return m[0].trim();
      }
      return "";
    };
    const getValue = (key: string): string => {
      const line = getLine(key);
      return line ? line.replace(/^[^:]+:/, "").trim() : "";
    };

    const rawUid = getValue("UID");
    const uid = normalizeUid(rawUid, platform);
    const summary = getValue("SUMMARY");
    const dtstartLine = getLine("DTSTART");
    const dtendLine = getLine("DTEND");
    if (!uid || !dtstartLine) continue;

    const startParsed = parseIcalDateTime(dtstartLine, feedTimeZone);
    if (!startParsed) {
      console.warn(`Unparseable DTSTART for ${uid}: ${dtstartLine}`);
      skipped++;
      continue;
    }
    const endParsed = dtendLine ? parseIcalDateTime(dtendLine, feedTimeZone) : null;

    events.push({
      uid,
      name: decodeIcalText(summary),
      start: startParsed.instant,
      end: endParsed ? endParsed.instant : startParsed.instant,
      isAllDay: startParsed.isAllDay,
      sourceTimeZone: startParsed.timeZone,
      location: decodeIcalText(getValue("LOCATION")),
      description: decodeIcalText(getValue("DESCRIPTION")),
      platform,
      kid,
      sport,
      teamName,
      feedId,
      familyPhone,
      familyEmail,
    });
  }
  return { events, skipped };
}

function eventsOverlap(a: CalEvent, b: CalEvent): boolean {
  if (a.kid !== b.kid || a.uid === b.uid) return false;
  if (a.familyPhone !== b.familyPhone) return false;
  return a.start < b.end && b.start < a.end;
}

async function fetchFeed(url: string): Promise<string | null> {
  try {
    const cleanUrl = url.replace(/^webcal:\/\//i, "https://");
    const response = await fetch(cleanUrl, {
      headers: {
        "User-Agent": "HomeHuddleCalendar/1.0",
        "Accept": "text/calendar, application/ics, */*",
      },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (!text.includes("BEGIN:VCALENDAR")) throw new Error("Not valid iCal");
    return text;
  } catch (err) {
    console.error("Feed fetch error:", err);
    return null;
  }
}

async function sendSMS(_message: string, _toNumber?: string): Promise<void> {
  return;
}

function fmtDateTime(d: Date, tz: string = DEFAULT_EVENT_TZ): string {
  return formatDateTimeInZone(d, tz);
}

async function sendTomorrowReminders(supabase: any, tz: string = DEFAULT_EVENT_TZ): Promise<void> {
  const now = new Date();
  const localHour = wallTimeAt(now.getTime(), tz).hour;
  if (localHour < 19 || localHour >= 20) return;

  const tomorrowKey = shiftDayKey(dayKeyInZone(now, tz), 1, tz);
  const { startUtc, endUtc } = zonedDayRangeUtc(tomorrowKey, tz);

  const { data: events } = await supabase
    .from("events")
    .select("*")
    .gte("start", startUtc.toISOString())
    .lte("start", endUtc.toISOString())
    .eq("is_duplicate", false);

  if (!events || events.length === 0) return;

  const byPhone: Record<string, any[]> = {};
  for (const ev of events) {
    const phone = ev.family_phone || "default";
    if (!byPhone[phone]) byPhone[phone] = [];
    byPhone[phone].push(ev);
  }

  for (const [phone, familyEvents] of Object.entries(byPhone)) {
    let message = `📅 HomeHuddle — Tomorrow's Schedule\n\n`;
    for (const ev of familyEvents) {
      message += `• ${ev.name}\n  ${formatTimeInZone(new Date(ev.start), tz)}`;
      if (ev.location) message += ` · ${ev.location}`;
      message += `\n\n`;
    }
    message += `View schedule: venuewise.net`;
    if (phone === "default") {
      await sendSMS(message);
    } else {
      await sendSMS(message, phone);
    }
  }
  console.log(`Sent tomorrow reminders for ${events.length} events (${tz} day ${tomorrowKey})`);
}

async function generateReminders(supabase: any, tz: string = DEFAULT_EVENT_TZ): Promise<void> {
  const todayKey = dayKeyInZone(new Date(), tz);
  const { startUtc, endUtc } = zonedDayRangeUtc(todayKey, tz);

  const { data: feeds, error: feedErr } = await supabase
    .from("feeds")
    .select("email, kid_name, family_name, phone")
    .eq("is_active", true);

  if (feedErr || !feeds || feeds.length === 0) return;

  const kidToEmail: Record<string, string> = {};
  feeds.forEach((f: any) => {
    if (f.kid_name) kidToEmail[f.kid_name.toLowerCase()] = f.email;
  });

  const { data: todayEvents, error: evErr } = await supabase
    .from("events")
    .select("uid, kid, name, start, end, location, platform, family_phone")
    .gte("start", startUtc.toISOString())
    .lte("start", endUtc.toISOString())
    .eq("is_duplicate", false);

  if (evErr || !todayEvents || todayEvents.length === 0) return;

  const reminders: any[] = [];

  for (const ev of todayEvents) {
    const email = kidToEmail[ev.kid?.toLowerCase()] || null;
    if (!email) continue;

    const startDate = new Date(ev.start);
    const endDate = new Date(ev.end);

    const timeStr = formatTimeInZone(startDate, tz);
    const endStr = formatTimeInZone(endDate, tz);

    const evName = ev.name || "event";
    const lower = evName.toLowerCase();
    const isGame = lower.includes("game") || lower.includes("vs") || lower.includes(" @ ");
    const isTournament = lower.includes("tournament") || lower.includes("tourney");
    const verb = isTournament ? "tournament" : isGame ? "game" : "practice";
    const loc = ev.location ? ` at ${ev.location}` : "";
    const durationMins = (endDate.getTime() - startDate.getTime()) / 60000;

    let message: string;
    if (isTournament) {
      message = `${ev.kid} has a ${verb} today from ${timeStr}–${endStr}${loc}.`;
    } else if (durationMins <= 90) {
      message = `${ev.kid} has ${verb} today at ${timeStr}${loc} — ends around ${endStr}, plan for pickup!`;
    } else {
      message = `${ev.kid} has ${verb} today: ${evName} from ${timeStr}–${endStr}${loc}.`;
    }

    reminders.push({
      email,
      kid: ev.kid,
      message,
      event_uid: ev.uid,
      event_date: todayKey,
      event_time: timeStr,
      event_name: ev.name,
      dismissed: false,
    });
  }

  if (reminders.length === 0) return;

  const { error: upsertErr } = await supabase
    .from("reminders")
    .upsert(reminders, { onConflict: "email,event_uid", ignoreDuplicates: true });

  if (upsertErr) {
    console.error("generateReminders upsert error:", upsertErr.message);
  } else {
    console.log(`generateReminders: wrote ${reminders.length} reminder(s) for ${todayKey} (${tz})`);
  }
}

async function triggerPush(supabase: any, email: string, title: string, body: string): Promise<void> {
  if (!email) return;
  const { data: subs } = await supabase
    .from("push_subscriptions").select("id").eq("email", email).limit(1);
  if (!subs?.length) return;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  try {
    await fetch(supabaseUrl + "/functions/v1/hyper-action", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer " + supabaseKey,
        "apikey": supabaseKey,
      },
      body: JSON.stringify({ email, title, body }),
    });
    console.log("Push triggered for " + email + ": " + title);
  } catch (e) {
    console.error("Push trigger error:", e);
  }
}

async function sendPushNotifications(supabase: any, tz: string = DEFAULT_EVENT_TZ): Promise<void> {
  const today = dayKeyInZone(new Date(), tz);
  const { data: reminders, error } = await supabase
    .from("reminders")
    .select("email, kid, message, event_time")
    .eq("event_date", today)
    .eq("dismissed", false);

  if (error || !reminders?.length) return;

  const byEmail: Record<string, any[]> = {};
  for (const r of reminders) {
    if (!byEmail[r.email]) byEmail[r.email] = [];
    byEmail[r.email].push(r);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  for (const [email, events] of Object.entries(byEmail)) {
    const { data: subs } = await supabase
      .from("push_subscriptions").select("id").eq("email", email).limit(1);
    if (!subs?.length) continue;

    const first = events[0];
    const title = events.length === 1
      ? "HomeHuddle — " + first.kid + " today"
      : "HomeHuddle — " + events.length + " events today";

    try {
      await fetch(supabaseUrl + "/functions/v1/hyper-action", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer " + supabaseKey,
          "apikey": supabaseKey,
        },
        body: JSON.stringify({ email, title, body: first.message }),
      });
      console.log("Push triggered for " + email);
    } catch (e) {
      console.error("Push trigger error for " + email + ":", e);
    }
  }
}

Deno.serve(async (_req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  const { data: feedRecords, error: feedsError } = await supabase
    .from("feeds")
    .select("*")
    .eq("is_active", true);

  if (feedsError) {
    console.error("Failed to load feeds:", feedsError);
    return new Response(JSON.stringify({ error: "Failed to load feeds" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!feedRecords || feedRecords.length === 0) {
    return new Response(JSON.stringify({ message: "No active feeds" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  console.log(`Loaded ${feedRecords.length} active feeds`);

  const results: any[] = [];
  const allEvents: CalEvent[] = [];
  let totalFetched = 0;
  let totalUpserted = 0;
  let totalSkipped = 0;
  let conflictsDetected = 0;
  const smsAlerts: { message: string; phone?: string }[] = [];

  for (const feed of feedRecords as FeedRecord[]) {
    const feedTz = normalizeTimeZone(feed.timezone, DEFAULT_EVENT_TZ);

    const result: any = {
      platform: feed.platform,
      kid: feed.kid_name,
      family: feed.family_name,
      team: feed.team_name || '',
      timezone: feedTz,
      fetched: 0,
      upserted: 0,
      skipped: 0,
      errors: [],
    };

    if (!feed.ical_url) {
      result.errors.push("No iCal URL");
      results.push(result);
      continue;
    }

    const raw = await fetchFeed(feed.ical_url);
    if (!raw) {
      result.errors.push("Failed to fetch feed");
      results.push(result);
      continue;
    }

    const { events, skipped } = parseIcal(
      raw,
      feed.platform,
      feed.kid_name,
      feed.sport || "sport",
      feed.team_name || "",
      feed.id,
      feed.phone,
      feed.email,
      feedTz,
    );

    result.fetched = events.length;
    result.skipped = skipped;
    totalFetched += events.length;
    totalSkipped += skipped;
    allEvents.push(...events);

    const now = new Date();
    const windowStart = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    const windowEnd = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);
    const windowEvents = events.filter(e => e.start >= windowStart && e.start <= windowEnd);

    for (const ev of windowEvents) {
      const { data: existing } = await supabase
        .from("events")
        .select("uid, name, start, location")
        .eq("uid", ev.uid)
        .eq("feed_id", feed.id)
        .maybeSingle();

      if (existing) {
        const timeChanged = new Date(existing.start).getTime() !== ev.start.getTime();
        const locationChanged = (existing.location || "") !== (ev.location || "");

        if ((timeChanged || locationChanged) && !SUPPRESS_CHANGE_ALERTS) {
          let alertMsg = `⚠️ HomeHuddle Alert — Schedule Change\n\n`;
          alertMsg += `${ev.name}\n`;
          if (timeChanged) {
            alertMsg += `⏰ Time changed:\n`;
            alertMsg += `  Was: ${fmtDateTime(new Date(existing.start), feedTz)}\n`;
            alertMsg += `  Now: ${fmtDateTime(ev.start, feedTz)}\n`;
          }
          if (locationChanged) {
            alertMsg += `📍 Location changed:\n`;
            if (existing.location) alertMsg += `  Was: ${existing.location}\n`;
            alertMsg += `  Now: ${ev.location || "TBD"}\n`;
          }
          alertMsg += `\nView: venuewise.net`;
          smsAlerts.push({ message: alertMsg, phone: feed.phone });
          await triggerPush(supabase, feed.email, "HomeHuddle — Schedule Change", alertMsg.replace(/[\u{0080}-\u{FFFF}]/gu, '').trim());
        }
      } else {
        if (ev.start > now && !SUPPRESS_CHANGE_ALERTS) {
          let alertMsg = `🆕 HomeHuddle — New Event Added\n\n`;
          alertMsg += `${ev.name}\n`;
          alertMsg += `📅 ${fmtDateTime(ev.start, feedTz)}\n`;
          if (ev.location) alertMsg += `📍 ${ev.location}\n`;
          alertMsg += `\nView: venuewise.net`;
          smsAlerts.push({ message: alertMsg, phone: feed.phone });
          await triggerPush(supabase, feed.email, "HomeHuddle — New Event", alertMsg.replace(/[\u{0080}-\u{FFFF}]/gu, '').trim());
        }
      }

      const { error } = await supabase.from("events").upsert(
        {
          uid: ev.uid,
          name: ev.name,
          start: ev.start.toISOString(),
          end: ev.end.toISOString(),
          location: ev.location,
          description: ev.description,
          platform: ev.platform,
          kid: ev.kid,
          sport: ev.sport,
          team_name: ev.teamName || null,
          feed_id: feed.id,
          family_phone: feed.phone || null,
          conflict: false,
          is_duplicate: false,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "uid,feed_id" }
      );

      if (error) {
        console.error(`Upsert error for ${ev.uid}:`, JSON.stringify(error));
        result.errors.push(error.message);
      } else {
        result.upserted++;
        totalUpserted++;
      }
    }

    await supabase
      .from("feeds")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", feed.id);

    results.push(result);
  }

  for (let i = 0; i < allEvents.length; i++) {
    for (let j = i + 1; j < allEvents.length; j++) {
      if (eventsOverlap(allEvents[i], allEvents[j])) {
        conflictsDetected++;
        await supabase.from("events").update({ conflict: true })
          .eq("uid", allEvents[i].uid)
          .eq("feed_id", allEvents[i].feedId || "");
        await supabase.from("events").update({ conflict: true })
          .eq("uid", allEvents[j].uid)
          .eq("feed_id", allEvents[j].feedId || "");

        const now = new Date();
        if (allEvents[i].start > now) {
          let alertMsg = `⚠️ HomeHuddle — Schedule Conflict!\n\n`;
          alertMsg += `${allEvents[i].kid} has 2 overlapping events:\n`;
          alertMsg += `• ${allEvents[i].name}\n`;
          alertMsg += `• ${allEvents[j].name}\n`;
          alertMsg += `📅 ${fmtDateTime(allEvents[i].start, allEvents[i].sourceTimeZone)}\n\nView: venuewise.net`;
          smsAlerts.push({ message: alertMsg, phone: allEvents[i].familyPhone });
        }
      }
    }
  }

  await sendTomorrowReminders(supabase);
  await generateReminders(supabase);
  await sendPushNotifications(supabase);

  const alertsToSend = smsAlerts.slice(0, 5);
  for (const alert of alertsToSend) {
    if (alert.phone) await sendSMS(alert.message, alert.phone);
    else await sendSMS(alert.message);
  }

  const response = {
    timestamp: new Date().toISOString(),
    feeds_loaded: feedRecords.length,
    total_fetched: totalFetched,
    total_upserted: totalUpserted,
    total_skipped: totalSkipped,
    conflicts_detected: conflictsDetected,
    change_alerts_suppressed: SUPPRESS_CHANGE_ALERTS,
    sms_alerts_sent: 0,
    sms_status: "disabled — rebuilding as send-once per-family notifier",
    feeds: results,
  };

  console.log("Sync complete:", JSON.stringify(response));

  return new Response(JSON.stringify(response), {
    headers: { "Content-Type": "application/json" },
  });
});
