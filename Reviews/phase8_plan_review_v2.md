# Phase 8 Plan Review (v2) — Staff Mode (Read-Mostly)

> **Gate B — Plan Review (v2).** Reviewer: Claude (per `MASTER_CONTEXT.md`
> section 5).
> Subject: Revised Phase 8 Implementation Plan (`1781574191228_implementation_plan.md`).
> This file supersedes `phase8_plan_review.md`.

## Verdict: APPROVED — proceed to Gate C (Build)

The agent addressed all five required changes from the v1 review plus the
minor observation about specialist Realtime. The revised plan is well-structured
and ready for build. Brief notes follow — none are blockers.

## How each required change was resolved

**1. Security architecture section** — RESOLVED. The new opening section
explicitly states the four-point security model: RLS as canonical boundary,
client filters as UX/perf, role checks as routing UX only, and the bypass
fail-safe behavior. This is the language the defense will need; it now lives in
the plan and will flow into the build.

**2. Consent-storage migration read priority + back-fill** — RESOLVED. The
"User Review Required" block specifies:
- Read priority: database first (`profiles.accepted_privacy_at`), fallback to
  metadata only if DB value is null.
- One-time back-fill: if metadata has the consent but DB is null, write the
  metadata timestamp to the DB.
- New writes go exclusively to the DB column.

This is the cleanest possible migration rule. Existing Phases 2-6 test users
will not be bounced back through the consent gate on next login.

**3. State-change verification chain** — RESOLVED, and well-formatted. The
four-row table in the verification plan is exactly what was asked for: each
state change has its RLS policy citation (with the exact policy name from
`schema.sql`), its test file + test name, and the database SELECT that confirms
the row landed in the expected state. This is the verification standard
Phase 5/7 established, applied cleanly to Phase 8's state changes.

**4. Department filter sourced from `profiles.department`** — RESOLVED. The
department_provider section now explicitly says: *"Security Guard: Read the
department filter directly from the authenticated user's `profiles.department`.
Do not accept UI inputs or expose setters that would allow changing this
parameter."* That closes the gap.

**5. Cross-role data-leakage tests with client bypass** — RESOLVED. Three
explicit tests added:
- Laboratory user explicit imaging filter on `patient_queue` -> expect zero
  rows
- Laboratory user explicit `patient_id` query on imaging
  `department_records` -> expect empty result
- Laboratory user attempts UPDATE on imaging `department_records` row ->
  expect failure / no rows updated

The third test (the UPDATE attempt) is a stronger probe than the v1 review
asked for. Credit for adding it — it covers the write side of cross-department
isolation, not just the read side.

**6. Specialist screen Realtime acknowledged** — RESOLVED. The plan now has
the one sentence: *"Intentional Pull-Based Design: The Specialist screen does
NOT subscribe to Realtime. Since this role is read-only and historical-data
focused, a manual pull-to-refresh on screen load is sufficient."* A reader
won't think it was forgotten.

## Three small notes for the build (not blockers)

**Note 1 — receptionist queue listens to BOTH `patient_queue` AND `documents`
realtime channels.** The plan mentions two Supabase Realtime subscriptions in
the reception_provider. Make sure they are managed independently — separate
channel handles, separate dispose() calls, separate error handlers. A common
bug pattern is letting one subscription's error tear down the other. Worth
explicit handling.

**Note 2 — the back-fill should be best-effort, not blocking.** When the
asynchronous one-time back-fill runs, it should not block the login flow or
display an error to the user if it fails. The user already has consent (it's
just in the wrong place); the next login attempt can re-try. Make sure the
back-fill is wrapped in a try/catch that logs but doesn't surface.

**Note 3 — the cross-role tests should run against a real Supabase test
project, not mocks.** The plan says *"Instantiate Supabase client mocked with
laboratory department staff JWT."* The verification is much stronger if these
tests run against the actual `onzeyejlfydvvbkejvwf` project with real test
users in the laboratory and imaging roles. A mocked JWT proves the test code
works; only a real JWT against real RLS proves the database rejects. If the
agent uses Supabase test fixtures + a real JWT for these tests, the defense
evidence is significantly stronger.

This isn't blocking the build — but worth raising for the walkthrough at Gate
D, where the reviewer will ask: *"are these tests hitting real RLS, or are
they mocking RLS responses?"*

## What I'll check at Gate D

- The four state-change verification rows actually run with real database
  reads in their tests, not mocked SELECT responses.
- The three cross-role tests genuinely demonstrate RLS denial — preferably
  with a brief paste of the database response showing zero rows (or the
  Postgres error code 42501 / 0 rows for UPDATE).
- The consent back-fill is verifiable: register a test user with consent in
  metadata only, log in, then `SELECT accepted_privacy_at FROM profiles WHERE
  id = ...` should show the timestamp got written.
- Three emulator screenshots (or one per role): receptionist dashboard with
  queue + documents; department home with department-scoped queue; specialist
  search results with patient timeline. These become defense materials.
- The Realtime subscriptions actually fire — receptionist screen visible, then
  from SQL editor `UPDATE` a queue row's status, watch the screen update live.
  Worth a video/screen recording for the defense if possible.

## Answer recap to the agent's open question

Document rejection UX with chip + custom field + 200-char limit is approved.
Chip's label writes verbatim to the database — confirmed.

## Status & next gate

- **Gate B for Phase 8: APPROVED.** Proceed to **Gate C (Build).** No re-review
  at Gate B needed.
- When the build is complete, send the walkthrough + test results + the
  verification evidence above. Gate D follows.

A small win to acknowledge: the v2 revision was thorough and addressed every
item without negotiating around them. The state-change table format is
particularly clean — recommend that table format become the template for
future security-claim verification across remaining work.
