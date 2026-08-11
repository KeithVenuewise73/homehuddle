# Local staging harness (Sprint 02)

Proves migrations `0001–0006` and the billing/entitlement/founder/deletion logic
against a **real, ephemeral PostgreSQL** — synthetic data only, nothing touches
the hosted Supabase project.

```bash
bash tests/staging/run.sh
```

What it does:
1. Spins up a throwaway Postgres cluster.
2. `00_base_stub.sql` recreates the **pre-migration** Supabase base tables
   (families, family_members, feeds, subscriptions, push_subscriptions) plus the
   auth helper functions (`current_person_id`, `current_family_ids`,
   `current_family_emails`, `is_admin`) and roles (`anon/authenticated/service_role`),
   so the migrations apply exactly as on Supabase.
3. Applies `0001–0006`.
4. `10_test_matrix.sql` asserts:
   - **Source coexistence** — Stripe + Apple purchase rows coexist; canonical
     `family_product_entitlements` stays correct as each source expires.
   - **Founder lifecycle** — 100-cap, #101 refused, reservation release frees a
     slot, a *granted* slot is permanent (never re-pooled).
   - **Deletion** — non-owner blocked from whole-family delete but can self-remove;
     owner schedule + cancel; hard delete anonymizes/purges and is idempotent.
   - **Admin metrics** — `admin_dashboard_metrics()` returns verified aggregates
     and denies non-admins.
5. A **founder concurrency race**: 8 parallel reservations compete for the last
   slot; exactly one wins (no oversell).

Note: this harness validates SQL/business logic. RLS *enforcement* and Edge
Functions are validated separately (policy inspection on the live project +
Deno runtime); the stub runs as superuser so RLS is not exercised here.
