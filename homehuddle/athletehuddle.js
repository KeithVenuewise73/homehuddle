/**
 * AthleteHuddle.js
 * Shared JavaScript library for all AthleteHuddle pages.
 * Handles Supabase CRUD, session management, and utilities.
 */

// ─── CONFIG ──────────────────────────────────────────────────────────────────
const SUPABASE_URL = window.SUPABASE_URL || 'https://urwnbskrtoplgnkkxuvl.supabase.co';
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || 'sb_publishable_NnATRFU2t1ATOHR07mFLoQ_ptkdjGDT';

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ─── SESSION ─────────────────────────────────────────────────────────────────

async function getSession() {
  const { data: { session }, error } = await db.auth.getSession();
  if (error) console.error('Session error:', error);
  return session;
}

async function getCurrentFamily() {
  // 1. Read from localStorage (saved by login.html after PIN verified)
  const stored = localStorage.getItem('hh_family');
  if (stored) {
    try {
      const parsed = JSON.parse(stored);
      if (parsed && parsed.id) return parsed;
    } catch(e) {}
  }

  // 2. Check URL params
  const params = new URLSearchParams(window.location.search);
  const emailParam = params.get('email');
  if (emailParam) {
    const { data, error } = await db
      .from('families')
      .select('*')
      .eq('email', emailParam)
      .single();
    if (!error && data) {
      localStorage.setItem('hh_family', JSON.stringify(data));
      return data;
    }
  }

  // 3. Dev fallback: first active family
  const { data: fallback } = await db
    .from('families')
    .select('*')
    .eq('status', 'active')
    .limit(1)
    .single();

  return fallback || null;
}

async function getFamilyId() {
  const family = await getCurrentFamily();
  return family ? family.id : null;
}

// ─── ATHLETES ────────────────────────────────────────────────────────────────

async function getAthletes(familyId) {
  const { data, error } = await db
    .from('athletes')
    .select('*')
    .eq('family_id', familyId)
    .order('first_name');
  if (error) { console.error('getAthletes error:', error); return []; }
  return data || [];
}

async function getAthlete(athleteId) {
  const { data, error } = await db
    .from('athletes')
    .select('*')
    .eq('id', athleteId)
    .single();
  if (error) { console.error('getAthlete error:', error); return null; }
  return data;
}

async function createAthlete(athleteData) {
  const familyId = await getFamilyId();
  if (!familyId) throw new Error('No family found for current user');
  const payload = Object.assign({}, athleteData, { family_id: familyId });
  const { data, error } = await db
    .from('athletes')
    .insert(payload)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function updateAthlete(athleteId, updates) {
  const { data, error } = await db
    .from('athletes')
    .update(updates)
    .eq('id', athleteId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function deleteAthlete(athleteId) {
  const { error } = await db.from('athletes').delete().eq('id', athleteId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE SPORTS ──────────────────────────────────────────────────────────

async function getAthleteSports(athleteId) {
  const { data, error } = await db
    .from('athlete_sports')
    .select('*')
    .eq('athlete_id', athleteId)
    .order('created_at', { ascending: false });
  if (error) { console.error('getAthleteSports error:', error); return []; }
  return data || [];
}

async function addAthleteSport(sportData) {
  const { data, error } = await db.from('athlete_sports').insert(sportData).select().single();
  if (error) throw error;
  return data;
}

async function deleteAthleteSport(sportId) {
  const { error } = await db.from('athlete_sports').delete().eq('id', sportId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE EVENTS ──────────────────────────────────────────────────────────

async function getAthleteEvents(athleteId, limit) {
  limit = limit || 10;
  const now = new Date().toISOString();
  const { data, error } = await db
    .from('athlete_events')
    .select('*')
    .eq('athlete_id', athleteId)
    .gte('start_time', now)
    .order('start_time')
    .limit(limit);
  if (error) { console.error('getAthleteEvents error:', error); return []; }
  return data || [];
}

async function linkEventToAthlete(eventData) {
  const { data, error } = await db.from('athlete_events').insert(eventData).select().single();
  if (error) throw error;
  return data;
}

async function unlinkEventFromAthlete(id) {
  const { error } = await db.from('athlete_events').delete().eq('id', id);
  if (error) throw error;
  return true;
}

// ─── ATHLETE GOALS ───────────────────────────────────────────────────────────

async function getAthleteGoals(athleteId) {
  const { data, error } = await db
    .from('athlete_goals')
    .select('*')
    .eq('athlete_id', athleteId)
    .order('created_at', { ascending: false });
  if (error) { console.error('getAthleteGoals error:', error); return []; }
  return data || [];
}

async function addAthleteGoal(goalData) {
  const { data, error } = await db.from('athlete_goals').insert(goalData).select().single();
  if (error) throw error;
  return data;
}

async function updateGoalStatus(goalId, status) {
  const { data, error } = await db
    .from('athlete_goals')
    .update({ progress_status: status })
    .eq('id', goalId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

async function deleteAthleteGoal(goalId) {
  const { error } = await db.from('athlete_goals').delete().eq('id', goalId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE STATS ───────────────────────────────────────────────────────────

async function getAthleteStats(athleteId, sport) {
  let query = db
    .from('athlete_stats')
    .select('*')
    .eq('athlete_id', athleteId)
    .order('recorded_at', { ascending: false });
  if (sport) query = query.eq('sport', sport);
  const { data, error } = await query;
  if (error) { console.error('getAthleteStats error:', error); return []; }
  return data || [];
}

async function addAthleteStat(statData) {
  const { data, error } = await db.from('athlete_stats').insert(statData).select().single();
  if (error) throw error;
  return data;
}

async function deleteAthleteStat(statId) {
  const { error } = await db.from('athlete_stats').delete().eq('id', statId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE VIDEOS ──────────────────────────────────────────────────────────

async function getAthleteVideos(athleteId) {
  const { data, error } = await db
    .from('athlete_videos')
    .select('*')
    .eq('athlete_id', athleteId)
    .order('created_at', { ascending: false });
  if (error) { console.error('getAthleteVideos error:', error); return []; }
  return data || [];
}

async function addAthleteVideo(videoData) {
  const { data, error } = await db.from('athlete_videos').insert(videoData).select().single();
  if (error) throw error;
  return data;
}

async function deleteAthleteVideo(videoId) {
  const { error } = await db.from('athlete_videos').delete().eq('id', videoId);
  if (error) throw error;
  return true;
}

// ─── COACH CONNECTIONS ───────────────────────────────────────────────────────

async function getCoachConnections(athleteId) {
  const { data, error } = await db
    .from('coach_connections')
    .select('*')
    .eq('athlete_id', athleteId)
    .order('created_at', { ascending: false });
  if (error) { console.error('getCoachConnections error:', error); return []; }
  return data || [];
}

async function addCoachConnection(connectionData) {
  const { data, error } = await db.from('coach_connections').insert(connectionData).select().single();
  if (error) throw error;
  return data;
}

// ─── UTILITIES ───────────────────────────────────────────────────────────────

function calcAge(birthdate) {
  if (!birthdate) return null;
  var today = new Date();
  var birth = new Date(birthdate);
  var age = today.getFullYear() - birth.getFullYear();
  var m = today.getMonth() - birth.getMonth();
  if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--;
  return age;
}

function formatDateTime(isoString) {
  if (!isoString) return '—';
  var d = new Date(isoString);
  return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

function formatHeight(inches) {
  if (!inches) return '—';
  var ft = Math.floor(inches / 12);
  var inch = Math.round(inches % 12);
  return ft + "'" + inch + '"';
}

function getInitials(firstName, lastName) {
  return ((firstName || '')[0] || '') + ((lastName || '')[0] || '').toUpperCase();
}

function goalStatusColor(status) {
  var map = { not_started: '#94a3b8', in_progress: '#3b82f6', achieved: '#22c55e', paused: '#f59e0b' };
  return map[status] || '#94a3b8';
}

function goalStatusLabel(status) {
  var map = { not_started: 'Not Started', in_progress: 'In Progress', achieved: 'Achieved ✓', paused: 'Paused' };
  return map[status] || status;
}

function showToast(message, type) {
  type = type || 'success';
  var existing = document.getElementById('ah-toast');
  if (existing) existing.remove();
  var toast = document.createElement('div');
  toast.id = 'ah-toast';
  toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:' +
    (type === 'error' ? '#ef4444' : '#22c55e') +
    ';color:#fff;padding:12px 24px;border-radius:8px;font-family:DM Sans,sans-serif;font-size:14px;font-weight:600;z-index:9999;box-shadow:0 4px 20px rgba(0,0,0,0.2);';
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(function() { toast.remove(); }, 3500);
}

function setActiveAthlete(athleteId) {
  sessionStorage.setItem('ah_athlete_id', athleteId);
}

function getActiveAthlete() {
  return sessionStorage.getItem('ah_athlete_id');
}
