<!-- Recovered/written 2026-11-04 on branch recovery/venuewise-production-2026-11. Status: PROPOSED — takes effect when this PR is approved and merged. -->

# Production recovery — Venuewise / HomeHuddle (`urwnbskrtoplgnkkxuvl`)

How the deployed database schema and edge functions were recovered on 2026-11-04, how to verify them, and how to redo it.

## What was recovered

| Component | Count | Where | Verification |
| --- | --- | --- | --- |
| Applied migrations | 118 | `supabase/recovery/production-2026-11/migrations/` | MD5 of each row's `statements` recomputed in the database and compared to the local file (`MANIFEST.csv`): all 118 match |
| Edge functions (deployed source) | 22 | `supabase/recovery/production-2026-11/functions/<slug>/` | Each file's SHA-256 recorded in `SHA256SUMS`; `DEPLOYED.json` holds version, `verify_jwt`, entrypoint and timestamps as reported by the platform |
| Diff against the repository | — | `supabase/recovery/production-2026-11/migrations/REPO_DIFF.md`, `functions/REPO_DIFF.md` | Normalized text comparison; findings listed per file |

Original version stamps and names are preserved. Nothing was renumbered, reformatted or "fixed".

## How it was done (reproducible)

1. Read-only SQL against `supabase_migrations.schema_migrations`: `select version, name, statements` for all rows, exported as one base64 JSON document in 120,000-character chunks, reassembled locally and decoded into one `.sql` file per row (`/home/claude/recovery/unpack_ledger.py` at the time; the script is small and is reproduced in `scripts/recovery/` on this branch).
2. Independent check: `select version, md5(array_to_string(statements, E'\n'))` run again against the database and compared to the local MD5s.
3. Edge functions: the platform's "get edge function" API returned every deployed file's content verbatim; files were written byte-for-byte and hashed.
4. No write of any kind was issued to the project. No secret, token, connection string or customer row was exported. The only non-schema data exported is row **counts**, used in security findings.

## What this does and does not prove

- **Source recovered** — yes, for every migration and every function.
- **Source verified** — yes for migrations (MD5) and function files (SHA-256 against the platform's own copy). This proves the files match what the platform *stores*; it does not prove the *running* bundle (`ezbr_sha256` in `DEPLOYED.json`) was built from exactly these files, because the platform bundles on deploy.
- **Environment reproducible / deployment tested / production recovery validated** — **no**. Nobody has yet created an empty project, applied these 118 files in order and compared the resulting catalog to production. That is the next step and is proposed in `docs/operations/migration-policy.md` §4.

## How to restore from this archive (procedure, not yet rehearsed)

1. Create an empty Supabase project (or branch).
2. Apply `supabase/recovery/production-2026-11/migrations/*.sql` in filename order with `psql`, stopping on first error. Expect to hit ordering issues where an applied row depended on manual steps (extensions, `cron.schedule`, storage buckets) — record each one in this file.
3. Compare `pg_dump --schema-only` of the result against production (read-only) and list every difference.
4. Deploy functions from `supabase/recovery/production-2026-11/functions/` with the secrets listed in each `DEPLOYED.json` → `env_var_names` set in the new project (values come from the CEO's own password manager / provider consoles — they were never exported).
5. Only after 1–4 are green may this archive be called a tested backup.

## Where the live data is

Not here. This archive contains **schema and code only**. Customer rows live in the production project and are covered by Supabase's own daily backups (plan-dependent — confirm the retention window in the dashboard; it was not verified in this exercise).
