# Stage 2 Spec — Patient upload submission

**Status:** Investigation stopped on a mismatch between the brief and the required mobile base. No upload implementation or migration has been written.
**Date:** 2026-10-23 (Asia/Shanghai).
**Scope:** Patient photo/PDF uploads. Containment stays active. No live database, Storage, or deployed function was contacted.
**Ownership:** Setsuna owns backend application, deployment, rollback, and maintenance. Mobile owns the adapter. All work remains local for review.

---

## 1. Required stop: Stage 1 mobile baseline

The task brief says to copy the Stage 1 adapter's `/status` check before resending after an unknown outcome, and requires the mobile branch to start at `origin/main`.

After `git fetch origin main`, the required base is:

`4fa9de8c89a3a16d76c94cc64a1c85d664443b18` — Merge pull request #58 from JudgementKazzy2023/fix/patient-submission-containment-adapter.

At that revision:

- `lib/features/patient/templates/data/templates_repository.dart` has submission transport, but no status lookup method or `/status` request.
- `lib/features/patient/templates/presentation/providers/templates_provider.dart` permits an explicit retry for `SERVER_ERROR`. Its `retry` flag skips the advisory duplicate precheck and then calls `submitTemplateDocument` directly. It does not resolve the outcome through `/status` first.
- `PatientSubmissionContainment.isActive` defaults to true and `activeForTesting` exists, matching the brief.
- The offline queue's `getQueuedDocuments(String uploaderId)` is owner-scoped, matching the brief.

A local candidate implementation exists separately:

`feat/template-status-lookup` at `ec33b99` — feat(templates): ask /status before resending after an unknown outcome.

That branch has not been merged or cherry-picked into this task. Its review/acceptance status has not been assumed.

**Question requiring resolution before implementation:** Should Stage 2 wait for `feat/template-status-lookup` to land on `main`, or may this task incorporate that implementation into the new branch while retaining the requested `origin/main` base? If another accepted Stage 1 revision is intended, identify that revision.

This follows the task rule: “If something in this brief doesn't match the code you find, stop and write the question into the design doc. Don't guess.” No second retry design has been invented.

## 2. Assessment investigation: confirmed local source

Inspected the complete untracked source at:

`C:/Users/Ralph/Downloads/Klinikaid Mobile app/supabase/functions/assess-document-quality/index.ts`

SHA256: `DA0A8A2D8FDCA4F785AB9ED41D6540E9B0712913B84CEE71AE369D63E593FBC1`.

Confirmed behavior from that source:

1. Handles OPTIONS and authenticates using Supabase Auth `getUser` with the caller's authorization header.
2. Reads `ocr_text` and optional `patient_name` from JSON. It requires `ocr_text` to be present.
3. Calls Gemini to assess the supplied OCR text, with a ten-second timeout.
4. Returns `{ score, verdict, issues }`. Successful results clamp the score and calculate the verdict. Several model, timeout, parsing, or outer-handler failures return a marginal fallback with score 50 and HTTP 200; missing configuration/authentication/body validation have separate error responses.
5. Does not accept or upload a file, copy a Storage object, create a `pending_document_ocr` row, return an assessment ID, or establish a server-owned association between an assessment and file.

Mobile's `lib/features/ocr/data/document_quality_service.dart` matches that scoring-only interface: it sends `ocr_text` and `patient_name`, parses the returned assessment, and uses a fallback on failure. It does not establish the assessment record required by the upload transaction either.

**Unverified:** Whether this local source matches the deployed function. No deployment status or runtime behavior has been inferred from its presence on disk. No deployed endpoint was called.

**Design implication:** Stage 2 cannot consume an assessment produced by this scoring-only endpoint. An explicit server-owned assessment creation and file-binding step must be specified from reviewed source. The existing web assessment action is a candidate to examine when implementation resumes; no endpoint, schema, or trust boundary has been silently assumed.

## 3. Backend baseline observed

The provided web worktree is clean at:

`9be996ce89e539dbd9fb5b0ea24a2d9f01f6d1be` — chore(db): regenerate schema.sql through migration 41 (#222).

Read-only inspection confirms that migration 41 includes `submit_patient_template_outcome`, and the template handler recognizes the `/status` subpath. Migration 34 consumes the owner's pending assessment with a delete and writes `documents.source_assessment_id` with unique enforcement.

The web branch `feat/patient-upload-submission` has not been created, and no web files were changed: the required stop was reached before implementation.

## 4. Contract and decisions pending the baseline resolution

The agreed rules in the task brief remain accepted: shared per-patient/category duplicate enforcement; other/missing category exemption; stable owner/operation-scoped request IDs; 30-day replay with indefinite receipt retention; atomic document/event/receipt creation; no silent insertion after expiry or withdrawal.

Routes, upload request keys and response bodies, assessment creation/file binding, error-code additions, fingerprint contents, the choice for web upload integration, and copy/cleanup ownership are intentionally not finalized while the task is stopped. The examples `/upload` and `/upload/status` in the brief remain proposals rather than an implemented contract.

In particular, the storage-copy protocol must prove both that a failed transaction leaves no orphan final file and that cleanup cannot remove a file belonging to a committed or uncertain transaction. No claim about those guarantees has been made from mocks or uninspected deployment behavior.

## 5. Required verification after implementation resumes

No implementation test, analysis, Deno, PGlite, Vitest, or type-check result is claimed for this documentation-only stop.

The implementation must cover the brief's required scenarios:

- Deno handler tests with `--deny-net --deny-env --deny-write`: gates, body validation, owner scoping, and every upload/status outcome.
- Local, uncommitted in-process Postgres checks: replay, conflict, expiry, withdrawal, single assessment consumption, refused second consumption, cross-template/upload duplicates, other exemption, audit failure rollback, and function grants.
- Vitest coverage of modified web actions, plus TypeScript checking and the requested Vitest suite; record the exact auth-decorations result rather than treating unrelated failures as upload validation.
- Mocked mobile HTTP/Storage and temporary database checks: exact bodies/paths, every error, status-before-resend, containment before all network operations, preserved rows/files across reopen, owner isolation, explicit one-draft actions, and no replay on screen opening/resume.
- Requested Flutter analysis and full tests, with containment test overrides restored in tearDown.

## 6. Before upload containment can lift

- Resolve the Stage 1 baseline question and complete the reviewed upload contract and implementation.
- Establish the authoritative assessment-producing source and verify deployment behavior, file ownership/binding, limits, and cleanup guarantees.
- Owner applies/deploys the reviewed migration and function changes; no application/deployment is authorized by this task.
- Verify owner-scoped upload outcome lookup, indefinite receipt retention and reconciliation, and the legacy duplicate report/resolution process.
- Name the reception contact and technical escalation route.
- Complete device checks and confirm that blocked legacy drafts remain intact, owner-scoped, and individually resolved without automatic or bulk replay/deletion.
- Lift upload containment only in a separate reviewed change.

## 7. Local work record

Mobile worktree: `C:/Users/Ralph/Downloads/Klinikaid Mobile app - uploads`.
Branch: `feat/upload-submission-adapter`, created from the fetched `origin/main` revision above.
Only this design document is staged for the investigation commit. Existing changes in the original mobile checkout are untouched. No push, PR, GitHub comment, migration application, deployment, live backend request, or Storage access was performed.
