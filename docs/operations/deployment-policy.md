<!-- Recovered/written 2026-11-04 on branch recovery/venuewise-production-2026-11. Status: PROPOSED — takes effect when this PR is approved and merged. -->

# Deployment policy — Venuewise / HomeHuddle

Applies to: HomeHuddle (iOS/web), FacilityHuddle, GameTracker, public event pages (public_events / public_this_week / public_upcoming views).

## Environments

| Name | Supabase project | Purpose | Who deploys |
| --- | --- | --- | --- |
| production | `urwnbskrtoplgnkkxuvl` | Live customers / live operations | CI with CEO approval only |
| preview | a Supabase branch of `urwnbskrtoplgnkkxuvl` (or an empty project) | Rehearsing migrations and function deploys; running the restore drill | Engineer, no approval |
| local | Supabase CLI local stack | Development and tests | Engineer |

There is no shared "staging" project today and none should be created by hand; a Supabase branch is the preview environment.

## The rule

Nothing reaches production except through a pull request into `main` that (a) passed CI (none on `main`), (b) was approved by the CEO in GitHub, and (c) was deployed by a workflow with a required-reviewer environment gate. The CEO's approval is the only manual step, and it is a click in GitHub or the Development Control Center — never a command.

## Levels of change

| Level | Examples | Who |
| --- | --- | --- |
| A — safe | docs, tests, recovery archives, new branches, PRs | engineer, no approval |
| B — reversible production change | RLS policies, grants, function redeploy, cron pause/resume, secrets rotation, migrations | engineer prepares package; CEO approves; CI applies |
| C — irreversible or commercial | deleting data, merging to `main`, customer migration, billing changes, outbound messaging | CEO decides case by case; never executed by an AI session |

A Level B package states: exact change, reason, current defect, affected apps, expected behaviour after, backup, validation test, rollback, risk. Packages prepared on 2026-11-04 are under `security/stage0/`.

## Rollback

Forward only. Every production change ships with the forward migration or the previous function bundle that undoes it, written **before** the change is applied.

## Observability after a deploy

The approver sees, in plain English: what changed, the validation query result, and the first error (if any) in the function or Postgres logs for the following 15 minutes. If that view does not exist yet, the deploy is not done — building it is part of the change.
