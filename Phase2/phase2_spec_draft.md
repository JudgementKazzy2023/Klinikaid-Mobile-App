# Phase 2 Spec (DRAFT) — Patient Document Submission via Edge Function

**Status:** DRAFT for cross-repo review. Not approved. No implementation.
**Date:** 2026-10-20
**Function:** `patient-document-submission` (tentative)
**Proposed owner (not yet accepted):** Web / shared backend, @Setsuna-guwah
(contract + implementation + deployment). Explicit mobile acceptance is pending.
Mobile owns the adapter, screens, offline queue, tests, release.
**Audit date:** 2026-10-20. Mobile local/PR head:
`f919be4767407e4a712f58081d78c82eb431555e`; fetched mobile `origin/main`:
`d749c503806839d78d6f6ec5c5e3dc8ab7305863`. No commits after f919be4
on fetched main; the submission code diff between these revisions is empty.
The PR head adds only the coordination document. Do not claim mobile advanced.
Web baseline moved from `a9460ce` to fetched `origin/master`
`940a2f6ed6733b647e94a708b2489cad05662095`. See section 2a.
Initial source reconciliation used no production checks. A follow-up read-only
Storage policy check on 2026-10-20 is recorded below; no writes were performed.

---

## 1. Why this exists

Patient document INSERT/UPDATE RLS policies were removed (PR #76 / migration
23). A patient without `documents.manage` cannot insert into `documents`.
Mobile's two direct-insert submission paths are therefore dead on prod.

Web uses Next.js server actions for its protected inserts. Those are not a
mobile-callable API. Mobile needs an authenticated Edge Function.

---

## 2. Current mobile call sites (to be replaced)

| # | Path | File | Current behavior |
|---|---|---|---|
| 1 | Template submission | `lib/features/patient/templates/data/templates_repository.dart:41` (insert at 42) | Direct insert with template metadata; called by `templates_provider.dart:59` |
| 2 | Online file upload | `lib/features/documents/presentation/providers/document_submission_provider.dart:294` | Storage upload precedes `DocumentsRepository.insertDocument`; shared remote insert at `lib/core/repositories/documents_repository.dart:35-36` |
| 3 | Offline upload replay | `lib/features/documents/presentation/providers/document_submission_provider.dart:352` (insert call at 407) | Re-uploads queued file, then uses the same insert helper; distinct execution path, not UPDATE |

**Pending UPDATE audit: source present, no active caller found.**
`lib/core/repositories/documents_repository.dart:47` defines
`updatePendingDocument`; line 54 sends the serialized document via UPDATE,
filtered by ID and pending status at lines 55-56. Search of application Dart
source and repository Dart references finds the definition only. There is no
identified patient UI/provider path invoking it. Its comment claiming RLS
allows this write is stale. No code was removed or changed.

**Patient remote DELETE: none found in audited mobile source.** The trash
action at `submit_document_screen.dart:873` calls `removeQueuedItem` at
`document_submission_provider.dart:81`, which removes a local Drift queue row
through `lib/core/cache/local_database.dart:165`; it does not delete a remote
documents row. Realtime UPDATE/DELETE listeners in `document_status_provider.dart`
consume events, not remote mutation requests. A surviving policy is not evidence
of a mobile call site.

**Staff mutations are separate:** reception approval at
`lib/features/reception/data/reception_repository.dart:253`, rejection at 270,
and staff status update at
`lib/features/staff/data/repositories/staff_queue_repository.dart:101` are
document UPDATE operations. Do not route them through the patient endpoint.

Blocking item 7 is resolved for this source baseline: three active INSERT paths,
one unused UPDATE helper, no identified patient remote DELETE. A create-only
contract covers current submission callers, not hypothetical editing/withdrawal.
The dormant helper must not acquire callers without a separately approved contract.

## 2a. Web baseline changes requiring contract reconciliation

These are merged source observations, not proof of production deployment.

| Change after a9460ce | Draft impact / owner decision |
|---|---|
| `dd6d122` / PR #106, migration 34 | Web now has service-role-only `submit_assessed_document`, `source_assessment_id` uniqueness and transactional assessment consumption/document insertion. Review reuse with the backend owner; do not invent competing primitives. This does not prove template retry idempotency, business-category dedup, or transactional audit guarantees. |
| `c4ec3a2` / PR #116, migration 36 | Pending-only Storage policy behavior confirmed LIVE on 2026-10-20 (see below). Mobile's current root-folder upload path fails before document INSERT. Final objects are server-managed in merged web code. |
| `ada580d` / PR #117 | Detected tests require a nonempty selection; zero-detection requires explicit submit-anyway acknowledgement. JSON currently has no acknowledgement field: exact field and server semantics must be agreed before finalization. |
| `0d61ea8` / PR #102 | Shared template validation now includes length/date bounds and stored-answer review. Declined form consent can be stored and flagged for reception, distinct from the account privacy gate. Pin/reconcile authoritative definitions rather than invent clinical acceptance rules. |
| `58d3098` / PR #113 | Demographic/notes bounds changed; reconcile template identity and allowed-field validation with these shared rules. |
| `f16575a` / PR #99 | Requestable laboratory coverage changed; recompare test IDs/catalogs before declaring byte parity. |
| `940a2f6` / PR #125 | schema.sql now reflects migrations through 36. A snapshot in Git is not proof those migrations are applied to production. |

The three-operation boundary remains a proposal. Storage staging and test
selection assumptions need revision; new server primitives must be reconciled.

### Live Storage confirmation (2026-10-20)

The linked backend matched mobile configuration. Read-only pg_policies and
pg_class checks show storage.objects RLS enabled. The only INSERT policy is
`Allow patient upload own files`, requiring bucket `patient-documents`, folder
1 = auth.uid(), and folder 2 = `pending-submissions`. DELETE has the same
pending-folder restriction; remaining policies are SELECT only. No broader
INSERT/ALL policy was returned. This confirms deployed policy behavior matching
PR #116, not the migration-history entry or web deployment version.

Mobile online and offline uploads target `<user>/<uuid>_<filename>`, so ordinary
patient uploads are denied by Storage before reaching the separately restricted
documents insert. Template inserts have no Storage upload step and remain
independently blocked by documents RLS. No upload, patient record query, policy
change or deployment was performed to establish this result.

PR #99/#117 shipped-feature drift is separately tracked in
[patient_test_detection_drift.md](patient_test_detection_drift.md). It must not
be deferred merely because Phase 2 is blocked. No fixes are authorized here.

---

## 3. Operations

Three operations, per the web team's confirmation:

Review note: the following summaries are not the finalized JSON contract. The
web comment proposes assess_upload(request_id, storage_path, document_type),
submit_upload(request_id, assessment_id, selected_test_ids), and
submit_template(request_id, template_id, fields). File/category identity on
finalization should resolve from the bound assessment, not be overridable.
Before finalization specify all exact keys, the PR #117 acknowledgement field,
allowlists, unknown-key rejection, user+operation-scoped idempotency, in-progress
handling, and error/status JSON. Account gates apply on every operation/retry.

### `assess_upload`
Assess an uploaded file's quality. Returns an assessment bound to that exact
stored file.

- **Input:** reference to the uploaded file in the private `patient-documents`
  bucket (path or object id), plus optional client OCR preview hints.
- **Server:** performs/validates the authoritative assessment against the
  actual stored file. Client OCR is a **hint only** and is never trusted as the
  assessment of record.
- **Output:** assessment result + an assessment reference usable by
  `submit_upload`.
- **Open:** assessment expiry (how long an assessment reference remains valid).

### `submit_upload`
Create a document from an uploaded file.

- **Input:** file reference, assessment reference, document type, selected
  tests, stable request ID.
- **Server derives:** patient identity, uploader identity, `status = 'pending'`.
  Client-supplied ownership/status overrides are rejected, not silently ignored.
- **Server validates:** active patient profile, confirmed email, privacy
  consent, temporary-password status, file type/size, assessment binding, test
  selections, duplicate prevention.
- **Output:** created document (or the existing document on idempotent replay).

### `submit_template`
Create a document from a structured template.

- **Input:** template id, template field values, stable request ID.
- **Server derives:** patient identity, uploader identity, `status = 'pending'`,
  `file_name`, `file_path` (`template://…`), `file_type = 'template'`.
- **Server validates:** same account-state checks, template id against the
  allowlist, field values against that template's schema, duplicate prevention.
- **Output:** created document (or existing document on idempotent replay).

---

## 4. Account-state preconditions (server-enforced)

Every operation validates, server-side:
- Authenticated user (JWT)
- Active patient profile
- Confirmed email
- Privacy consent accepted
- Temporary-password status (`must_change_password` not set — see Phase 4)

A failure in any precondition returns a distinguishable error so mobile can
route the patient to the right remediation (verify email, accept consent,
change password) rather than showing a generic failure.

**Open:** exact error codes per precondition.

---

## 5. File handling

- Bucket: private `patient-documents`
- Allowed types: PDF, JPEG, PNG
- Max size: 5 MiB
- Assessment must bind to the exact stored file (not a client-asserted hash or
  a different object)

**Cleanup ownership — unresolved.** If upload succeeds but submission fails,
who removes the orphaned file? Options: server-side cleanup on terminal
failure; a scheduled sweep of unreferenced objects; or client-initiated delete.

**Constraint that rules out the naive approach:** an **ambiguous timeout must
not trigger deletion** — the submission may have committed. Cleanup must be
driven by confirmed terminal failure or a sweep that can distinguish referenced
from unreferenced objects, never by a client-side timeout.

---

## 6. Idempotency and retry

- Mobile generates a **stable request ID** per submission attempt, reused across
  retries of that same submission.
- A successful replay returns **the same document**, not a second insert.
- Mobile must not generate a new request ID on retry — that defeats idempotency.

**Open:** idempotency retention window (how long the server remembers a request
ID). Mobile's retry policy must stay inside it.

---

## 7. Duplicate prevention

Business duplicate prevention (beyond request-ID idempotency) must handle
**concurrent submissions across clients** — the same patient submitting from web
and mobile simultaneously.

Mobile currently enforces one-pending-per-type client-side (the dedup feature).
That logic should move server-side or be mirrored there; a client-side check
cannot be atomic across two clients.

**Open:** atomic cross-client deduplication mechanism. A client-side check plus
a server-side unique constraint behaves differently from a server-side
transactional check; the contract must say which.

---

## 8. Audit

Each **new** document produces exactly one attributed `DOCUMENT_SUBMITTED` audit
event. An idempotent replay must **not** emit a second event.

**Open:** audit-failure recovery. If the document commits but the audit write
fails, what happens — is the submission rolled back, or is the audit gap
reconciled separately?

---

## 9. Mobile adapter responsibilities

- Build requests; never send patient/uploader identity or status.
- Generate and persist stable request IDs with the draft.
- Map server error codes to specific user-facing remediation.
- Offline queue: persist drafts; **no automatic replay** without reconciliation
  (see the containment document).
- Distinguish: confirmed failure (safe to retry with same request ID) vs
  ambiguous timeout (refresh and check before retrying) vs precondition failure
  (route to remediation).
- Preserve existing behavior where it remains valid: document metadata, test
  selection, quality checks, dedup UX.

---

## 10. Unresolved decisions (must close before implementation)

| # | Item | Owner | Blocking? |
|---|---|---|---|
| 1 | Exact allowlists / category mappings (template ids, document types, test catalog) | Web | Yes |
| 2 | Assessment expiry and consumption behavior | Web | Yes - contract required before finalization |
| 3 | Idempotency retention and mobile retry horizon | Web + Mobile | Yes - contract required before finalization |
| 4 | Atomic cross-client deduplication mechanism | Web | Yes |
| 5 | Audit-failure recovery | Web | Yes |
| 6 | File cleanup ownership on failed submission | Web | Yes |
| 7 | Patient UPDATE/DELETE call-site audit | Mobile | Resolved at audited baseline: unused UPDATE helper only; no remote patient DELETE caller; offline replay is active path 3 |
| 8 | Error codes per precondition failure | Web | Yes |

Items 1-6 and 8 remain contract-shaping. Also resolve proposed ownership,
staged-path compatibility, zero-detection acknowledgement, and reuse of migration
34 primitives. This draft is not FINALIZED.

---

## 11. Acceptance-test matrix (disposable fixtures only)

| Scenario | Expected |
|---|---|
| Valid template submit | Document created, `status = pending`, one audit event |
| Valid upload submit | Document created, bound to assessed file, one audit event |
| Replay with same request ID | Same document returned, no second insert, no second audit event |
| New request ID for an already consumed assessment or pending-category duplicate | No second logical submission; enforce assessment/business duplicate rules, not a guaranteed new insert |
| Same key with different normalized content | 409 IDEMPOTENCY_CONFLICT |
| Client sends patient_id / uploader_id / status | Rejected; server derives these values only for valid requests |
| Unconfirmed email | Distinguishable precondition error |
| Consent not accepted | Distinguishable precondition error |
| `must_change_password` set | Distinguishable precondition error |
| Inactive profile | Denied |
| File > 5 MiB | Rejected |
| Disallowed file type | Rejected |
| Assessment for a different file | Rejected |
| Expired assessment | Rejected (once expiry defined) |
| Invalid template id | Rejected |
| Template field violating schema | Rejected |
| Invalid test selection | Rejected |
| Concurrent duplicate (web + mobile) | Exactly one document created |
| Ambiguous timeout | No file deletion; retry with same ID is safe |
| Submission fails after upload | File cleanup per the defined owner; no orphan accumulation |

All fixtures disposable. No production patient data. Mobile tests fully mocked —
no live Supabase initialization (per the test incident documented in the
overnight-queue walkthrough).

---

## 12. Rollout dependency

Mobile Phase 2 is **blocked** until the function is deployed to a reachable
environment. Sequence:

1. Both sides accept ownership; backend owner finalizes all contract-shaping items
2. Web implements and deploys to staging
3. Mobile builds adapter against staging
4. Mobile Gate D on staging
5. Web deploys to prod
6. Mobile Gate D on prod
7. Containment lifted + draft reconciliation

Containment is proposed, not implemented. If separately approved and released,
it remains in force through steps 1-6. No staging environment or rollout approval
is implied by this proposed sequence.
