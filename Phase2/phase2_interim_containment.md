# Interim Containment — Patient Document Submission

**Status:** Proposed containment only. NOT implemented or released. Explicit
implementation and release approval pending. No backend deployment.
**Date:** 2026-10-20
**Context:** Patient document INSERT/UPDATE RLS policies were removed on prod
(PR #76 / migration 23). Mobile's direct-insert submission paths are now
RLS-denied. Phase 2 (the `patient-document-submission` Edge Function) is a
coordinated build with proposed web/shared backend ownership; timeline and
ownership acceptance are not finalized. This document
covers what mobile does in the meantime.

---

## Problem

Patients cannot submit documents. Two mobile paths call
`_client.from('documents').insert(...)` directly:
1. **Template submission** — `templates_repository` (the 6 structured forms)
2. **File upload submission** — `document_submission_provider` via DocumentsRepository

There is also a third active execution path: offline upload replay through
DocumentsRepository. An unused pending-document UPDATE helper exists, but no
caller or remote patient DELETE action was found (see the spec audit).

### Exact entry points audited at mobile f919be4 / main d749c50

| Entry point | Guard boundary proposed for review |
|---|---|
| `lib/features/patient/templates/presentation/screens/template_form_renderer_screen.dart:123` -> `templates_provider.dart:59` -> `templates_repository.dart:42` | Patient template UI plus provider/repository boundary before remote insert |
| `lib/features/documents/presentation/screens/submit_document_screen.dart:142` -> `document_submission_provider.dart:212` | Block before Storage upload and before local queue insertion/success handling |
| `document_submission_provider.dart:352` offline replay, insert at 407 | Provider-level stop before Storage upload, before retry increments or removal of queued items |
| `submit_document_screen.dart:32` initial screen callback and `:45` app-resume callback | Both invoke syncOfflineQueue; must remain unable to write while disabled |

Search found no other explicit syncOfflineQueue callers in lib. A future/manual
caller must also be covered by the provider guard. Block the unused
DocumentsRepository.updatePendingDocument path if a containment guard is added
at this patient repository boundary; do not silently add an edit operation.

Both are denied by RLS. The 2026-10-20 read-only Storage check additionally
confirmed pending-only INSERT/DELETE policies and enabled storage.objects RLS.
Mobile uploads to `<user>/<uuid>_<filename>` instead of
`<user>/pending-submissions/...`, so upload/sync now fails at Storage before the
documents insert. This is a second independent block, not an alternative fix:
changing the path alone would still leave document insertion denied. Templates
have no Storage upload step. No production submission was attempted.

A patient tapping Submit today gets a failure. Until the
Edge Function ships, submission cannot work — the containment makes that
**honest and non-destructive** rather than a confusing failure.

---

## Containment scope

### 1. Block before the network write

Disable submission at the point *before* any write is attempted — not by letting
the request fail. Applies to:
- Template submit
- File upload submit
- **All automatic and manual sync paths** (offline queue replay, retry-on-
  reconnect, background sync — every path that would attempt a document write)

**Recommended template UX for review:** prevent new template form entry and
show a persistent unavailable state at the entry point. Do not invite patients
to enter values that cannot be submitted. Provider/repository guards remain
necessary for already-open forms and other entry paths. This is not approval
to implement containment or add template persistence.

### 2. Preserve everything the patient created

Containment must be non-destructive. Preserve:
- Existing persisted offline upload drafts; template form values currently live
  in screen memory (`template_form_renderer_screen.dart:23`), not a confirmed
  durable template queue. Recommend preventing new template form entry instead
  of adding persistence in containment. Do not claim memory-only values survive
  restart or discard an already-open form as a side effect of the guard.
- Uploaded/captured files held locally
- Account associations and local identifiers
- Any OCR text, quality assessment, detected tests, and document-type selection
  already computed

**No bulk file cleanup.** Do not delete local files or drafts as part of
containment. When submission is restored, this material must still be usable.

### 3. Honest messaging

Message: **"Submission temporarily unavailable. This draft has not been
submitted."**

Requirements:
- Appears **before** the patient believes they submitted — not after a failed
  attempt.
- Must not imply the draft was lost.
- Must not imply a retry will work.
- Persistent/visible, not an auto-dismiss toast the patient can miss.

Preferred UX: disable or relabel the Submit action with the message inline,
rather than allowing a tap that then fails.

### 4. Keep read paths working

Unaffected and must continue working:
- Viewing previously submitted documents
- Submission status / tracking
- Records, results, chat, profile
- Existing authorized staff/admin flows; not every staff/admin role necessarily
  has documents.manage. Preserve permission/MFA gates and do not route these
  flows through patient containment.

### 5. No automatic replay on restore

When the Edge Function ships and submission is re-enabled, **do not auto-submit
queued drafts.** Replaying a queue of drafts accumulated during containment
risks duplicate submissions and unattributed writes. Restoration requires a
reconciliation step defined in Phase 2, not an automatic flush.

---

## What containment does NOT do

- Does **not** modify RLS or any backend policy.
- Does **not** attempt a workaround write path.
- Does **not** delete, clean up, or migrate local drafts or files.
- Does **not** change staff/admin document handling.
- Does **not** touch `is_flagged`, archiving, overnight queue, or any other
  shipped behavior.

---

## Open question for the web team

**Should patients be directed to the web portal in the interim?**
If web submission still works for patients (web uses server actions that bypass
the removed RLS policies), the message could add: "You can submit documents
through the web portal." Confirm whether web patient submission is functional
before adding that line — do not send patients to a second broken path.

---

## Acceptance (mobile device check)

1. Patient attempts to open a new template form -> persistent unavailable state;
   no new form entry and no network write. An already-open form cannot submit
   through its provider/repository boundary and is not cleared by the guard.
2. Patient opens upload flow → captures/selects a file → same containment, no
   write attempted.
3. Existing persisted upload queue rows, identifiers, owner associations and files
   survive restart without sync or deletion. New template entry is prevented;
   template persistence is not part of this containment proposal. Do not imply
   existing unsaved form values were durably saved.
4. Previously submitted documents still viewable; status tracking works.
5. Mocked network tests prove zero submission writes, including Storage writes,
   from all three paths and both lifecycle sync triggers; no production write
   tests for this documentation task. No false success on network fallback.
6. Staff/admin document flows unaffected.

---

## Exit criteria

Containment is lifted only when:
- The `patient-document-submission` Edge Function is deployed and verified by its
  owner (web/shared backend team),
- The mobile adapter is built, reviewed, and Gate D passed, and
- A reconciliation path for drafts accumulated during containment is defined.

Re-enable review must resolve each queued item under its original owner, preserve
stable retry identity, reconcile possible prior remote commits before retry,
and account for web PR #116 pending-only Storage paths and PR #106 assessment
consumption. Do not bulk replay or bulk-delete historical objects. Unknown
outcomes remain held for owner-approved reconciliation. Viewing/tracking stays
available under its existing authorization.

Containment is not lifted by the Edge Function existing — it's lifted by the
full Phase 2 path being verified end to end.
