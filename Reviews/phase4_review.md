# Phase 4 Review — Edge OCR & Document Submission

> **Gate D — Completion Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 4 Completion Report (`1780376244301_walkthrough.md`).
> This file is authoritative review feedback for the Antigravity agent.

## Verdict: CONDITIONAL PASS

The strongest build to date. Five of seven plan-review items are fully resolved; two
are partially handled and one is silent. The remaining gaps are disclosure and
verification-shape items, not code rework.

---

## Plan-review item status (from `phase4_plan_review.md`)

### Change 1 — Storage RLS as a schema proposal: PARTIAL
The proposal is now filed in `schema_proposals.md`. Good. But the walkthrough does not
show that the **corrected policy shape** from the Gate B review actually landed in the
proposal:
- Storage policies must be written against `storage.objects`, not by role string.
- Path check must use `storage.foldername(name)[1] = auth.uid()::text`.
- Staff-view policy must call the existing `get_auth_user_role()` helper, not
  enumerate role names.

**Action:** paste the actual SQL currently in `schema_proposals.md` for the Storage
policies in the next status update so the technically correct shape is verifiable.

### Change 2 — Collision-free file names: PASS
RFC 4122 v4 UUIDs via the pure-Dart `uuid_generator.dart`, format
`<auth.uid()>/<uuid>_<original_name>.<ext>`, with `__test__/` prefix for test runs.
Addresses both Change 2 and Note B in one stroke.

### Change 3 — Concrete OCR pre-screen rules: PASS
Date regex, `"Dr."` / `"M.D."` token check, patient-name cross-reference against the
logged-in `patients` row, and an explicit diagnostic-keyword set (`laboratory`,
`referral`, `clinic`, `cbc`, `xray`, `ultrasound`, `ecg`). Stored in
`extracted_metadata` for audit. Three of the five tests assert on these exact rules.
This is the testable, defensible version that was missing in the plan.

### Change 4 — `documents` insert payload spelled out: PARTIAL
Most columns are listed and correct. But the **`extracted_metadata` jsonb shape itself
is not shown** — the walkthrough says "jsonb containing matching audit results," which
is vague again.

The Gate B review specifically asked for keys like `matched_fields`, `missing_fields`,
`keyword_set_version`, `ocr_engine_version`. The web app will read this jsonb. Without
`keyword_set_version` in particular, you cannot tell whether a 6-month-old submission
was screened with today's rules or yesterday's rules — that matters for any audit.

**Action:** lock the `extracted_metadata` shape and paste a representative example
object in the next status update.

### Change 5 — Offline replay design: PASS
- Triggers: app resume (lifecycle observer) + manual pull-to-refresh. (Connectivity
  stream not used — acceptable, since resume+pull covers practical recovery.)
- `auth.uid()` mismatch handled as **orphaned**, surfaced in the UI; not silent drop or
  silent upload.
- Retries capped at 3 attempts per item.
- The test "Orphans and blocks submission when `uploader_id` does not match active
  auth uid" actually verifies the identity check.

### Note A — Automated "no network during OCR" check: SILENT
The Gate B review asked for this to be an automated assertion, not a manual check. The
walkthrough's test list does not include it. The "Queues file to Drift SQLite when
offline exception occurs" test proves **offline submission behavior**, which is a
different guarantee than **OCR ran with zero network calls**. The on-device-OCR
constraint is one of the paper's stated privacy selling points and deserves a real
assertion.

**Action:** either add an automated assertion (HTTP override / network mock active
during OCR; assert ML Kit still produces output), or state explicitly that it remains
a manual check and why.

### Note B — Test-data hygiene: PASS
Implemented via the `__test__/` path prefix in the file-naming format. Test artifacts
are now identifiable and easy to purge.

---

## Flag — `HttpOverrides` relaxation

The Verification Results section states:
*"Disallowed Flutter test HTTP overrides so standard internet timeouts/lookups function
correctly in test contexts."*

Flutter's test environment defaults to a strict `HttpOverrides` that makes real HTTP
fail with `400`. Disabling that override means tests can make real network calls. Two
concerns:

1. If the offline-queue test relies on a real network call **timing out** to trigger
   the offline branch, the test will be slow and flaky depending on local DNS / network
   state.
2. If the OCR test runs with real network access enabled, the "no network during OCR"
   guarantee (Note A) becomes harder to verify, not easier.

The cleaner pattern is the opposite: **explicitly inject** a network failure (e.g. a
mocked `SupabaseStorageClient`) for the offline-branch test, and keep `HttpOverrides`
strict so real-network calls fail loudly during tests.

**Action:** explain in the next status update which test required the relaxed override,
why, and whether the tradeoff is right.

---

## What the build did well

- **The five Phase 4 tests are the right tests, not boilerplate.** Name-match,
  missing-fields, offline queueing, and identity-mismatch blocking all map to risks the
  guide flagged.
- **The orphaning UX** (surface to user, never silently drop or upload) is exactly the
  right behavior for a healthcare data path.
- **The phases are stacking cleanly** — Phase 4 routes through `OfflineDocumentsQueue`,
  the Drift table built in Phase 3. That was the point of Phase 3's groundwork.
- **Plan / build alignment is high** — the agent followed the Gate B plan
  substantially, which is the first time Gate B has been honored end-to-end.

---

## Carry-overs from prior phases

Phases 2 and 3 remain CONDITIONAL until `schema_proposals.md` is **actually sent** to
the web team. Phase 4 has now added the Storage policies to that same file, so the file
contains more outstanding items than before. The cost of further delay is rising.

**Action:** send `schema_proposals.md` to the web team this week. Record the date.

---

## What closes Phase 4 fully

The conditional PASS becomes a clean PASS when:

1. The Storage policy SQL in `schema_proposals.md` uses the technically correct shape
   (`storage.objects` + `storage.foldername(name)` + `get_auth_user_role()`), pasted in
   the next status update.
2. The `extracted_metadata` jsonb shape is locked down and documented, with an example
   object including `keyword_set_version`.
3. Note A is closed — either an automated assertion or an explicit decision to keep it
   manual with a stated reason.
4. The `HttpOverrides` relaxation is explained — which test, why, is the tradeoff right.
5. `schema_proposals.md` is sent to the web team (carry-over from Phase 2/3, now also
   carrying Phase 4's Storage proposal).

No code rework required.

---

## Status & next gate

- **Gate D for Phase 4: CONDITIONAL PASS.** Update the progress tracker in
  `MASTER_CONTEXT.md`:
  - Phase 0 — PASS
  - Phase 1 — PASS
  - Phase 2 — PASS (conditional)
  - Phase 3 — PASS (conditional)
  - Phase 4 — PASS (conditional)
- **Next: Gate A -> Gate B for Phase 5 (RAG chatbot via Edge Function).** Phase 5 is
  the **single most security-critical phase** of the project — it introduces the Gemini
  API key, which must never reach the client (non-negotiable constraint #1). The
  Phase 5 plan MUST include all of the following:
  1. **Edge Function deployment plan** — how `chat` is deployed, and confirmation that
     `GEMINI_API_KEY` is stored as a Supabase secret (`supabase secrets set ...`), not
     in `env.dart`, not in the app, not in the repo.
  2. **Embedding dimension** — must be **768** to match `rag_documents.embedding
     vector(768)`. State the Gemini embedding model chosen and its output dimension.
  3. **RAG retrieval design** — direct `rag_documents` query vs. a SQL match function.
     Coordinate with the web team so there is one agreed approach.
  4. **The exact system prompt** for Gemini — Claude will read this closely. It must
     enforce: answer only from provided clinic content; if unknown, say so and suggest
     contacting the clinic; never give medical advice, interpret lab values, or
     diagnose (constraint #4).
  5. **`chatbot_logs` insert payload** — every column with its value source.
  6. **Knowledge-base ingestion approach** — coordinate with the web team so
     `rag_documents` is shared, not duplicated.

  Draft the Phase 5 plan using the template in `MASTER_CONTEXT.md` section 6.1 and
  submit it for Gate B review before any Phase 5 code.

## Guidance for the Antigravity agent

1. **Plan/build alignment is now expected.** Phase 4 followed the Gate B plan
   substantially — this is the new baseline. Future phases must continue running plan
   reviews before building.
2. **Filing a proposal is not the same as filing the right proposal.** When a Gate B
   review corrects the shape of a SQL artifact, the corrected shape is what goes into
   `schema_proposals.md` — paste it in the next status so the reviewer can verify.
3. **Verification scope must match the constraint.** "Offline submission queued
   correctly" and "OCR ran with no network" are different guarantees. If the constraint
   is "OCR is on-device," the test must assert OCR-with-no-network specifically — not
   adjacent offline behavior.
4. **`HttpOverrides` choices deserve explanation.** Relaxing the strict test default has
   real consequences for flakiness and for what other constraints can be asserted.
   When changing it, document the reason in the walkthrough.
5. **Phase 5 is the highest-stakes phase for constraint #1.** Treat the Gemini API key
   as the most dangerous artifact in the project — it goes in a Supabase secret store
   and nowhere else. Plan for it accordingly.
