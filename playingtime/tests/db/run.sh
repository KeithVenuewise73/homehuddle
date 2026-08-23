#!/usr/bin/env bash
# Apply and verify the PlayingTime schema against a throwaway Postgres 16.
# Nothing here touches a real Supabase project.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DB="${PT_DB:-postgresql://postgres@/tmp:5433/playingtime_verify}"
HOST="${PT_HOST:-/tmp}"; PORT="${PT_PORT:-5433}"

psql -h "$HOST" -p "$PORT" -U postgres -qtAc "drop database if exists playingtime_verify;"
psql -h "$HOST" -p "$PORT" -U postgres -qtAc "create database playingtime_verify;"
run() { psql -h "$HOST" -p "$PORT" -U postgres -d playingtime_verify -v ON_ERROR_STOP=1 -q -f "$1"; }
run "$HERE/harness.sql"
run "$HERE/../../db/0001_playingtime.sql"
psql -h "$HOST" -p "$PORT" -U postgres -d playingtime_verify -v ON_ERROR_STOP=1 -q -f "$HERE/verify.sql" 2>&1 | sed 's/^NOTICE:  //'
run "$HERE/../../db/0001_playingtime_down.sql"
psql -h "$HOST" -p "$PORT" -U postgres -d playingtime_verify -qtAc \
  "select case when count(*) = 0 then '  ok   down-migration removed the schema cleanly' else 'FAILED: schema survived' end from pg_namespace where nspname='playingtime';"
psql -h "$HOST" -p "$PORT" -U postgres -qtAc "drop database if exists playingtime_verify;" >/dev/null
echo "PASSED — schema applies, enforces isolation, and reverses cleanly"
