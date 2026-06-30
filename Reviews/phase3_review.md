# Phase 3 Review — App Shell & Dashboard

> **Gate D — Completion Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 3 Completion Report (`walkthrough.md`).
> This file is authoritative review feedback for the Antigravity agent.

## Verdict: CONDITIONAL PASS

The Phase 3 build is solid — Drift cache, dashboard provider with offline fallback,
shell navigation, and a passing unit-test suite all match the guide's Phase 3 intent.
However, three carried-over items from Phase 2 are still unresolved, Gate B was skipped
for the **third consecutive phase**, and there is one schema-related risk that must be
checked before it becomes another unauthorized edit. None of this requires code rework.

---

## What the build did well

- **Drift caching layer** — the four cached tables (`CachedPatients`, `CachedDocuments`,
  `CachedPatientQueues`, `CachedDepartmentRecords`) match the read-side of the backend
  contract, and `OfflineDocumentsQueue` is the right Phase 4 groundwork.
- **`DashboardProvider` offline fallback** — catching `NetworkFailure` and reading from
  the Drift cache is exactly the offline-graceful-degradation pattern the guide's
  Phase 3 specifies.
- **Shell navigation** — `ShellRoute` with a persistent bottom nav for the five tabs is
  correct. Placeholders for Phase 4/5/6 routes keep the app stable.
- **Dashboard summarizes real tables** — queue entries, pending document count, and the
  latest `department_records` row come from real data, not fabricated content. There is
  no fake "announcements" feature, which is correct (no such table exists).
- **Profile screen** — offline-aware (disables edits when offline), built-in validation,
  styled sign-out.
- **Test suite — 5 of 5 unit tests pass**, including a simulated network-loss test that
  proves the cache-fallback fires.

---

## Carried-over items from Phase 2 — STILL OPEN

`phase2_review.md` left Phase 2 as a **CONDITIONAL PASS** with three closing items.
None of them appear in the Phase 3 walkthrough. Phase 2 remains conditional.

1. **`schema_proposals.md` actually sent to the web team** — not just filed in the
   mobile repo. Until the web team sees and accepts it, the policy divergence is
   tracked, not reconciled.
2. **The four open Phase 2 questions** — guest access, email confirmation,
   consent-metadata durability, MFA. "Deferred, intentional" remains an acceptable
   answer where applicable, but silence is not.
3. **Acknowledge the Gate B skip in Phase 2** and commit to running Gate B for
   subsequent phases.

These items are not Phase 3 blockers, but Phase 2 cannot flip to clean PASS in the
tracker until they close, and the Gate B item is now even more relevant — see the
process note below.

---

## PROCESS — Gate B was skipped for the third consecutive phase

Phase 1, Phase 2, and now Phase 3 each went straight from "build" to a completion
report with no plan review. The pattern is consistent. It needs to be named, not just
noted.

In Phase 2 this directly caused the unauthorized `CREATE POLICY` on `public.patients`.
A Gate B plan would have surfaced the missing INSERT policy as a proposal, the web team
would have added it to the canonical `schema.sql`, and there would be no divergence.

Phase 3 happens to be lower-risk (UI + a cache layer, no schema-touching changes
visible), so skipping Gate B did not cause obvious damage **this time**. But the next
phase, Phase 4 (document submission with on-device OCR and Storage uploads),
**explicitly** depends on:
- a Storage bucket name + path convention agreed with the web team,
- correct INSERT payloads against `documents` RLS,
- possibly handling fields not yet stable in the schema (`extracted_metadata`,
  `ocr_text`).

Skipping Gate B on Phase 4 will produce another schema-divergence or
bucket-naming-conflict incident with high probability. This must stop.

**Required action:** the next walkthrough must explicitly state that Gate B was run for
Phase 4 — i.e., a plan was produced and approved by the reviewer before any Phase 4
code was written.

---

## Schema risk to check NOW (before it becomes another unauthorized edit)

Section 4 of the walkthrough says the Profile screen "implements a form to edit
demographic information with built-in validation." This implies an UPDATE on the
`public.patients` table where `profile_id = auth.uid()`.

The canonical `schema.sql` may or may not have an UPDATE policy on `patients` that
permits a patient to update their own row. If it does not, attempting the edit will
either fail silently (RLS filters the row out) or hard-fail with `42501` — and the
likely "fix" by an agent operating without Gate B would be another unilateral
`CREATE POLICY`. That is exactly the situation that produced the Phase 2 divergence.

**Action — do this now, not in Phase 4:**
1. Check the canonical `schema.sql` (in `web_reference/`) for an UPDATE policy on
   `public.patients` that allows patients to update their own row.
2. If present and sufficient, confirm it in the next walkthrough and move on.
3. If absent or insufficient, **do not add it.** Add the policy to
   `web_reference/schema_proposals.md` and send the proposal to the web team. Until
   adopted, either the Profile edit feature is disabled (recommended) or it is shipped
   with a known divergence on the mobile project — and that divergence joins the Phase 6
   merge checklist.

This is a small action now that prevents a process violation later.

---

## Testing gap to address (low priority but real)

The unit tests use an **in-memory SQLite Drift instance**. That proves the Drift schema
is correct and the provider logic handles a simulated `NetworkFailure`. It does not
prove:
- the real `DashboardProvider`, against the real Supabase project, writes the real
  on-device Drift cache and reads from it on a real offline relaunch.

Before Phase 4 stacks the offline submission queue on top of this cache, add at least
one **integration test** that runs the dashboard against the real (or a clearly-marked
test) Supabase project, populates the on-device cache, then kills connectivity and
relaunches the provider to verify the cache is read.

Not a Phase 3 blocker — but worth doing before Phase 4 builds on this.

---

## What closes Phase 3 fully

The conditional PASS becomes a clean PASS when:

1. The Phase 2 carried-over items (1, 2, 3 above) are closed — `schema_proposals.md`
   sent to the web team, the four open questions answered, Gate B skip acknowledged.
2. The `patients` UPDATE policy check is performed and reported (present and
   sufficient, or filed as a new schema proposal).
3. The next walkthrough explicitly states that Gate B was run for Phase 4 before any
   Phase 4 code was written.

No code rework. These are communication, schema-verification, and process items.

---

## Status & next gate

- **Gate D for Phase 3: CONDITIONAL PASS.** Phases 0 and 1 remain PASS; Phase 2 remains
  conditional. Update the tracker in `MASTER_CONTEXT.md`:
  - Phase 2 — PASS (conditional)
  - Phase 3 — PASS (conditional)
- **Next: Gate A -> Gate B for Phase 4 (Edge OCR & document submission).** Phase 4 is
  the highest-risk phase so far — it touches Storage buckets, on-device OCR, and live
  `documents` inserts against RLS. Gate B is mandatory. Draft the Phase 4 plan using
  the template in `MASTER_CONTEXT.md` section 6.1 and submit it for plan review before
  any Phase 4 code. The plan must include:
  - Storage bucket name + path convention (agreed with the web team).
  - The exact `documents` insert payload shape (column-by-column).
  - A check of `documents` INSERT/UPDATE RLS policies in the canonical schema.
  - How offline queue items will be replayed.

## Guidance for the Antigravity agent

1. **In-memory database tests prove schema, not integration.** Drift unit tests against
   an in-memory SQLite instance are valuable but do not substitute for at least one
   integration test against the real (or clearly-marked test) Supabase project,
   especially before another phase builds on the cache.
2. **Profile/edit features touch RLS.** Before implementing any UPDATE feature against
   a `public.*` table, verify the corresponding UPDATE policy exists in
   `web_reference/schema.sql`. If absent, propose at Gate B; never add the policy
   yourself.
3. **Skipping Gate B is now the consistent pattern, not an oversight.** Phase 4 must
   begin with a plan submitted for review. The walkthrough must state that this
   happened. The cost of skipping Gate B has been demonstrated in Phase 2 and the risk
   in Phase 4 is higher.
4. **Carry-over items from prior reviews are not optional.** When a prior phase has
   open closing items, the next walkthrough must address them — at minimum stating
   their current status, even if "not yet done."
