# Phase 9 Plan Review (v2) — Testing, Hardening & Release

> **Gate B — Plan Review (v2).** Reviewer: Claude (per `MASTER_CONTEXT.md`
> section 5).
> Subject: Revised Phase 9 Implementation Plan (`1782007947098_implementation_plan.md`).
> This file supersedes `phase9_plan_review.md`.

## Verdict: APPROVED — proceed to Gate C (Build)

The agent addressed all seven required changes from the v1 review cleanly. The
revised plan is comprehensive and ready for build. Three small notes follow —
none are blockers, but worth keeping in mind during execution.

## How each required change was resolved

**1. ISO 25010 Usability factual correction** — RESOLVED. The plan now
correctly references Inter typography and the light cream + forest-green
palette. No more references to Outfit or dark theme. ✓

**2. ISO 25010 methodology specified** — RESOLVED. The plan now states:
- Self-scored by the team with clinic staff feedback
- Scored rubric table delivered in `Reviews/walkthrough.md`
- Four load scenarios from Phase 6 review explicitly listed
- Real device requirement called out in a dedicated callout for Scenarios 2
  and 4 (Android 8.0, 4GB RAM, quad-core)

The "real device requirement" callout is well-placed and unambiguous. ✓

**3. APK security pass methodology** — RESOLVED, and cleanly. The plan
specifies:
- The exact decompile tool (`apktool`) with the `--force` flag
- All four grep commands (`AIzaSy`, `GEMINI`, `service_role`, `eyJ`)
- Pass criteria (first three zero matches; `eyJ` matches checked against the
  anon key)
- Evidence format (raw command logs in Gate D walkthrough)
- A pre-build sanity gate (`flutter analyze` + `flutter test`) before
  compiling the release APK

The pre-build sanity gate is good practice — it catches issues before the
expensive build step. ✓

**4. Mobile/web integration participation plan** — RESOLVED. The plan covers:
- Shared project (`onzeyejlfydvvbkejvwf`) configuration
- Two-operator scenario (one web, one mobile)
- Single-operator fallback (mobile team deploys web app locally, signs into
  both clients)

The fallback is the realistic option given the timeline and is well-defined. ✓

**5. Defense Materials Checklist** — RESOLVED. Three items explicitly
captured:
- Phase 7 admin-block dialog screenshot
- Phase 8 consent back-fill SQL evidence
- Phase 8 three staff dashboard screenshots ✓

**6. Release build expanded** — RESOLVED. Covers keystore signing, version
stamping (`1.0.0+1`), and distribution (sideload + shared folder). The
academic context is acknowledged appropriately. ✓

**7. Documentation cleanup section** — RESOLVED. All four target files listed
with concrete acceptance criteria. ✓

## Three small notes for the build (not blockers)

**Note 1 — the documentation cleanup mentions `MASTER_CONTEXT2.md`.** The
Phase 7 walkthrough explicitly resolved the duplicate by consolidating to a
single canonical `MASTER_CONTEXT.md`. The Phase 9 plan's wording
*"`MASTER_CONTEXT.md` / `MASTER_CONTEXT2.md`"* implies both still exist. If
they do, the consolidation didn't actually happen and needs to be redone. If
`MASTER_CONTEXT2.md` is no longer a real file, just update the plan to drop the
reference. Worth verifying in the build phase.

**Note 2 — Scenario 1 (100 concurrent chat Edge Function users) needs a
simulation method specified at Gate D.** The plan says "simulated" but doesn't
say how. Options to disclose at Gate D:
- A simple script that fires 100 parallel `curl` requests to the Edge Function
  endpoint
- A load-testing tool like `k6` or `artillery`
- Manually staggered requests from a single dev machine

Any of these is acceptable; the plan just needs to record which one was used
when the results are reported. A "we simulated 100 users" claim without a
method is weak evidence.

**Note 3 — the schema proposals adoption status (item 6.3 of Documentation
Cleanup) depends on the web team responding.** This has been an open
coordination item since Phase 5. If by the time of the Phase 9 walkthrough the
web team has not provided per-proposal adoption status, the documentation
should at least record:
- The date the proposals were sent (Phase 5 walkthrough section 6, ~2026-06-05)
- The dates of any follow-up requests
- The current best-known status of each proposal (e.g., "match_rag_documents
  RPC is not in the current `schema.sql` snapshot dated 2026-06-10, suggesting
  not yet adopted")

That's defensible. "Web team has not responded yet" is also defensible if
true. The wrong move is leaving the proposal-adoption section blank.

## What I'll check at Gate D

- All 11 test files run green and the actual logs are pasted
- The four ISO 25010 load scenarios with real performance numbers, with
  Scenarios 2 and 4 noting the device specs they ran on
- The full grep output (or "no matches found") for the four APK security
  checks
- The mobile/web integration scenarios with either screenshots or a brief
  recording showing the live sync
- The three defense materials (admin-block dialog, consent back-fill SQL,
  three staff dashboard screenshots)
- The release APK exists, signed, with the documented version
- All four documentation files updated, including the `schema_proposals.md`
  adoption status (per Note 3)

## Status & next gate

- **Gate B for Phase 9: APPROVED.** Proceed to **Gate C (Build).** No
  re-review at Gate B needed.
- When the build is complete, send the walkthrough + all evidence above. Gate D
  follows.

This is the final phase. The walkthrough at Gate D will determine defense
readiness. The plan is now well-positioned to deliver that.

A small win to acknowledge: the v2 revision was thorough and addressed every
item — including the small observations from the v1 review's "Two
observations" section. That kind of completeness is the right rhythm for the
final phase.

Build away. The defense materials will follow naturally from the verification
work.
