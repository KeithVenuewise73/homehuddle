// HLG shared request guards for Supabase Edge Functions (Venuewise project).
// Pure functions: no Supabase client, no env access, so they are unit-testable with plain Deno.
//
// Usage patterns:
//   - Cron-driven functions (verify_jwt=false): requireSharedSecret(req, "x-outbox-secret", Deno.env.get("OUTBOX_SECRET"))
//   - Twilio webhooks (verify_jwt=false): await verifyTwilioSignature(authToken, publicUrl, formParams, req.headers.get("x-twilio-signature"))
//   - Everything else: verify_jwt=true in config.toml, plus auth.getUser(token) inside.

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

/**
 * Fail-closed shared-secret check. Returns null when the request may proceed,
 * otherwise a Response to return immediately. A missing/empty configured secret
 * is itself a failure (401): the endpoint must never be open by default.
 */
export function requireSharedSecret(
  req: Request,
  headerName: string,
  configuredSecret: string | undefined | null,
): Response | null {
  const expected = (configuredSecret ?? "").trim();
  if (expected.length < 16) {
    return json({ error: "endpoint_not_configured" }, 503);
  }
  const provided = (req.headers.get(headerName) ?? "").trim();
  if (!provided || !timingSafeEqual(provided, expected)) {
    return json({ error: "unauthorized" }, 401);
  }
  return null;
}

/**
 * Twilio request signature (X-Twilio-Signature): base64(HMAC-SHA1(authToken,
 * url + concat(sorted(key+value)))) over the full public URL (incl. query string)
 * and the POST form parameters.
 * https://www.twilio.com/docs/usage/webhooks/webhooks-security
 */
export async function computeTwilioSignature(
  authToken: string,
  url: string,
  params: Record<string, string>,
): Promise<string> {
  const keys = Object.keys(params).sort();
  let data = url;
  for (const k of keys) data += k + params[k];
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return btoa(String.fromCharCode(...new Uint8Array(mac)));
}

export async function verifyTwilioSignature(
  authToken: string | undefined | null,
  url: string,
  params: Record<string, string>,
  providedSignature: string | null | undefined,
): Promise<boolean> {
  if (!authToken || !providedSignature) return false;
  const expected = await computeTwilioSignature(authToken, url, params);
  return timingSafeEqual(expected, providedSignature);
}

export function formToRecord(form: FormData): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of form.entries()) out[k] = typeof v === "string" ? v : "";
  return out;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
