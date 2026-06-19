/* FacilityHuddle — dashboard.js
   Uses the shared ohGet/ohInsert/ohUpdate/ohToast/ohAlert helpers from
   assets/js/main.js. */

let facilityData = null, facilityId = null, areas = [], bookings = [], openSlots = [];

function fhSaveSession(email, facility) {
  sessionStorage.setItem('fh_dash_email', email);
  sessionStorage.setItem('fh_dash_facility', JSON.stringify(facility));
}
function fhLoadSession() {
  const e = sessionStorage.getItem('fh_dash_email'), f = sessionStorage.getItem('fh_dash_facility');
  if (e && f) { try { return { email: e, facility: JSON.parse(f) }; } catch (x) {} }
  return null;
}
function fhClearSession() {
  sessionStorage.removeItem('fh_dash_email');
  sessionStorage.removeItem('fh_dash_facility');
}

async function fhLogin() {
  const email = document.getElementById('login-email').value.trim();
  const code = document.getElementById('login-code').value;
  if (!email || !code) { ohAlert('login-err', 'Please enter your email and access code.', 'error'); return; }
  const btn = document.getElementById('login-btn');
  btn.textContent = 'Signing in…'; btn.disabled = true;
  try {
    const matches = await ohGet('facilities', { 'contact_email': `eq.${email}`, 'select': '*' });
    if (!matches.length) {
      ohAlert('login-err', 'No FacilityHuddle profile found for this email.', 'error');
      btn.textContent = 'Sign In →'; btn.disabled = false; return;
    }
    const facility = matches[0];
    if (facility.access_code !== code) {
      ohAlert('login-err', 'Incorrect access code. Contact Venuewise to get access.', 'error');
      btn.textContent = 'Sign In →'; btn.disabled = false; return;
    }
    facilityData = facility; facilityId = facility.id;
    fhSaveSession(email, facility);
    fhLaunchApp();
  } catch (e) {
    ohAlert('login-err', 'Could not connect. Please try again.', 'error');
    btn.textContent = 'Sign In →'; btn.disabled = false;
  }
}

function fhLogout() {
  fhClearSession(); facilityData = null; facilityId = null;
  document.getElementById('app').style.display = 'none';
  document.getElementById('login-screen').style.display = 'flex';
}

async function fhLaunchApp() {
  document.getElementById('login-screen').style.display = 'none';
  document.getElementById('app').style.display = 'block';
  document.getElementById('dash-facility-name').textContent = facilityData.name || '';

  try { areas = await ohGet('facility_areas', { 'facility_id': `eq.${facilityId}`, 'select': '*', 'order': 'display_order.asc' }); } catch (e) { areas = []; }
  try { bookings = await ohGet('bookings', { 'facility_id': `eq.${facilityId}`, 'select': '*', 'order': 'start_time.asc' }); } catch (e) { bookings = []; }
  try { openSlots = await ohGet('open_slots', { 'facility_id': `eq.${facilityId}`, 'status': 'eq.open', 'select': '*', 'order': 'start_time.asc' }); } catch (e) { openSlots = []; }

  fhPopulateAreaSelect();
  fhRenderOverview();
  fhRenderCalendar();
  fhRenderMarketplace();
}

function fhAreaById(id) { return areas.find(a => a.id === id); }

function fhFmtMoney(n) {
  return Number(n || 0).toLocaleString('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
}
function fhFmtRange(start, end) {
  const s = new Date(start), e = new Date(end);
  const opts = { weekday: 'short', month: 'short', day: 'numeric' };
  const timeOpts = { hour: 'numeric', minute: '2-digit' };
  return `${s.toLocaleDateString('en-US', opts)} · ${s.toLocaleTimeString('en-US', timeOpts)} – ${e.toLocaleTimeString('en-US', timeOpts)}`;
}

function fhPopulateAreaSelect() {
  const sel = document.getElementById('c-area');
  if (!sel) return;
  sel.innerHTML = areas.map(a => `<option value="${a.id}">${a.name} (${a.area_type})</option>`).join('');
}

function fhRenderOverview() {
  const potential = openSlots.reduce((sum, o) => sum + Number(o.price || 0), 0);
  document.getElementById('s-areas').textContent = areas.length;
  document.getElementById('s-bookings').textContent = bookings.filter(b => b.status === 'confirmed').length;
  document.getElementById('s-open').textContent = openSlots.length;
  document.getElementById('s-potential').textContent = fhFmtMoney(potential);
  document.getElementById('hero-amount').textContent = `${fhFmtMoney(potential)} sitting in open inventory right now`;

  const cancelled = bookings.find(b => b.status === 'cancelled');
  const areaCount = new Set(openSlots.map(o => o.area_id)).size;
  document.getElementById('hero-sub').textContent = openSlots.length
    ? `${openSlots.length} open slot${openSlots.length === 1 ? '' : 's'} across ${areaCount} area${areaCount === 1 ? '' : 's'}${cancelled ? `, including a cancellation from ${cancelled.customer_name}` : ''}.`
    : 'No open slots right now — fully booked.';

  const el = document.getElementById('overview-bookings');
  const recent = bookings.slice(0, 5);
  el.innerHTML = recent.length ? recent.map(b => {
    const area = fhAreaById(b.area_id);
    return `<div class="row-item">
      <div style="display:flex;align-items:center;gap:10px">
        <div style="width:8px;height:8px;border-radius:50%;background:${area ? area.color : '#5B6B82'}"></div>
        <div>
          <div style="font-size:13.5px;font-weight:600">${b.customer_name || b.title || 'Booking'}</div>
          <div style="font-size:11.5px;color:var(--slate)">${area ? area.name : ''} · ${fhFmtRange(b.start_time, b.end_time)}</div>
        </div>
      </div>
      <span class="pill ${b.status === 'cancelled' ? 'pill-cancelled' : 'pill-confirmed'}">${b.status === 'cancelled' ? 'Cancelled' : fhFmtMoney(b.amount)}</span>
    </div>`;
  }).join('') : '<p style="font-size:13px;color:var(--slate);font-style:italic">No bookings yet.</p>';
}

function fhRenderCalendar() {
  const el = document.getElementById('calendar-list');
  el.innerHTML = bookings.length ? bookings.map(b => {
    const area = fhAreaById(b.area_id);
    return `<div class="row-item">
      <div>
        <div style="font-size:14px;font-weight:600">${b.customer_name || b.title || 'Booking'}</div>
        <div style="font-size:12px;color:var(--slate)">${area ? area.name : ''} · ${b.booking_type ? b.booking_type.replace(/_/g, ' ') : ''} · ${fhFmtRange(b.start_time, b.end_time)}</div>
        ${b.notes ? `<div style="font-size:11.5px;color:rgba(14,23,38,.45);margin-top:3px;font-style:italic">${b.notes}</div>` : ''}
      </div>
      <span class="pill ${b.status === 'cancelled' ? 'pill-cancelled' : 'pill-confirmed'}">${b.status}</span>
    </div>`;
  }).join('') : '<p style="font-size:13px;color:var(--slate);font-style:italic;text-align:center;padding:24px 0">No bookings yet.</p>';
}

function fhRenderMarketplace() {
  const el = document.getElementById('marketplace-list');
  el.innerHTML = openSlots.length ? openSlots.map(slot => {
    const area = fhAreaById(slot.area_id);
    const isCancellation = slot.source === 'cancellation';
    return `<div class="slot-card ${isCancellation ? 'cancellation' : ''}" id="slot-${slot.id}">
      ${isCancellation ? '<div class="fill-badge">JUST CANCELLED</div>' : ''}
      <div style="display:flex;align-items:center;gap:8px;margin-top:${isCancellation ? '8px' : '0'}">
        <div style="width:10px;height:10px;border-radius:3px;background:${area ? area.color : '#5B6B82'}"></div>
        <span style="font-weight:700;font-size:14.5px">${area ? area.name : 'Area'}</span>
        <span style="font-size:11.5px;color:var(--slate)">· ${area ? area.area_type : ''}</span>
      </div>
      <div style="margin-top:12px;font-size:14px;font-weight:600">${fhFmtRange(slot.start_time, slot.end_time)}</div>
      <div style="margin-top:6px;font-size:12.5px;color:var(--slate)">${slot.reason || ''}</div>
      <div class="fh-display" style="font-size:22px;font-weight:800;margin-top:14px">${fhFmtMoney(slot.price)}</div>
      <button class="fill-btn" onclick="fhFillSlot('${slot.id}')">FILL THIS SLOT</button>
    </div>`;
  }).join('') : '<p style="font-size:13px;color:var(--slate);font-style:italic">No open slots right now — fully booked.</p>';
}

async function fhFillSlot(slotId) {
  const slot = openSlots.find(s => s.id === slotId);
  if (!slot) return;
  try {
    const ok = await ohUpdate('open_slots', slotId, { status: 'claimed', claimed_at: new Date().toISOString() });
    if (!ok) throw new Error('update failed');
    openSlots = openSlots.filter(s => s.id !== slotId);
    ohToast('Slot claimed — booking confirmation sent.', 'success');
    fhRenderMarketplace();
    fhRenderOverview();
  } catch (e) {
    ohAlert('marketplace-alert', 'Could not claim this slot. Please try again.', 'error');
  }
}

async function fhPublishSlot() {
  const areaId = document.getElementById('c-area').value;
  const start = document.getElementById('c-start').value;
  const end = document.getElementById('c-end').value;
  const price = document.getElementById('c-price').value;
  const reason = document.getElementById('c-reason').value.trim();
  if (!areaId || !start || !end) {
    ohAlert('create-alert', 'Please choose an area, start time, and end time.', 'error');
    return;
  }
  try {
    const created = await ohInsert('open_slots', {
      facility_id: facilityId,
      area_id: areaId,
      source: 'unbooked',
      start_time: new Date(start).toISOString(),
      end_time: new Date(end).toISOString(),
      price: Number(price) || 0,
      reason: reason || 'Manually listed by facility staff',
      status: 'open'
    });
    openSlots.push(created[0]);
    ohAlert('create-alert', 'Slot published to the marketplace.', 'success');
    fhRenderMarketplace();
    fhRenderOverview();
  } catch (e) {
    ohAlert('create-alert', 'Could not publish this slot. Please try again.', 'error');
  }
}

function fhShowPanel(name, btn) {
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.getElementById('panel-' + name).classList.add('active');
  if (btn) {
    document.querySelectorAll('.sb-link').forEach(l => l.classList.remove('active'));
    btn.classList.add('active');
  }
}

const fhSess = fhLoadSession();
if (fhSess) { facilityData = fhSess.facility; facilityId = facilityData.id; fhLaunchApp(); }
