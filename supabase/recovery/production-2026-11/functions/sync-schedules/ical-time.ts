// ═══════════════════════════════════════════════════════════════════
// HomeHuddle — ical-time.ts
// Timezone-aware parsing/formatting for calendar timestamps.
//
// Rules this module enforces:
//   1. An event is an INSTANT. It is stored in Postgres as timestamptz (UTC).
//   2. The instant is derived from a wall-clock time PLUS an IANA zone.
//      Never from the runtime's local zone (which is UTC on Supabase Edge).
//   3. DST is resolved by the IANA database via Intl, never by a fixed offset.
//
// No dependencies. Runs on Deno (Edge Functions), Node, and browsers.
// ═══════════════════════════════════════════════════════════════════

export const DEFAULT_EVENT_TZ = "America/New_York";

export type IcalTimeKind = "utc" | "zoned" | "floating" | "date";

export interface ParsedIcalTime {
  instant: Date;
  isAllDay: boolean;
  timeZone: string;
  kind: IcalTimeKind;
}

const TZ_ALIASES: Record<string, string> = {
  "Eastern Standard Time": "America/New_York",
  "Eastern Daylight Time": "America/New_York",
  "US/Eastern": "America/New_York",
  "Central Standard Time": "America/Chicago",
  "US/Central": "America/Chicago",
  "Mountain Standard Time": "America/Denver",
  "US/Mountain": "America/Denver",
  "Pacific Standard Time": "America/Los_Angeles",
  "US/Pacific": "America/Los_Angeles",
  "Atlantic Standard Time": "America/Halifax",
  "GMT Standard Time": "Europe/London",
  "UTC": "UTC",
  "Z": "UTC",
};

export function isValidTimeZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export function normalizeTimeZone(
  tzid: string | null | undefined,
  fallback: string = DEFAULT_EVENT_TZ,
): string {
  if (!tzid) return fallback;
  const raw = tzid.trim().replace(/^"(.*)"$/, "$1").trim();
  if (!raw) return fallback;

  const aliased = TZ_ALIASES[raw];
  if (aliased) return aliased;
  if (isValidTimeZone(raw)) return raw;

  const stripped = raw.replace(/^\/+/, "");
  if (isValidTimeZone(stripped)) return stripped;

  const parts = stripped.split("/").filter(Boolean);
  for (let take = 2; take <= Math.min(3, parts.length); take++) {
    const tail = parts.slice(-take).join("/");
    if (isValidTimeZone(tail)) return tail;
  }
  return fallback;
}

interface WallTime {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const partsCache = new Map<string, Intl.DateTimeFormat>();

function formatter(tz: string): Intl.DateTimeFormat {
  let f = partsCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    partsCache.set(tz, f);
  }
  return f;
}

export function wallTimeAt(ms: number, tz: string): WallTime {
  const parts = formatter(tz).formatToParts(new Date(ms));
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? "0");
  return {
    year: get("year"),
    month: get("month"),
    day: get("day"),
    hour: get("hour"),
    minute: get("minute"),
    second: get("second"),
  };
}

function wallAsPseudoUtc(w: WallTime): number {
  return Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
}

export function tzOffsetMs(ms: number, tz: string): number {
  return wallAsPseudoUtc(wallTimeAt(ms, tz)) - ms;
}

export function wallTimeToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  tz: string,
): Date {
  const target = Date.UTC(year, month - 1, day, hour, minute, second);
  const guess1 = target - tzOffsetMs(target, tz);
  const guess2 = target - tzOffsetMs(guess1, tz);

  const valid: number[] = [];
  for (const candidate of guess1 === guess2 ? [guess1] : [guess1, guess2]) {
    if (wallAsPseudoUtc(wallTimeAt(candidate, tz)) === target) valid.push(candidate);
  }
  if (valid.length) return new Date(Math.min(...valid));
  return new Date(Math.max(guess1, guess2));
}

export interface IcalProperty {
  name: string;
  params: Record<string, string>;
  value: string;
}

export function parseIcalProperty(line: string): IcalProperty {
  const text = line.replace(/\r?\n[ \t]/g, "").trim();
  const colon = text.indexOf(":");
  const head = colon === -1 ? text : text.slice(0, colon);
  const value = colon === -1 ? "" : text.slice(colon + 1).trim();

  const segments = head.split(";");
  const name = (segments.shift() || "").trim().toUpperCase();
  const params: Record<string, string> = {};
  for (const seg of segments) {
    const eq = seg.indexOf("=");
    if (eq === -1) continue;
    params[seg.slice(0, eq).trim().toUpperCase()] = seg.slice(eq + 1).trim();
  }
  return { name, params, value };
}

export function parseIcalDateTime(
  line: string,
  fallbackTz: string = DEFAULT_EVENT_TZ,
): ParsedIcalTime | null {
  const prop = parseIcalProperty(line);
  const value = prop.value;
  if (!value) return null;

  const tzid = prop.params["TZID"];
  const isDateOnly = prop.params["VALUE"]?.toUpperCase() === "DATE" || /^\d{8}$/.test(value);

  if (isDateOnly) {
    const m = /^(\d{4})(\d{2})(\d{2})$/.exec(value);
    if (!m) return null;
    const tz = normalizeTimeZone(tzid, fallbackTz);
    return {
      instant: wallTimeToUtc(+m[1], +m[2], +m[3], 0, 0, 0, tz),
      isAllDay: true,
      timeZone: tz,
      kind: "date",
    };
  }

  const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/.exec(value);
  if (!m) return null;
  const [, y, mo, d, h, mi, s, z] = m;

  if (z === "Z") {
    return {
      instant: new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +s)),
      isAllDay: false,
      timeZone: "UTC",
      kind: "utc",
    };
  }

  const tz = normalizeTimeZone(tzid, fallbackTz);
  return {
    instant: wallTimeToUtc(+y, +mo, +d, +h, +mi, +s, tz),
    isAllDay: false,
    timeZone: tz,
    kind: tzid ? "zoned" : "floating",
  };
}

export function formatTimeInZone(date: Date, tz: string = DEFAULT_EVENT_TZ): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

export function formatDateTimeInZone(date: Date, tz: string = DEFAULT_EVENT_TZ): string {
  const d = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    weekday: "short",
    month: "short",
    day: "numeric",
  }).format(date);
  return `${d} at ${formatTimeInZone(date, tz)}`;
}

export function dayKeyInZone(date: Date, tz: string = DEFAULT_EVENT_TZ): string {
  const w = wallTimeAt(date.getTime(), tz);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${w.year}-${pad(w.month)}-${pad(w.day)}`;
}

export function zonedDayRangeUtc(
  dayKey: string,
  tz: string = DEFAULT_EVENT_TZ,
): { startUtc: Date; endUtc: Date } {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayKey);
  if (!m) throw new Error(`zonedDayRangeUtc: bad day key ${dayKey}`);
  const startUtc = wallTimeToUtc(+m[1], +m[2], +m[3], 0, 0, 0, tz);
  const endUtc = new Date(
    wallTimeToUtc(+m[1], +m[2], +m[3] + 1, 0, 0, 0, tz).getTime() - 1,
  );
  return { startUtc, endUtc };
}

export function shiftDayKey(dayKey: string, days: number, tz: string = DEFAULT_EVENT_TZ): string {
  const { startUtc } = zonedDayRangeUtc(dayKey, tz);
  return dayKeyInZone(new Date(startUtc.getTime() + days * 86400000 + 43200000), tz);
}
