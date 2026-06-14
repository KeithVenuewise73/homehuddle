/* ============================================================
   CoachesHuddle — main.js
   Shared Supabase helpers + nav/footer inject
   ============================================================ */

const CH_SURL = 'https://urwnbskrtoplgnkkxuvl.supabase.co';
const CH_SKEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyd25ic2tydG9wbGdua2t4dXZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwNDgyMjMsImV4cCI6MjA5NDYyNDIyM30._BpvQsf6Ub5nwxY8jD3aGDLvyk0-_vBA4s6LREZ9ShQ';

/* ── Supabase helpers ── */
async function chGet(table, params = {}) {
  const url = new URL(`${CH_SURL}/rest/v1/${table}`);
  Object.entries(params).forEach(([k,v]) => url.searchParams.set(k, v));
  const res = await fetch(url.toString(), {
    headers: { 'apikey': CH_SKEY, 'Authorization': `Bearer ${CH_SKEY}` }
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

async function chInsert(table, data) {
  const res = await fetch(`${CH_SURL}/rest/v1/${table}`, {
    method: 'POST',
    headers: {
      'apikey': CH_SKEY, 'Authorization': `Bearer ${CH_SKEY}`,
      'Content-Type': 'application/json', 'Prefer': 'return=representation'
    },
    body: JSON.stringify(data)
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

async function chUpdate(table, id, data) {
  const res = await fetch(`${CH_SURL}/rest/v1/${table}?id=eq.${id}`, {
    method: 'PATCH',
    headers: {
      'apikey': CH_SKEY, 'Authorization': `Bearer ${CH_SKEY}`,
      'Content-Type': 'application/json', 'Prefer': 'return=minimal'
    },
    body: JSON.stringify(data)
  });
  return res.ok;
}

/* ── Toast ── */
function chToast(msg, type = 'success') {
  let t = document.getElementById('ch-toast');
  if (!t) {
    t = document.createElement('div');
    t.id = 'ch-toast';
    t.style.cssText = 'position:fixed;bottom:24px;right:24px;padding:12px 18px;border-radius:10px;font-size:13px;font-weight:600;z-index:9999;transform:translateY(80px);opacity:0;transition:all .3s;pointer-events:none;font-family:DM Sans,sans-serif;max-width:320px;';
    document.body.appendChild(t);
  }
  const colors = {
    success: 'background:#111;border:1px solid rgba(34,197,94,.4);color:#4ade80',
    error:   'background:#111;border:1px solid rgba(239,68,68,.4);color:#f87171',
    info:    'background:#111;border:1px solid rgba(201,162,39,.4);color:#E8BF45'
  };
  t.style.cssText += ';' + (colors[type] || colors.success);
  t.textContent = msg;
  t.style.transform = 'translateY(0)'; t.style.opacity = '1';
  clearTimeout(t._to);
  t._to = setTimeout(() => { t.style.transform = 'translateY(80px)'; t.style.opacity = '0'; }, 3500);
}

/* ── Alert helper ── */
function chAlert(id, msg, type = 'success') {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = msg;
  el.className = `ch-alert ${type}`;
  el.style.display = 'block';
  el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

/* ── Nav inject ── */
function chInjectNav(activePage = '') {
  const pages = [
    { href: 'index.html', label: 'Home' },
    { href: 'coach-directory.html', label: 'Find a Coach' },
    { href: 'join.html', label: 'Join' },
    { href: 'dashboard.html', label: 'Dashboard' },
  ];
  const links = pages.map(p =>
    `<a href="${p.href}" class="${activePage===p.label?'active':''}">${p.label}</a>`
  ).join('');
  const nav = `
  <nav class="ch-nav">
    <a href="index.html" class="ch-nav-brand">
      <div class="ch-nav-logo">Coaches<span>Huddle</span></div>
      <div class="ch-nav-powered">POWERED BY <a href="https://venuewise.net">VENUEWISE</a></div>
    </a>
    <div class="ch-nav-links">
      ${links}
      <a href="profile-create.html" class="ch-nav-cta">Create Profile</a>
    </div>
  </nav>`;
  document.body.insertAdjacentHTML('afterbegin', nav);
}

/* ── Eco bar + Footer inject ── */
function chInjectFooter() {
  document.body.insertAdjacentHTML('beforeend', `
  <footer class="ch-footer">
    <div class="ch-footer-inner">
      <div>
        <div class="ch-footer-brand-name">Coaches<span>Huddle</span></div>
        <p class="ch-footer-tagline">Help Athletes Find You. Help Families Trust You.</p>
        <p class="ch-footer-powered">Powered by <a href="https://venuewise.net">Venuewise</a></p>
      </div>
      <div class="ch-footer-col">
        <h5>CoachesHuddle</h5>
        <a href="index.html">Home</a>
        <a href="coach-directory.html">Find a Coach</a>
        <a href="profile-create.html">Create Profile</a>
        <a href="spotlight-submit.html">Submit for Spotlight</a>
        <a href="dashboard.html">Coach Dashboard</a>
      </div>
      <div class="ch-footer-col">
        <h5>Venuewise</h5>
        <a href="https://venuewise.net/homehuddle/">HomeHuddle</a>
        <a href="https://venuewise.net/homehuddle/family--athlete.html">AthleteHuddle</a>
        <a href="https://venuewise.net/homehuddle/organizationhuddle.html">OrganizationHuddle</a>
        <a href="https://venuewise.net/homehuddle/facilityhuddle.html">FacilityHuddle</a>
      </div>
      <div class="ch-footer-col">
        <h5>Media</h5>
        <a href="https://5starsportsmedia.com" style="color:var(--gold)">5-Star Sports Media ↗</a>
        <a href="https://5starsportsmedia.com/coach-spotlight.html">Coach Spotlights</a>
        <a href="contact.html">Contact</a>
        <a href="https://venuewise.net/homehuddle/privacy.html">Privacy</a>
      </div>
    </div>
    <div class="ch-footer-bottom">
      <p class="ch-footer-copy">&copy; <span class="yr"></span> <a href="https://venuewise.net">Venuewise</a>. All rights reserved.</p>
      <p class="ch-footer-copy" style="font-style:italic">Coach Spotlight coverage is earned, not purchased.</p>
    </div>
  </footer>
  <div class="eco-bar">
    <div class="eco-bar-inner">
      <span class="eco-bar-text">★ <strong>Venuewise Ecosystem</strong> — One connected platform for sports families</span>
      <div class="eco-bar-links">
        <a href="https://venuewise.net/homehuddle/">HomeHuddle</a>
        <a href="https://venuewise.net/homehuddle/family--athlete.html">AthleteHuddle</a>
        <a href="index.html" class="active">CoachesHuddle</a>
        <a href="https://venuewise.net/homehuddle/organizationhuddle.html">OrganizationHuddle</a>
        <a href="https://venuewise.net/homehuddle/facilityhuddle.html">FacilityHuddle</a>
        <a href="https://5starsportsmedia.com" style="color:var(--gold);font-weight:700">5-Star Sports Media ↗</a>
      </div>
    </div>
  </div>`);
  document.querySelectorAll('.yr').forEach(el => el.textContent = new Date().getFullYear());
}

/* ── URL param helper ── */
function chParam(name) {
  return new URLSearchParams(window.location.search).get(name);
}

/* ── Session: store coach email in sessionStorage ── */
function chSaveCoachSession(email) { sessionStorage.setItem('ch_coach_email', email); }
function chGetCoachEmail() { return sessionStorage.getItem('ch_coach_email'); }
