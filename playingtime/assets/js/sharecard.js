/* ============================================================================
 * PlayingTime Football — sharecard.js
 * Renders the shareable game card (§21) onto a canvas.
 *
 * Everything drawn here comes from the derived game. Nothing on the card is
 * decorative-but-false: if a number was not tracked, it is not on the card.
 * That is also what makes the card worth sharing — it is a real record of a real
 * game, not a template with a name dropped into it.
 *
 * 1080x1350 is the portrait aspect that survives Instagram, Facebook and iMessage
 * without being re-cropped.
 * ========================================================================== */

import { UNITS } from './catalog.js';
import { statLines } from './engine.js';

const W = 1080;
const H = 1350;

const INK = {
  bg: '#0B0E12',
  panel: '#151A21',
  line: '#2E3742',
  text: '#F4F7FA',
  dim: '#97A3B2',
  faint: '#67727F',
  green: '#22C58F'
};

const SANS = "'DM Sans', -apple-system, 'Segoe UI', Roboto, sans-serif";
const SERIF = "'DM Serif Display', Georgia, serif";

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function text(ctx, str, x, y, { size = 32, weight = 400, color = INK.text, align = 'left', font = SANS, spacing = 0 } = {}) {
  ctx.save();
  ctx.font = `${weight} ${size}px ${font}`;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = 'alphabetic';
  if (spacing && ctx.letterSpacing !== undefined) ctx.letterSpacing = `${spacing}px`;
  ctx.fillText(str, x, y);
  ctx.restore();
}

/** Shrink a string until it fits, so a long name never overruns the card. */
function fitText(ctx, str, maxWidth, startSize, weight, font) {
  let size = startSize;
  ctx.save();
  for (; size > 22; size -= 2) {
    ctx.font = `${weight} ${size}px ${font}`;
    if (ctx.measureText(str).width <= maxWidth) break;
  }
  ctx.restore();
  return size;
}

/**
 * Pick the statistics worth putting on a card: the ones with the highest counts,
 * plus combined tackles where they exist. Capped at six so the card stays legible
 * at thumbnail size.
 */
function headlineStats(derived) {
  const out = [];
  if (derived.derived.tackles > 0) {
    out.push({ label: 'TACKLES', value: String(derived.derived.tackles) });
  }
  const skip = new Set(['solo_tackle', 'assist_tackle']);
  const lines = UNITS
    .flatMap((u) => statLines(derived.stats, u.id))
    .filter((l) => !skip.has(l.id))
    .sort((a, b) => b.count - a.count);

  for (const l of lines) {
    if (out.length >= 6) break;
    const yards = l.yards !== null && l.yardsKnown > 0 ? ` · ${l.yards >= 0 ? '+' : ''}${l.yards} YDS` : '';
    out.push({ label: l.label + yards, value: String(l.count) });
  }
  return out;
}

/**
 * Draw the card.
 * @param {HTMLCanvasElement} canvas
 * @param {{game, athlete, derived, vsLine}} data
 */
export function drawShareCard(canvas, { game, athlete, derived, vsLine }) {
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext('2d');

  /* Ground */
  ctx.fillStyle = INK.bg;
  ctx.fillRect(0, 0, W, H);

  /* A field-lines motif, quiet enough to stay behind the numbers */
  ctx.save();
  ctx.strokeStyle = 'rgba(34,197,143,.07)';
  ctx.lineWidth = 3;
  for (let x = 90; x < W; x += 90) {
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, H); ctx.stroke();
  }
  ctx.restore();

  /* Top glow */
  const glow = ctx.createLinearGradient(0, 0, 0, 420);
  glow.addColorStop(0, 'rgba(34,197,143,.16)');
  glow.addColorStop(1, 'rgba(34,197,143,0)');
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, W, 420);

  /* ---- Header ---- */
  ctx.save();
  const markX = 72, markY = 70, markS = 62;
  const markGrad = ctx.createLinearGradient(markX, markY, markX + markS, markY + markS);
  markGrad.addColorStop(0, '#22C58F');
  markGrad.addColorStop(1, '#0F6E56');
  ctx.fillStyle = markGrad;
  roundRect(ctx, markX, markY, markS, markS, 18);
  ctx.fill();
  ctx.restore();
  text(ctx, 'PT', markX + markS / 2, markY + 43, { size: 28, weight: 700, color: '#06231B', align: 'center' });

  text(ctx, 'PLAYINGTIME', markX + markS + 20, markY + 27, { size: 26, weight: 700, spacing: 2 });
  text(ctx, 'FOOTBALL', markX + markS + 20, markY + 55, { size: 20, weight: 600, color: INK.faint, spacing: 4 });

  /* ---- Identity ---- */
  const nameSize = fitText(ctx, athlete.name || 'Athlete', W - 144, 82, 400, SERIF);
  text(ctx, athlete.name || 'Athlete', 72, 258, { size: nameSize, weight: 400, font: SERIF });

  const idBits = [
    athlete.jerseyNumber ? `#${athlete.jerseyNumber}` : null,
    [athlete.primaryPosition, athlete.secondaryPosition].filter(Boolean).join(' / ') || null,
    athlete.team || null
  ].filter(Boolean).join('  ·  ');
  text(ctx, idBits, 72, 302, { size: 27, weight: 500, color: INK.dim });

  text(ctx, vsLine.toUpperCase(), 72, 356, { size: 30, weight: 700, color: INK.green, spacing: 1 });

  /* ---- Participation hero ---- */
  const heroY = 400;
  ctx.fillStyle = INK.panel;
  roundRect(ctx, 72, heroY, W - 144, 250, 28);
  ctx.fill();
  ctx.strokeStyle = INK.line;
  ctx.lineWidth = 2;
  ctx.stroke();

  const totals = derived.totals;
  const hasPlays = totals.teamPlays > 0;

  text(ctx, hasPlays ? `${totals.participation}%` : '—', 100, heroY + 138,
    { size: 116, weight: 700, color: INK.green });
  text(ctx, 'PARTICIPATION', 104, heroY + 186, { size: 22, weight: 700, color: INK.faint, spacing: 3 });

  text(ctx, String(totals.athletePlays), W - 100, heroY + 108, { size: 74, weight: 700, align: 'right' });
  text(ctx, `OF ${totals.teamPlays} PLAYS`, W - 100, heroY + 148, { size: 21, weight: 700, color: INK.faint, align: 'right', spacing: 2 });

  /* Per-unit line, only for units that were actually on the field */
  const unitBits = UNITS
    .filter((u) => derived.units[u.id].teamPlays > 0)
    .map((u) => `${u.short} ${derived.units[u.id].athletePlays}/${derived.units[u.id].teamPlays}`)
    .join('   ');
  if (unitBits) {
    text(ctx, unitBits, W - 100, heroY + 200, { size: 24, weight: 600, color: INK.dim, align: 'right' });
  }

  /* ---- Statistics ---- */
  const stats = headlineStats(derived);
  const gridTop = heroY + 300;

  if (stats.length === 0) {
    ctx.fillStyle = INK.panel;
    roundRect(ctx, 72, gridTop, W - 144, 150, 24);
    ctx.fill();
    text(ctx, 'Participation tracked — no individual statistics recorded', W / 2, gridTop + 88,
      { size: 25, weight: 500, color: INK.dim, align: 'center' });
  } else {
    const cols = 2;
    const cardW = (W - 144 - 24) / cols;
    const cardH = 148;
    stats.forEach((s, i) => {
      const cx = 72 + (i % cols) * (cardW + 24);
      const cy = gridTop + Math.floor(i / cols) * (cardH + 22);
      ctx.fillStyle = INK.panel;
      roundRect(ctx, cx, cy, cardW, cardH, 24);
      ctx.fill();
      ctx.strokeStyle = INK.line;
      ctx.lineWidth = 2;
      ctx.stroke();
      text(ctx, s.value, cx + 30, cy + 92, { size: 66, weight: 700 });
      const labelSize = fitText(ctx, s.label, cardW - 60, 22, 700, SANS);
      text(ctx, s.label, cx + 30, cy + 124, { size: labelSize, weight: 700, color: INK.faint, spacing: 2 });
    });
  }

  /* ---- Footer / attribution (§22) ---- */
  ctx.fillStyle = INK.line;
  ctx.fillRect(72, H - 168, W - 144, 2);

  text(ctx, 'Track your athlete with PlayingTime', 72, H - 108, { size: 27, weight: 600 });
  text(ctx, 'Powered by Venuewise  ·  playingtime.venuewise.net', 72, H - 68,
    { size: 22, weight: 500, color: INK.faint });

  const dateStr = new Date(`${String(game.date).slice(0, 10)}T12:00:00`);
  const dateLabel = Number.isNaN(dateStr.getTime())
    ? String(game.date)
    : dateStr.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  text(ctx, dateLabel.toUpperCase(), W - 72, H - 68, { size: 22, weight: 700, color: INK.faint, align: 'right', spacing: 2 });

  return canvas;
}
