#!/usr/bin/env bash
# ============================================================================
# HomeHuddle billing invariant guard (static).
# Verifies the canonical Stripe/Founder/trial rules are present in the billing
# code-paths that the SQL harness cannot exercise (no live Stripe/Apple keys).
# Exits non-zero on any violation. Safe, offline, no paid infra.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."

CO=supabase/functions/stripe-checkout/index.ts
WH=supabase/functions/stripe-webhook/index.ts
CAL=homehuddle/calendar.html
MIG=supabase/migrations/20260810_0001_product_aware_entitlements.sql
fail=0
pass(){ echo "  OK  $1"; }
bad(){ echo "  FAIL $1"; fail=1; }

echo "==================== BILLING INVARIANTS ===================="

# 1. Canonical lookup keys present; obsolete key absent (active code).
grep -q "founding_member_monthly" "$CO" && pass "checkout uses founding_member_monthly" || bad "founding lookup key missing"
grep -q "standard_monthly" "$CO" && pass "checkout uses standard_monthly" || bad "standard lookup key missing"
! grep -q "early_adopter_monthly" "$CO" && pass "no early_adopter_monthly in checkout" || bad "obsolete early_adopter_monthly present"

# 2. Canonical CEO machine-copied price ids (l/O). The erroneous 1/0 spelling
#    must be absent from ALL active billing code + the migration.
grep -q "price_1TliAoPqdDGv5YmHOF88NED9" "$CO" && pass "founding price id canonical l/O (checkout)" || bad "founding price id not canonical (checkout)"
grep -q "price_1TliApPqdDGv5YmHcxaaDG1J" "$CO" && pass "standard price id canonical l/O (checkout)" || bad "standard price id not canonical (checkout)"
grep -q "price_1TliAoPqdDGv5YmHOF88NED9" "$WH" && pass "founding price id canonical l/O (webhook)" || bad "founding price id not canonical (webhook)"
grep -q "price_1TliAoPqdDGv5YmHOF88NED9" "$MIG" && pass "founding backfill canonical l/O (migration)" || bad "founding backfill not canonical (migration)"
! grep -rq "price_1T1iAoPqdDGv5YmH0F88NED9" "$CO" "$WH" "$MIG" && ! grep -rq "price_1T1iApPqdDGv5YmHcxaaDG1J" "$CO" "$WH" "$MIG" && pass "erroneous 1/0 ids absent from active code + migration" || bad "erroneous 1/0 id still present"

# 3. Trial policy: Standard 14-day, Founding none.
grep -Eq "if \(!isFounding\) subData\['subscription_data\[trial_period_days\]'\] = TRIAL_DAYS;" "$CO" && pass "trial gated to !isFounding (Standard only)" || bad "trial not gated to Standard"
grep -Eq "trial_days: isFounding \? 0 : TRIAL_DAYS" "$CO" && pass "response reports 0 trial days for founding" || bad "response trial_days not conditional"

# 4. Founder eligibility from the shared pool, NOT price default / client input.
grep -q "founder_slots_remaining" "$CO" && pass "checkout eligibility from founder_slots_remaining" || bad "eligibility not pool-derived"
grep -Eq "const isFounding = foundingAvailable;" "$CO" && pass "isFounding derived server-side from pool" || bad "isFounding not server-side"

# 5. Webhook founder detection prefers pool-derived metadata over price-id equality.
grep -q "sub.metadata?.founding === 'true'" "$WH" && pass "webhook prefers subscription metadata flag" || bad "webhook does not prefer metadata"

# 6. Paywall: no false Founding trial claim; cap is 100 not 150.
! grep -q "14 days free · limited" "$CAL" && pass "founding card no longer claims 14-day trial" || bad "founding card still claims trial"
! grep -Eq "first 150|of 150" "$CAL" && pass "no 150-cap text in paywall" || bad "150-cap text present in paywall"

echo "==========================================================="
if [ "$fail" -eq 0 ]; then echo "ALL BILLING INVARIANTS PASSED"; else echo "BILLING INVARIANTS FAILED"; exit 1; fi
