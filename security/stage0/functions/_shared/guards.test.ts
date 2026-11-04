import {
  computeTwilioSignature,
  formToRecord,
  requireSharedSecret,
  verifyTwilioSignature,
} from "./guards.ts";

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

Deno.test("requireSharedSecret: missing configured secret fails closed (503)", () => {
  const req = new Request("https://x.test/f", { headers: { "x-outbox-secret": "anything-at-all-long" } });
  const r = requireSharedSecret(req, "x-outbox-secret", undefined);
  assert(r !== null && r.status === 503, "expected 503 when secret not configured");
});

Deno.test("requireSharedSecret: short configured secret is treated as not configured", () => {
  const req = new Request("https://x.test/f", { headers: { "x-outbox-secret": "short" } });
  const r = requireSharedSecret(req, "x-outbox-secret", "short");
  assert(r !== null && r.status === 503, "expected 503 for <16 char secret");
});

Deno.test("requireSharedSecret: wrong or absent header is 401", () => {
  const secret = "0123456789abcdef0123456789abcdef";
  const absent = requireSharedSecret(new Request("https://x.test/f"), "x-outbox-secret", secret);
  assert(absent !== null && absent.status === 401, "absent header must be 401");
  const wrong = requireSharedSecret(
    new Request("https://x.test/f", { headers: { "x-outbox-secret": secret.slice(0, -1) + "X" } }),
    "x-outbox-secret",
    secret,
  );
  assert(wrong !== null && wrong.status === 401, "wrong header must be 401");
});

Deno.test("requireSharedSecret: correct header passes", () => {
  const secret = "0123456789abcdef0123456789abcdef";
  const ok = requireSharedSecret(
    new Request("https://x.test/f", { headers: { "x-outbox-secret": secret } }),
    "x-outbox-secret",
    secret,
  );
  assert(ok === null, "legitimate caller must pass");
});

// Twilio's documented worked example (webhooks security page).
const TWILIO_DOC_URL = "https://mycompany.com/myapp.php?foo=1&bar=2";
const TWILIO_DOC_PARAMS = {
  Digits: "1234",
  To: "+18005551212",
  From: "+14158675310",
  Caller: "+14158675310",
  CallSid: "CA1234567890ABCDE",
};
const TWILIO_DOC_TOKEN = "12345";
const TWILIO_DOC_SIGNATURE = "GvWf1cFY/Q7PnoempGyD5oXAezc=";

Deno.test("twilio signature: matches Twilio's documented example", async () => {
  const sig = await computeTwilioSignature(TWILIO_DOC_TOKEN, TWILIO_DOC_URL, TWILIO_DOC_PARAMS);
  assert(sig === TWILIO_DOC_SIGNATURE, `expected ${TWILIO_DOC_SIGNATURE}, got ${sig}`);
  assert(await verifyTwilioSignature(TWILIO_DOC_TOKEN, TWILIO_DOC_URL, TWILIO_DOC_PARAMS, sig), "valid signature must verify");
});

Deno.test("twilio signature: forged STOP request is rejected", async () => {
  const forged = { From: "+15550001111", Body: "STOP" };
  const ok = await verifyTwilioSignature(TWILIO_DOC_TOKEN, "https://x.test/functions/v1/sms-inbound", forged, "AAAA");
  assert(ok === false, "forged signature must fail");
  const missing = await verifyTwilioSignature(TWILIO_DOC_TOKEN, "https://x.test/functions/v1/sms-inbound", forged, null);
  assert(missing === false, "missing signature must fail");
  const noToken = await verifyTwilioSignature(undefined, "https://x.test/functions/v1/sms-inbound", forged, "AAAA");
  assert(noToken === false, "missing auth token must fail closed");
});

Deno.test("formToRecord: converts FormData to plain record", () => {
  const f = new FormData();
  f.set("From", "+15550001111");
  f.set("Body", "YES");
  const r = formToRecord(f);
  assert(r.From === "+15550001111" && r.Body === "YES", "record mismatch");
});
