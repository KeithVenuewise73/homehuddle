/**
 * AthleteHuddle.js
 * Shared JavaScript library for all AthleteHuddle pages.
 * Handles Supabase CRUD, session management, and utilities.
 *
 * Dependencies:
 *   - Supabase JS v2 (loaded via CDN in each HTML page)
 *   - SUPABASE_URL and SUPABASE_ANON_KEY must be set before this script loads
 */

// ─── CONFIG ──────────────────────────────────────────────────────────────────
// Replace these with your actual Supabase project values
const SUPABASE_URL = window.SUPABASE_URL || 'https://urwnbskrtoplgnkkxuvl.supabase.co';
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || 'sb_publishable_NnATRFU2t1ATOHR07mFLoQ_ptkdjGDT';

// Initialize Supabase client (v2 CDN global)
const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ─── SESSION ─────────────────────────────────────────────────────────────────

/**
 * Get the current authenticated session.
 * In HomeHuddle's PIN/email auth, adapt this to match your auth flow.
 */
async function getSession() {
  const { data: { session }, error } = await db.auth.getSession();
  if (error) console.error('Session error:', error);
  return session;
}

/**
 * Get the family record for the current user.
 * Uses email from session to look up family.
 */
async function getCurrentFamily() {
  // Your families table columns: id, family_name, email, phone, pin, status
  // Try live Supabase auth session first
  const session = await getSession();
  const email = session?.user?.email;

  if (email) {
    const { data, error } = await db
      .from('families')
      .select('*')
      .eq('email', email)
      .single();
    if (!error && data) return data;
  }

  // Dev/demo fallback: use the first active family (Herman Family)
  // Remove once auth is fully wired in HomeHuddle
  const { data: fallback } = await db
    .from('families')
    .select('*')
    .eq('status', 'active')
    .limit(1)
    .single();

  return fallback || null;
}

/**
 * Convenience: get family_id for current session.
 * Used throughout as the anchor for all athlete queries.
 */
async function getFamilyId() {
  const family = await getCurrentFamily();
  return family?.id || null;
}

// ─── ATHLETES ─────────────────────────────────────────────────────────────────

/**
 * Get all athletes for the current family.
 */
async function getAthletes(familyId) {
  const { data, error } = await db
    .from('athletes')
    .select('*')
    .eq('family_id', familyId)
    .order('first_name');

  if (error) { console.error('getAthletes error:', error); return []; }
  return data || [];
}

/**
 * Get a single athlete by ID.
 */
async function getAthlete(athleteId) {
  const { data, error } = await db
    .from('athletes')
    .select('*')
    .eq('id', athleteId)
    .single();

  if (error) { console.error('getAthlete error:', error); return null; }
  return data;
}

/**
 * Create a new athlete profile.
 * @param {object} athleteData - fields matching the athletes table
 */
async function createAthlete(athleteData) {
  const familyId = await getFamilyId();
  if (!familyId) throw new Error('No family found for current user');

  const payload = { ...athleteData, family_id: familyId };

  const { data, error } = await db
    .from('athletes')
    .insert(payload)
    .select()
    .single();

  if (error) throw error;
  return data;
}

/**
 * Update an existing athlete profile.
 */
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

/**
 * Delete an athlete (cascades to all child tables via FK).
 */
async function deleteAthlete(athleteId) {
  const { error } = await db
    .from('athletes')
    .delete()
    .eq('id', athleteId);

  if (error) throw error;
  return true;
}

// ─── ATHLETE SPORTS ───────────────────────────────────────────────────────────

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
  const { data, error } = await db
    .from('athlete_sports')
    .insert(sportData)
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function updateAthleteSport(sportId, updates) {
  const { data, error } = await db
    .from('athlete_sports')
    .update(updates)
    .eq('id', sportId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function deleteAthleteSport(sportId) {
  const { error } = await db.from('athlete_sports').delete().eq('id', sportId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE EVENTS ───────────────────────────────────────────────────────────

async function getAthleteEvents(athleteId, limit = 10) {
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
  const { data, error } = await db
    .from('athlete_events')
    .insert(eventData)
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function unlinkEventFromAthlete(id) {
  const { error } = await db.from('athlete_events').delete().eq('id', id);
  if (error) throw error;
  return true;
}

// ─── ATHLETE GOALS ─────────────────────────────────────────────────────────────

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
  const { data, error } = await db
    .from('athlete_goals')
    .insert(goalData)
    .select()
    .single();

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

// ─── ATHLETE STATS ─────────────────────────────────────────────────────────────

async function getAthleteStats(athleteId, sport = null) {
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
  const { data, error } = await db
    .from('athlete_stats')
    .insert(statData)
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function deleteAthleteStat(statId) {
  const { error } = await db.from('athlete_stats').delete().eq('id', statId);
  if (error) throw error;
  return true;
}

// ─── ATHLETE VIDEOS ───────────────────────────────────────────────────────────

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
  const { data, error } = await db
    .from('athlete_videos')
    .insert(videoData)
    .select()
    .single();

  if (error) throw error;
  return data;
}

async function deleteAthleteVideo(videoId) {
  const { error } = await db.from('athlete_videos').delete().eq('id', videoId);
  if (error) throw error;
  return true;
}

// ─── COACH CONNECTIONS ────────────────────────────────────────────────────────

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
  const { data, error } = await db
    .from('coach_connections')
    .insert(connectionData)
    .select()
    .single();

  if (error) throw error;
  return data;
}

// ─── UTILITIES ────────────────────────────────────────────────────────────────

/**
 * Calculate age from birthdate string.
 */
function calcAge(birthdate) {
  if (!birthdate) return null;
  const today = new Date();
  const birth = new Date(birthdate);
  let age = today.getFullYear() - birth.getFullYear();
  const m = today.getMonth() - birth.getMonth();
  if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--;
  return age;
}

/**
 * Format a date/time for display.
 */
function formatDateTime(isoString) {
  if (!isoString) return '—';
  const d = new Date(isoString);
  return d.toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric',
    hour: 'numeric', minute: '2-digit'
  });
}

/**
 * Format height from inches to ft/in display.
 */
function formatHeight(inches) {
  if (!inches) return '—';
  const ft = Math.floor(inches / 12);
  const inch = Math.round(inches % 12);
  return `${ft}'${inch}"`;
}

/**
 * Get initials from first/last name.
 */
function getInitials(firstName, lastName) {
  return `${(firstName || '')[0] || ''}${(lastName || '')[0] || ''}`.toUpperCase();
}

/**
 * Goal status badge color helper.
 */
function goalStatusColor(status) {
  const map = {
    not_started: '#94a3b8',
    in_progress: '#3b82f6',
    achieved: '#22c55e',
    paused: '#f59e0b'
  };
  return map[status] || '#94a3b8';
}

/**
 * Goal status label.
 */
function goalStatusLabel(status) {
  const map = {
    not_started: 'Not Started',
    in_progress: 'In Progress',
    achieved: 'Achieved ✓',
    paused: 'Paused'
  };
  return map[status] || status;
}

/**
 * Show a toast notification.
 */
function showToast(message, type = 'success') {
  const existing = document.getElementById('ah-toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.id = 'ah-toast';
  toast.style.cssText = `
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
    background: ${type === 'error' ? '#ef4444' : '#22c55e'};
    color: #fff; padding: 12px 24px; border-radius: 8px;
    font-family: 'DM Sans', sans-serif; font-size: 14px; font-weight: 600;
    z-index: 9999; box-shadow: 0 4px 20px rgba(0,0,0,0.2);
    animation: slideUp 0.3s ease;
  `;
  toast.textContent = message;

  const style = document.createElement('style');
  style.textContent = `@keyframes slideUp { from { opacity:0; transform: translateX(-50%) translateY(20px); } to { opacity:1; transform: translateX(-50%) translateY(0); } }`;
  document.head.appendChild(style);
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3500);
}

/**
 * Save athleteId to sessionStorage for cross-page navigation.
 */
function setActiveAthlete(athleteId) {
  sessionStorage.setItem('ah_athlete_id', athleteId);
}

function getActiveAthlete() {
  return sessionStorage.getItem('ah_athlete_id');
}
