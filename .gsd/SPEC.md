# Mobile and web alignment

Status: FINALIZED

Audit mobile `d749c50` against web `940a2f6` and inspect deployed contracts read-only. Inventory every discovered feature, distinguishing shared intent, platform differences, missing features, and defects in either client. Maintain evidence, severity, ownership, dependencies, acceptance tests, and completed/pending/blocked status. Keep sensitive security evidence private.

Implement confirmed mobile defects in independent branches and draft PRs. Initial acceptance batches: restore registration/recovery/email-change validation; preserve queue state across online/offline transitions and deletions; replace reception's client-side queue allocation with the existing authenticated triage transaction. Expand the backlog from the inventory and progress independent fixes while backend work is blocked.

Submission alignment must cover immediate uploads, templates, assessment/test selection, retry/idempotency and offline replay. A server-owned authenticated submission contract is a backend dependency: do not embed privileged credentials, weaken RLS, invent a deployed endpoint, or deploy backend changes. Prepare contributions only for review.

For each implementation, state affected paths and observable acceptance before editing. Add focused regressions, run Flutter analysis/tests and applicable build/UI checks, retain private receipts with tested revisions, and report unavailable gates as blockers. Preserve existing checkouts and production data. Production inspection is read-only; production fixtures require backend-owner authorization.
