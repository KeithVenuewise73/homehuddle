/* Run every PlayingTime suite and report one result.
 * Usage: node playingtime/tests/run-all.mjs */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const results = [];

function run(name, cmd, args, opts = {}) {
  process.stdout.write(`\n${'═'.repeat(64)}\n  ${name}\n${'═'.repeat(64)}\n`);
  const r = spawnSync(cmd, args, { stdio: 'inherit', cwd: REPO, ...opts });
  results.push({ name, code: r.status, skipped: false });
  return r.status;
}

run('Unit tests — engine, store, catalog', 'node', ['--test', join(HERE, 'engine.test.js'), join(HERE, 'store.test.js'), join(HERE, 'catalog.test.js')]);
run('Acceptance — the V1 list, in a real browser', 'node', [join(HERE, 'acceptance.mjs')]);

/* The schema suite needs a Postgres to apply to. Missing one is a skip with a
 * reason, never a silent pass. */
const pgUp = spawnSync('psql', ['-h', process.env.PT_HOST || '/tmp', '-p', process.env.PT_PORT || '5433',
  '-U', 'postgres', '-qtAc', 'select 1'], { stdio: 'ignore' }).status === 0;
if (pgUp && existsSync(join(HERE, 'db', 'run.sh'))) {
  run('Schema — applies, isolates, reverses', 'bash', [join(HERE, 'db', 'run.sh')]);
} else {
  results.push({ name: 'Schema — applies, isolates, reverses', code: 0, skipped: true });
}

console.log(`\n${'═'.repeat(64)}`);
let failed = 0;
for (const r of results) {
  if (r.skipped) { console.log(`  SKIP  ${r.name} — no Postgres on ${process.env.PT_HOST || '/tmp'}:${process.env.PT_PORT || 5433}`); continue; }
  if (r.code === 0) console.log(`  PASS  ${r.name}`);
  else { console.log(`  FAIL  ${r.name}`); failed++; }
}
console.log('═'.repeat(64));
process.exit(failed ? 1 : 0);
