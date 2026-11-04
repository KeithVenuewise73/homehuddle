<!-- Recovered/written 2026-11-04 on branch recovery/venuewise-production-2026-11. Status: PROPOSED — takes effect when this PR is approved and merged. -->

# AI development rules — Venuewise / HomeHuddle

These rules bind any AI session (Claude, ChatGPT, Copilot or other) working in this repository or against project `urwnbskrtoplgnkkxuvl`. They exist because production migrations and functions were, for months, written and applied by AI sessions with no copy in version control. The 2026-11-04 recovery shows the result: 118 applied migrations, most with no repository counterpart, and 22 deployed functions with none.

1. **Read-only by default.** An AI session may inspect, query (read-only), export source, write files on a branch and open PRs. It may not apply a migration, deploy a function, change a policy or grant, rotate a secret, alter a cron job, or touch customer data unless the CEO has approved that specific change in writing in the session, with the Level B package in front of them.
2. **Branch, never `main`.** All work lands on a branch named `<type>/<topic>` and arrives at `main` through a PR the CEO approves. No AI session merges.
3. **The repository is the ledger.** Any SQL or function the session applies (after approval) is committed to the branch **first**, with the same version stamp the platform will record, so repo and database never diverge again.
4. **No invented results.** A test "passed" only if the session ran it and shows the output. A migration "applied" only if the ledger row exists. A function "deployed" only if `DEPLOYED.json` reflects the new version. Reports label every claim VERIFIED / DOCUMENTED / NOT VERIFIED / ASSUMPTION.
5. **No secrets in text.** Tokens, keys, connection strings and customer PII never appear in a commit, PR, report, log or chat message. Secret *names* are fine.
6. **No outbound side effects.** Sending SMS/email, charging a card, creating a subscription, calling a provider's write API — never, even "to test".
7. **Ask once, plainly.** When a decision belongs to the CEO (trust, money, customers, deletion), the session presents the decision in one paragraph with the recommendation and stops. It does not ask the CEO to run commands.
8. **Leave the trail.** Every session ends with: the branch, the PR, what was verified and how, what is still unverified, and what needs approval — in `docs/operations/` or the PR body, not only in the chat.
9. **Policies above are versioned.** A session that needs an exception proposes a change to the relevant policy file in the same PR, with the reason.

Related: `docs/operations/migration-policy.md`, `docs/operations/edge-function-policy.md`, `docs/operations/deployment-policy.md`, `docs/architecture/schema-owners.md`.
