// HomeHuddle — send-notifications Edge Function

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SERVICE_ROLE_KEY')!;
const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY')!;
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!;
const VAPID_SUBJECT = 'mailto:keith@venuewise.net';

const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

function b64urlToBytes(str: string): Uint8Array {
  const pad = (4 - str.length % 4) % 4;
  return Uint8Array.from(atob(str.replace(/-/g,'+').replace(/_/g,'/') + '='.repeat(pad)), c => c.charCodeAt(0));
}

function bytesToB64url(buf: ArrayBuffer | Uint8Array): string {
  const arr = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  return btoa(String.fromCharCode(...arr)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'');
}

async function importVapidPrivateKey(): Promise<CryptoKey> {
  const pkcs8Bytes = b64urlToBytes(VAPID_PRIVATE_KEY);
  return crypto.subtle.importKey(
    'pkcs8', pkcs8Bytes,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false, ['sign']
  );
}

async function makeVapidJwt(endpoint: string): Promise<string> {
  const url = new URL(endpoint);
  const audience = `${url.protocol}//${url.host}`;
  const exp = Math.floor(Date.now() / 1000) + 43200;

  const header = bytesToB64url(new TextEncoder().encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payload = bytesToB64url(new TextEncoder().encode(JSON.stringify({ aud: audience, exp, sub: VAPID_SUBJECT })));
  const unsigned = `${header}.${payload}`;

  const privKey = await importVapidPrivateKey();
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    privKey,
    new TextEncoder().encode(unsigned)
  );

  return `${unsigned}.${bytesToB64url(sig)}`;
}

async function sendPush(endpoint: string, keys: { auth: string; p256dh: string }, title: string, body: string, url: string): Promise<number> {
  try {
    const jwt = await makeVapidJwt(endpoint);
    const payloadBytes = new TextEncoder().encode(JSON.stringify({ title, body, url, icon: '/icon-192.png', tag: 'homehuddle' }));

    const authSecret = b64urlToBytes(keys.auth);
    const receiverPubKey = b64urlToBytes(keys.p256dh);

    const senderPair = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
    const senderPubRaw = new Uint8Array(await crypto.subtle.exportKey('raw', senderPair.publicKey));
    const receiverKey = await crypto.subtle.importKey('raw', receiverPubKey, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
    const sharedSecret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: receiverKey }, senderPair.privateKey, 256));

    const salt = crypto.getRandomValues(new Uint8Array(16));
    const enc = new TextEncoder();

    const ikmKey = await crypto.subtle.importKey('raw', sharedSecret, { name: 'HKDF' }, false, ['deriveBits']);
    const prk = new Uint8Array(await crypto.subtle.deriveBits(
      { name: 'HKDF', hash: 'SHA-256', salt: authSecret, info: enc.encode('Content-Encoding: auth\0') },
      ikmKey, 256
    ));

    const prkKey = await crypto.subtle.importKey('raw', prk, { name: 'HKDF' }, false, ['deriveBits']);
    const keyInfo = new Uint8Array([...enc.encode('Content-Encoding: aes128gcm\0'), 0, 65, ...senderPubRaw, ...receiverPubKey]);
    const nonceInfo = new Uint8Array([...enc.encode('Content-Encoding: nonce\0'), 0, 65, ...senderPubRaw, ...receiverPubKey]);

    const cekRaw = new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: keyInfo }, prkKey, 128));
    const nonceRaw = new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info: nonceInfo }, prkKey, 96));

    const cek = await crypto.subtle.importKey('raw', cekRaw, { name: 'AES-GCM' }, false, ['encrypt']);
    const encrypted = new Uint8Array(await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonceRaw },
      cek,
      new Uint8Array([...payloadBytes, 2])
    ));

    const rs = new Uint8Array(4);
    new DataView(rs.buffer).setUint32(0, 4096, false);
    const content = new Uint8Array([...salt, ...rs, senderPubRaw.length, ...senderPubRaw, ...encrypted]);

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `vapid t=${jwt}, k=${VAPID_PUBLIC_KEY}`,
        'Content-Type': 'application/octet-stream',
        'Content-Encoding': 'aes128gcm',
        'TTL': '86400',
      },
      body: content,
    });

    const resText = await res.text();
    console.log('Push response:', res.status, resText);
    return res.status;
  } catch(e) {
    console.error('sendPush error:', e);
    return 0;
  }
}

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const { type, email, title, conflictWith, time } = body;
    if (!email) return new Response(JSON.stringify({ error: 'email required' }), { status: 400 });

    const { data: subs } = await sb.from('push_subscriptions').select('endpoint, keys').eq('email', email);
    if (!subs || !subs.length) return new Response(JSON.stringify({ sent: 0, reason: 'no subscriptions' }), { status: 200 });

    let sent = 0;
    const calUrl = `https://venuewise.net/calendar.html?email=${encodeURIComponent(email)}`;

    if (type === 'test') {
      for (const sub of subs) {
        const s = await sendPush(sub.endpoint, sub.keys, '🏠 HomeHuddle', 'Push notifications are working!', calUrl);
        if (s >= 200 && s < 300) sent++;
      }
    }

    if (type === 'reminder') {
      const today = new Date().toISOString().slice(0, 10);
      const { data: reminders } = await sb.from('reminders').select('*').eq('email', email).eq('event_date', today).eq('dismissed', false);
      for (const r of reminders || []) {
        for (const sub of subs) {
          const s = await sendPush(sub.endpoint, sub.keys, '📅 HomeHuddle Reminder', r.message, calUrl);
          if (s >= 200 && s < 300) sent++;
        }
      }
    }

    if (type === 'conflict') {
      for (const sub of subs) {
        const s = await sendPush(sub.endpoint, sub.keys, '⚠️ Schedule Conflict', `${title} overlaps with ${conflictWith} at ${time}`, calUrl);
        if (s >= 200 && s < 300) sent++;
      }
    }

    return new Response(JSON.stringify({ sent }), { status: 200 });
  } catch(e) {
    console.error('handler error:', e);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});