# Stage 2 Spec — Patient upload submission

**Status:** Implemented locally for review; migration 42 is written but not applied. Upload containment remains active. No production backend or Storage was contacted.
**Date:** 2026-10-23 (Asia/Shanghai).
**Scope:** Patient JPEG/PNG/PDF uploads, shared web/Edge persistence, owner-scoped mobile drafts and reconciliation. Template implementation is unchanged after the explicitly requested merge.
**Ownership:** Setsuna owns backend application, deployment, rollback, and maintenance. Mobile owns the client. Reception owns patient cases; Setsuna owns technical receipt recovery.

---

## 1. Baselines and resolved question

Mobile started at fetched `origin/main` `4fa9de8c89a3a16d76c94cc64a1c85d664443b18` on `feat/upload-submission-adapter`, in `C:/Users/Ralph/Downloads/Klinikaid Mobile app - uploads`.

The brief's Stage 1 status-before-resend behavior was absent there. The initial investigation recorded that mismatch in commit `10381d2`. The user resolved it by explicitly authorizing `git merge --no-ff feat/template-status-lookup`, at `ec33b99f240c6fa1cebe813ac6d7e031e95f9d8e` (PR #60). Merge commit: `e221c7e`. No further template implementation changes are part of this task. If PR #60 changes during review, merge the accepted `origin/main` later as the user directed.

Web started at `origin/master` `9be996ce89e539dbd9fb5b0ea24a2d9f01f6d1be`, in `C:/Users/Ralph/Downloads/Setsuna KlinikAid - submission`, on `feat/patient-upload-submission`. Backend implementation commit: `eba25bf`.

Read the web migration 34/41 implementations, handler/index/tests/import map, assessed-file helper, web assess/confirm/discard actions, shared test detector and Storage/pending-row schema policies. The mobile design extends the merged template adapter's typed results, stable IDs and status-before-resend flow.

## 2. Assessment investigation

Inspected the complete untracked source:

`C:/Users/Ralph/Downloads/Klinikaid Mobile app/supabase/functions/assess-document-quality/index.ts`

SHA256: `DA0A8A2D8FDCA4F785AB9ED41D6540E9B0712913B84CEE71AE369D63E593FBC1`.

The source authenticates via Auth.getUser, reads `ocr_text` and optional `patient_name`, calls Gemini with a ten-second timeout, and returns `{ score, verdict, issues }`. Several model, timeout, parsing or outer-handler failures return HTTP 200 with the marginal score-50 fallback. Configuration/authentication/body failures have separate responses.

It does **not** accept/store a file, copy a Storage object, create `pending_document_ocr`, return an assessment ID, or bind the scoring result to an object. Mobile's `document_quality_service.dart` uses that scoring-only interface and fallback.

**Decision:** Mobile explicitly creates its own assessment record, following the tracked web assess action. The scoring endpoint remains an advisory preview, never evidence that a consumable assessment exists. PDF selection uses the existing reception-review fallback with empty OCR; server acceptance does not require successful OCR, matching web's failed-OCR behavior.

**Open question for Setsuna:** Confirm deployed `assess-document-quality` behaviour and identify its authoritative tracked source. Its deployed implementation was not called or inferred from this local copy. If it has additional side effects, reconcile those before release.

## 3. Preparation and ownership

For each submission content, mobile creates stable UUID v4 `request_id` and `assessment_id`, saves a durable local draft before dispatch, and uploads with `upsert: false` to:

`<authenticated uid>/pending-submissions/<assessmentId>/source.<ext>`

Extensions are canonical `pdf`, `png`, or `jpg`; the server also accepts `jpeg` for existing web-created JPEG assessments. Mobile then inserts its own `pending_document_ocr` row:

```json
{
  "id": "<assessmentId>",
  "user_id": "<authenticated uid>",
  "patient_id": "<linked patient row id>",
  "file_name": "<display name>",
  "file_type": "application/pdf | image/jpeg | image/png",
  "file_path": "<derived pending path>",
  "ocr_text": "<captured text or empty string>"
}
```

This is an assessment-row insert permitted by the existing patient policy, **not** a `documents` insert. Patient and uploader on the final document are derived/verified server-side. Every awaited client boundary rechecks the captured identity. An identity switch stops further dispatch and suppresses stale success or queue deletion.

Preparation is immutable. If an upload response was lost and the object already exists, mobile downloads it and compares the bytes before using it. If a pending-row insert is already present, it reads the owner-scoped row and requires every submitted field to match. It never overwrites the file or row. Preparation failures preserve the local draft and original file.

## 4. Upload routes

Existing template root and `/status` behavior remain unchanged. New routes are:

### POST `functions/v1/patient-document-submission/upload`

Authenticated with the patient's JWT. The request is exactly:

```json
{
  "request_id": "<UUID>",
  "assessment_id": "<UUID>",
  "document_type": "lab-request",
  "selected_test_ids": ["cbc"]
}
```

`document_type` may be omitted, defaulting to `other`; when present it must be `other` or one of the shared template category IDs. `selected_test_ids` is optional. Unknown top-level keys are rejected. No caller-selected final path, patient ID, uploader, status, metadata, scores or test labels are accepted.

Selection semantics reuse `detectRequestedTests` and `selectDetectedTests`: omitted selection means all detected tests; explicit selection is intersected with detected tests. If tests were detected and none were selected, return `FIELD_REQUIRED` for `selected_test_ids`. No detected tests means reception reviews the uploaded document without invented selections. IDs are deduplicated and sorted for the request fingerprint.

Success is HTTP 200:

```json
{ "document_id": "<UUID>", "status": "pending", "replayed": false }
```

`replayed: true` is also confirmed success. The server-derived upload metadata contains `document_type` and, when applicable, the same detected/selected test arrays and detection source/version as web. Client preview demographic/quality metadata is not copied into the document.

### POST `functions/v1/patient-document-submission/upload/status`

```json
{ "request_id": "<the original UUID>" }
```

Owner-scoped, same account gates, no writes and no resend. Responses mirror migration 41:

- `committed`: document_id, current status, first_accepted_at, replayable.
- `withdrawn`: first_accepted_at.
- `not_found`: no retained upload receipt for this owner/request.

A committed lookup resolves the draft even when its receipt is no longer replayable. A withdrawn lookup requires clinic reconciliation and preserves the original ID; it never silently generates a fresh submission.

## 5. Gates, file validation and fingerprint

Upload submission and lookup run every existing gate, including on replays: authenticated user, active profile, patient role resolved through `role_id`/roles (`resolvedRole`), linked patient row, verified email, accepted account privacy consent, and no forced password change. Uploads do not acquire template-intake's DOB/age gate.

The server validates the assessment's owner/patient/ID, permitted pending path, MIME type, nonzero size up to 5 * 1024 * 1024 bytes, and PDF/JPEG/PNG signature. It reads the Storage object identity/metadata before downloading. The transaction then locks and compares both the assessment snapshot and Storage snapshot, refusing a replacement between validation and commit.

The server fingerprint is SHA-256 of canonical assessment ID, category and normalized selection. The assessment ID is the immutable file/assessment identity. Mobile separately fingerprints bytes, display name, MIME, OCR, category, selection and patient to detect edits and allocate fresh request/assessment IDs. Reordering the same selection is not an edit.

The authoritative test catalog was moved unchanged to runtime-neutral `clinicTestCatalog.ts`, re-exported from `constants.ts`. Both web and Edge detection use that single catalog. This avoids evaluating constants.ts's NODE_ENV read under Deno's denied-environment test permission.

## 6. Persistence and storage decision

Migration 42 widens `submission_receipts.operation` to include `submit_upload`. The new submit and lookup functions are SECURITY INVOKER, `search_path = ''`, and executable only by service_role. Receipts remain indefinitely, with a 30-day replay window; no cleanup or retention job is introduced.

`submit_patient_upload` performs, in one transaction:

1. Verify the patient belongs to the authenticated owner and take `submit_upload:<user>:<request>` advisory lock.
2. Return retained receipt replay/conflict/expired/withdrawn outcomes before requiring the consumed assessment.
3. Lock the owner's pending assessment; refuse a missing, mismatched or previously consumed assessment.
4. Validate/lock the derived Storage object and compare the service-read snapshots.
5. Take the exact `pending_document:<patient>:<category>` lock used by templates; reject a collision with the existing document ID/status. `other` and missing category are exempt. Rejection changes neither existing document nor assessment.
6. Transactionally seal the Storage object's metadata, consume the assessment, and insert the pending document with unique source_assessment_id, attributed DOCUMENT_SUBMITTED event (metadata.document_id), and receipt.

**Decision: promote the pending object in place; do not copy it to a second path.** A Storage copy and Postgres commit cannot form one transaction. Keeping the original object avoids the two-file orphan/cleanup race entirely. Failed SQL rolls back the seal and assessment consumption, leaving the original pending draft. The final document references the server-validated pending path; no client-selected final path is trusted.

The transaction updates the object row version while sealing it. A tightened patient DELETE policy refuses sealed/referenced objects; a trigger rejects deletion or replacement, even by cleanup code, while a document references the file. Read bookkeeping fields may update without changing the object. No new code calls Storage.remove after submission or on an uncertain outcome. Receipts are retained through cancellation; the cancelled document's file is no longer protected, so web's existing cancel cleanup still removes it (review fix, `d9156d5`).

**Verification limit:** The SQL metadata protection and rollback are tested in-process. Actual Supabase Storage service behavior, permissions and physical-object lifecycle still require owner verification in an isolated project. The tests do not claim production deployment or multi-connection advisory-lock contention.

## 7. Web integration choice

The web confirm action now calls the same shared upload validator/store and `submit_patient_upload`; it no longer copies the file, calls the legacy submit_assessed_document path, performs destructive pending-file cleanup, or logs DOCUMENT_SUBMITTED outside the transaction.

The assessment UUID was generated by the web server during assessment creation; it is the stable web request ID. Repeated confirmation replays the original document; changing a selection already accepted under that ID conflicts. A genuinely new upload uses a new server-created assessment. A third optional category argument defaults to `other`, preserving the existing web UI's category behavior while allowing categorized callers to join the shared duplicate rule.

Assessments already consumed under the legacy migration-34 flow have no migration-42 receipt. The new path reports an unavailable assessment/contact-clinic state rather than manufacturing receipt evidence or silently creating another document. The legacy function and finalDocumentPath helper remain historical compatibility code; the active web confirm action no longer uses them.

## 8. Outcomes and errors

All errors use `{ error_code, message, field?, document_id?, status? }`.

| SQL outcome | API behavior |
|---|---|
| created / replayed | 200 with original document ID; replay adds no event |
| conflict | 409 IDEMPOTENCY_CONFLICT; contact clinic, no automatic retry |
| expired / withdrawn | 409 RECONCILIATION_REQUIRED; preserve key/file/answers |
| duplicate | 409 DUPLICATE_PENDING, document_id and status; link existing record |
| assessment_not_found | 409 ASSESSMENT_NOT_FOUND; missing, wrong-owner or already consumed assessment; no disclosure of another owner's data |
| file_invalid | 400 FIELD_INVALID, field=file; missing/replaced/invalid Storage object |

`ASSESSMENT_NOT_FOUND` is the only added upload-specific error code: consumption is a distinct prerequisite that templates do not have. File and selection failures reuse FIELD_REQUIRED/FIELD_INVALID rather than adding another family of errors.

Mobile maps field errors to visible form feedback; duplicates to the named category message and `/documents/status?document_id=...`; auth/email/consent/password codes to existing flows. Account/data/age errors retain the server message. Unknown-field/template/method drift prompts an app update. Unrecognized/malformed responses, timeout, network failure and SERVER_ERROR remain uncertain, never certain failure/success:

“We could not confirm this submission. Your file and answers are still here. Try again, or contact the clinic.”

Conflict/reconciliation/consumed-assessment states are persisted as blocked and never automatically retried.

## 9. Mobile draft lifecycle

Local Drift schema version 2 adds request_id, assessment_id, upload_state and submission_content to the existing queue. The migration only adds fields and assigns each existing row its own IDs and `legacy` state. All original columns, metadata, timestamps, owner and file paths remain unchanged. A real v1 database/reopen test verifies preservation and stable IDs.

New selected/captured files are copied into the app's documents area before queueing, under an owner-specific drafts directory. The content snapshot includes a byte hash. The queue is saved before preparation and marked `unknown` **before** dispatching the submit operation, so process termination cannot turn a possibly committed submission into an apparently never-sent draft.

Unknown and migrated legacy drafts check `/upload/status` before an explicit resend. Unchanged content retains IDs; edited content gets new IDs after the previous uncertain outcome is checked. A fresh form cannot bypass an unresolved saved draft merely by reselecting its original file after app restart. Historical pre-receipt writes cannot be reconstructed from a newly assigned legacy request ID; the legacy duplicate report and clinic review remain release prerequisites, not evidence produced by this local task.

No opening, app resume, auth event, constructor or syncOfflineQueue callback submits any queued row. The sync compatibility entry only reloads local rows. The signed-in owner must choose and confirm one saved draft. Other owners' rows are hidden and untouched. Missing files are retained and surfaced for support; they are never silently removed.

A local queue row is removed only after confirmed submit success or a committed status lookup. At that point the app's private copy under `submission-drafts/<owner>/` is deleted too, so submitted medical documents do not accumulate on the device; the patient's original file is never touched. No other local or remote file is deleted automatically. Duplicate rejection, field errors, unavailable lookup, timeout, conflict, withdrawal and blocked states retain the draft/file. The patient direct documents insert/update APIs have been removed; document reads remain.

Detected tests on mobile uploads come from OCR text the client wrote into its own pending row, so they are labelled `test_detection_source: "client_ocr_catalog_match"`; web keeps `"ocr_text_catalog_match"`. Reception reviews the original file either way.

## 10. Validation and evidence

**Outside the brief, kept in this branch:** about 20 existing test files had the real production Supabase URL and anon key replaced with synthetic values, and `test/flutter_test_config.dart` now fails any live HTTP in tests. Both are safety improvements unrelated to uploads; they can be split into their own PR before review if preferred.

No live database/Storage/assessment calls, credentials, migrations, deployments, pushes or GitHub comments were used. Flutter tests have a global fail-closed HTTP override; explicit mocked clients remain usable. Legacy production initialization literals were replaced with synthetic URL/key values. Every test-only containment override is restored in tearDown.

Required coverage includes exact request bodies/paths/JWT; success/replay; every error mapping; same-ID retry/status ordering; changed content; no retry after reconciliation/conflict; owner switch during storage/assessment/submit; disposed/concurrent operations; persisted unknown state; reopening; missing files; individual legacy review; containment; and opening/resuming the enabled/contained screen without replay. Existing upload owner/dedup tests were updated to assert the replacement flow rather than removed.

Deno handler tests: 49 passed with --deny-net --deny-env --deny-write. Deno entry-point check passed.

Local PGlite script and logs are under the web worktree's ignored `private/stage2-validation/` and are not committed. Fourteen scenarios passed: atomic create; replay/conflict; second consume refusal; owner lookup and expiry; withdrawal; duplicates in both template/upload directions; other/missing-category exemption; audit-failure rollback including seal/assessment; sealed-file cleanup refusal; invalid Storage metadata/size; grants/invoker/search_path; stale assessment/object snapshots; and read-bookkeeping compatibility. Multi-connection contention is not claimed.

Web: TypeScript checking and production build passed. Full Vitest produced 763 passed, one skipped and the brief's known Windows-only auth-decorations path-separator failure. Excluding only that named test produced 763 passed, one skipped. npm run verify passed typecheck/lint and stopped at that known unit-test failure; build and anonymous browser gates were then run separately with synthetic configuration. Browser checks passed 12, skipped the signed-in admin test. The installed local Chrome was used because Playwright's bundled executable was absent. Configuration-test and final mobile results are recorded in the completion report.

Exact command output is preserved locally in the web ignored validation directory and `C:/Users/Ralph/Downloads/Klinikaid Mobile app/.review/stage2-*.txt`. New ignored test files must be staged with git add -f.

## 11. Open questions for Setsuna and release prerequisites

- Confirm deployed assess-document-quality behaviour and track its authoritative source.
- Review the in-place promotion/seal protocol, Storage API permissions/physical lifecycle and retention/cancellation cleanup policy in an isolated deployment. No production behavior is inferred from mocks.
- Review/apply migration 42 and deploy the Edge/web changes in the documented order; regenerate schema.sql only after application. Review rollback without deleting receipts or submitted-file protection.
- Verify owner-scoped outcome lookup, 30-day replay with indefinite receipt evidence, concurrent requests/assessment consumption/category locking and crash recovery against real multiple connections.
- Run the legacy pending/conflict/unclassifiable duplicate report. Decide how to reconcile historical queue attempts that predate receipts; a new legacy request ID alone is not proof about historical direct writes. Keep uncertain/unclassifiable cases with reception/owner review.
- Name the reception contact and technical escalation route.
- Perform Android device checks: capture/PDF input, quality/selection/field errors, duplicate link, auth remediation, lost responses, app termination/reopen, account switches, offline files and explicit one-draft resolution. No bulk or lifecycle replay/deletion may be restored.
- Reconcile PR #60 review changes by merging accepted origin/main later, as directed by the user.
- Lift upload containment only through a separate reviewed change. It remains active throughout this task.

## 12. Final local verification and commits

Mobile implementation: `20da970` on `feat/upload-submission-adapter`. Backend implementation: `eba25bf`, followed by coverage commit `8da6c0a`, on `feat/patient-upload-submission`. The earlier mobile investigation and authorized merge are `10381d2` and `e221c7e`. No template implementation differs from the merge baseline.

Final mobile command:

`flutter test --no-pub --reporter expanded --concurrency 1`

Exact summary: `04:28 +526 ~1: All tests passed!` — 526 passed, one pre-existing skipped auth-client test. An earlier parallel run exposed an unrelated chatbot timing assertion; the full serial run passed. No test failure is being ignored in this final mobile result.

`flutter analyze --no-pub --no-fatal-infos` exited 0: 36 informational diagnostics, zero warnings and zero errors. Information-level lint cleanup in unrelated code is outside this task.

Backend results: 49 Deno tests passed; 14 in-process SQL scenarios passed; TypeScript checking exited 0 with no diagnostics; ESLint reported no warnings/errors; production build passed; configuration tests passed 4/4; anonymous browser checks passed 12 with one signed-in test skipped.

Full Vitest's exact totals are `Test Files 1 failed | 53 passed | 1 skipped (55)` and `Tests 1 failed | 763 passed | 1 skipped (765)`. The sole failure is the brief's allowed Windows path-separator difference in `src/app/(auth)/auth-decorations.test.ts`. Excluding only that test gives 763 passed and one skipped. `npm run verify` therefore stops at its unit gate; its typecheck/lint gates passed, and build/browser/configuration checks were verified separately. This is not represented as a green full verification receipt.

The full command outputs, changed-file lists and commit list are linked from the local completion report at `C:/Users/Ralph/Downloads/Klinikaid Mobile app/.review/stage2-final-report.txt`. The PGlite script remains local/ignored and uncommitted. All new test sources were explicitly added with git add -f; the copied env.dart remains ignored and uncommitted. Nothing was pushed, applied or deployed.
