#!/usr/bin/env bash
# ============================================================================
# HomeHuddle — local staging harness (Sprint 02)
# Stands up an EPHEMERAL PostgreSQL cluster, stubs the Supabase base schema +
# auth helper functions, applies migrations 0001-0006, and runs the synthetic
# test matrix + a founder concurrency race. Synthetic data only; nothing touches
# the hosted Supabase project. Real Postgres engine → real proof of the SQL.
#
# Usage:  bash tests/staging/run.sh
# Requires: postgresql-16 client+server installed; run from repo root; needs an
# unprivileged OS user to own the server (uses `postgres` via runuser if root).
# ============================================================================
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="${HH_STAGING_DIR:-/tmp/hh_staging}"
export PATH="/usr/lib/postgresql/16/bin:$PATH"

RUN() { if [ "$(id -u)" = "0" ]; then runuser -u postgres -- "$@"; else "$@"; fi }

rm -rf "$BASE"; mkdir -p "$BASE/pgdata" "$BASE/sock" "$BASE/sql"
cp "$REPO"/supabase/migrations/20260810_000*_*.sql "$BASE/sql/"
cp "$REPO"/tests/staging/00_base_stub.sql "$REPO"/tests/staging/10_test_matrix.sql "$REPO"/tests/staging/20_rls_matrix.sql "$BASE/sql/"
if [ "$(id -u)" = "0" ]; then chown -R postgres:postgres "$BASE"; chmod -R 755 "$BASE"; fi

RUN initdb -D "$BASE/pgdata" -U postgres --auth=trust >/dev/null
RUN pg_ctl -D "$BASE/pgdata" -o "-k $BASE/sock -c listen_addresses=''" -l "$BASE/pg.log" -w start >/dev/null
RUN createdb -h "$BASE/sock" -U postgres staging
PSQL() { RUN psql -h "$BASE/sock" -U postgres -d staging -v ON_ERROR_STOP=1 "$@"; }

echo "== applying base stub + migrations 0001-0006 =="
PSQL -q -f "$BASE/sql/00_base_stub.sql" >/dev/null
for m in 0001 0002 0003 0004 0005 0006; do
  PSQL -q -f "$(ls "$BASE/sql/"*_${m}_*.sql)" >/dev/null && echo "  applied $m"
done

echo "== logic + deletion + admin matrix =="
PSQL -f "$BASE/sql/10_test_matrix.sql" 2>&1 | grep -E "NOTICE|====" || true

echo "== RLS role matrix (real anon/authenticated enforcement) =="
PSQL -f "$BASE/sql/20_rls_matrix.sql" 2>&1 | grep -E "NOTICE|====|forge" || true

echo "== founder concurrency race (8-way for the last slot) =="
PSQL -q -c "truncate public.founder_grants;" >/dev/null
PSQL -q -c "do \$\$ declare i int; fid uuid; begin
  for i in 1..99 loop fid:=('a1a1a1a1-0000-4000-b000-'||lpad(i::text,12,'0'))::uuid;
    insert into families(id,family_name,email,phone,pin,status) values(fid,'g','g'||i||'@d.invalid','p','0','active') on conflict do nothing;
    insert into founder_grants(family_id,product,state,granted_at) values(fid,'homehuddle','granted',now()); end loop;
  for i in 1..8 loop fid:=('c0c0c0c0-0000-4000-b000-'||lpad(i::text,12,'0'))::uuid;
    insert into families(id,family_name,email,phone,pin,status) values(fid,'c','c'||i||'@d.invalid','p','0','active') on conflict do nothing; end loop;
end \$\$;" >/dev/null
rm -f "$BASE"/race_*.out
for i in $(seq 1 8); do
  fid="c0c0c0c0-0000-4000-b000-$(printf '%012d' "$i")"
  ( PSQL -At -c "select reserve_founder_slot('$fid','homehuddle','apple','r$i');" >"$BASE/race_$i.out" 2>&1 ) &
done
wait
WINS=$(grep -hc '^t' "$BASE"/race_*.out | awk '{s+=$1} END{print s}')
echo "  winners=$WINS (must be 1); active holds=$(PSQL -At -c "select count(*) from founder_grants where state in ('reserved','granted');")"
[ "$WINS" = "1" ] && echo "  CONCURRENCY PASS" || { echo "  CONCURRENCY FAIL"; exit 1; }

echo "== teardown =="
RUN pg_ctl -D "$BASE/pgdata" -w stop >/dev/null; rm -rf "$BASE"
echo "DONE"
