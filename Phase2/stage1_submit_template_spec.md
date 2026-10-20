# Stage 1 Spec — `submit_template` Edge Function

**Status:** DRAFT for backend owner review. Not approved, not implemented.
**Date:** 2026-10-20
**Scope:** Template submission only. Upload path is Stage 2.
**Ownership:** Backend owner (`@Setsuna-guwah`) retains contract authority,
deployment, rollback, and maintenance. Mobile may contribute source and tests
for review; contribution is not deployment permission.

---

## 1. Why Stage 1 exists separately

Patient document submission is broken on prod at two independent points:

1. **Storage** — patient writes narrowed to `<user>/pending-submissions/`
   (PR #116 / migration 36). Mobile uploads to `<user>/<uuid>_<filename>`.
   Confirmed live; device shows
   `StorageException(message: new row violates row-level security policy,
   statusCode: 403, error: Unauthorized)`.
2. **Insert** — patient INSERT policy on `documents` removed (PR #76 /
   migration 23).

Template submission involves **no file and no Storage**. It is blocked only by
(2). That makes it separable and substantially smaller than the full contract —
no assessment binding, no expiry, no OCR, no test-selection acknowledgement, no
orphaned-file cleanup.

Stage 1 restores the six structured forms. Upload submission remains contained
until Stage 2.

---

## 2. Reference baseline — IMPORTANT

**Web's current template flow is authoritative.** Mobile's template catalog and
field schemas were ported from web at an earlier baseline (`a9460ce`) and have
since been affected by:

- `0d61ea8` / PR #102 — shared template validation now includes length/date
  bounds and stored-answer review; declined form consent can be stored and
  flagged for reception, distinct from the account privacy gate.
- `58d3098` / PR #113 — demographic/notes bounds changed.
- `f16575a` / PR #99 — requestable laboratory coverage changed.

Mobile's ported definitions must be treated as **stale until reconciled**. Do
not finalize this contract against mobile's copy. Decisions 1 and 2 below exist
to pin the authoritative definitions.

---

## 3. Operation contract

### Request

```
POST /functions/v1/submit-template
Authorization: Bearer <user JWT>
Content-Type: application/json

{
  "request_id":  "<client-generated stable UUID>",
  "template_id": "<one of the allowed template ids>",
  "fields":      { "<field_key>": "<value>", ... }
}
```

**Unknown top-level keys and unknown field keys are rejected**, not ignored.
Silent ignoring hides client/server drift.

### Server-derived — client values rejected, not overwritten

| Column | Derived from |
|---|---|
| `patient_id` | `patients.id` where `profile_id = auth.uid()` |
| `uploader_id` | `auth.uid()` |
| `status` | `'pending'` |
| `file_type` | `'template'` |
| `file_name` | server-formatted from template name + date |
| `file_path` | server-formatted `template://<template_id>-<timestamp>` |
| `extracted_metadata.submitted_at` | server clock |
| `extracted_metadata.patient_name` | from the patient record |

If the request body contains any of these, **reject with 400**. Rejecting
rather than ignoring surfaces a mismatched client immediately.

> **Note on `patient_id`:** it is the `patients` row id, resolved via
> `profile_id = auth.uid()` — **not** `auth.uid()` itself. This exact confusion
> was a live bug in mobile's provisioning path. Worth an explicit assertion in
> the function.

### Response — success

```
200 OK
{
  "document_id": "<uuid>",
  "status": "pending",
  "replayed": false          // true when returning an existing document
}
```

### Response — error

```
4xx / 5xx
{
  "error_code": "<stable machine-readable code>",
  "message": "<human-readable, safe to log>"
}
```

Codes must be stable and distinguishable so mobile can route to the correct
remediation rather than showing a generic failure. Proposed set in §8.

---

## 4. Account-state preconditions (server-enforced, every call including replays)

| Precondition | Proposed error code |
|---|---|
| Valid JWT | `UNAUTHENTICATED` |
| Patient record exists for this profile | `NO_PATIENT_RECORD` |
| Profile active | `PROFILE_INACTIVE` |
| Email confirmed | `EMAIL_NOT_CONFIRMED` |
| Privacy consent accepted | `CONSENT_REQUIRED` |
| `must_change_password` not set | `PASSWORD_CHANGE_REQUIRED` |

Each must be distinguishable. A single generic `FORBIDDEN` forces mobile to
show an unhelpful error for six different remediable states.

`NO_PATIENT_RECORD` matters specifically: mobile previously shipped a bug where
accounts existed in `auth.users` + `profiles` with no `patients` row. That is
fixed, but the function should fail loudly rather than insert with a null
`patient_id`.

---

## 5. The four validation decisions

These require the backend owner's answer before implementation.

### Decision 1 — Template catalog and field schema authority

**Question:** Where does the authoritative list of valid `template_id` values
and their field schemas live, and how does the function read it?

Options:
- **(a)** Hard-coded inside the Edge Function
- **(b)** A database table the function reads
- **(c)** A shared constants module web and the function both import

**Mobile's position:** (b) or (c). Option (a) creates a third copy of the
schema (web constants, mobile Dart, function) that will drift — exactly what
happened between `a9460ce` and now. If (c), name the module and its version
pin. If (b), name the table.

**Also needs confirming:** the current six template ids. Mobile has
`referral-form`, `lab-request`, `med-cert`, `procedure-consent`,
`patient-intake`, `results-release`. Confirm this set is unchanged after
PR #99/#102/#113.

### Decision 2 — Field value bounds

**Question:** What are the exact per-field constraints the function enforces?

PR #102 added length/date bounds; PR #113 changed demographic/notes bounds.
Mobile currently enforces only "required field non-empty, non-whitespace."

Needed per field:
- Max length (text and textarea — likely different)
- Date bounds (past-only? future-only? max range? `referral_date` and
  `date_needed` plausibly differ)
- Select values — the exact allowed option set per select field
- Whether the server trims, normalizes, or rejects on leading/trailing
  whitespace

**Mobile's position:** server is authoritative and rejects; mobile mirrors the
same bounds client-side purely as UX so the patient sees the problem before
submitting. Mobile will not invent bounds — it needs the values.

### Decision 3 — Patient-intake age rule

**Question:** Is the 18+ rule on `patient-intake` server-enforced, and what is
the error code?

Mobile currently enforces 18+ client-side for `patient-intake` only, computed
against Philippine time (UTC+8) from the patient's date of birth. Registration
uses 13+; these are deliberately different thresholds.

**Mobile's position:** enforce server-side with a distinct code
(`AGE_REQUIREMENT_NOT_MET`). A client-only clinical eligibility rule is
bypassable. Confirm the threshold, the timezone basis, and whether it applies
to any template other than `patient-intake`.

### Decision 4 — Business duplicate rule for templates

**Question:** What constitutes a duplicate template submission, and how is it
enforced atomically?

Mobile currently enforces **one pending document per category per patient**,
client-side, cross-method (a pending lab-request template blocks a lab-request
upload and vice versa). A client-side check cannot be atomic across web and
mobile submitting concurrently.

Needed:
- Is the rule one-pending-per-template-id, or per broader category?
- Does it span templates and uploads (cross-method), matching mobile's current
  behavior?
- Mechanism: transactional check inside the function, or a partial unique index
  on `(patient_id, category) WHERE status = 'pending'`?
- Error code on rejection, and does the response include the existing
  document's id so mobile can point the patient at it?

**Mobile's position:** server-side and atomic. Mobile keeps its client-side
check as UX (fail fast, better message) but stops treating it as the guarantee.

### Also needs confirming (not blocking, but affects the contract)

PR #102's **declined form consent** — stored and flagged for reception,
distinct from the account privacy gate. Does `submit_template` accept a
form-level consent value in `fields`, and does declining block submission or
submit-with-flag? If the latter, which field carries it.

---

## 6. `extracted_metadata` shape

Mobile currently writes, and web currently reads:

```json
{
  "template_id":       "<id>",
  "template_name":     "<name>",
  "submission_type":   "template",
  "submitted_at":      "<ISO8601 UTC>",
  "patient_name":      "<full name>",
  "<field_key>":       "<value>"
}
```

`patient-intake` additionally carries `date_of_birth`, `contact_number`,
`address`, injected from the patient record. Other templates do not.

**Decision needed:** the function now owns this shape. Confirm it is unchanged,
and that the function — not the client — performs the `patient-intake`
injection. Mobile should stop injecting them once the function does.

Byte-parity matters here: web reception renders directly from
`extracted_metadata.selected_tests` and the template fields. A shape change
breaks reception display for existing documents.

---

## 7. Idempotency and retry

**Key:** `request_id`, scoped to `(user_id, operation)`.

- Mobile generates a stable UUID **when the draft is created**, persists it with
  the draft, and reuses it across every retry of that submission.
- Mobile does **not** generate a new id on retry. A new id is a new submission
  by definition.
- Successful replay returns the **same** `document_id` with `"replayed": true`.
  No second insert, no second audit event.
- Same `request_id` with **different normalized content** → `409
  IDEMPOTENCY_CONFLICT`. This catches a client that mutated the draft and
  retried with a stale id.
- **In-progress** handling: a second call with the same `request_id` while the
  first is still executing must not double-insert. Either block until the first
  resolves and return its result, or return a distinguishable `IN_PROGRESS`
  that mobile treats as "do not retry yet."

**Decision needed:** retention window for `request_id`. Mobile's retry policy
must stay inside it. Beyond the window, a replay would create a second
document — so mobile needs the number to cap its retry horizon and to decide
when a queued draft becomes "must reconcile manually" rather than "safe to
retry."

**Ambiguous timeout:** mobile cannot distinguish "never arrived" from
"committed but response lost." Mobile's rule: retry with the same `request_id`
(safe by idempotency), and if still unresolved, surface
"could not be confirmed — refresh before retrying" rather than claiming either
outcome. No automatic replay without reconciliation.

---

## 8. Error codes (proposed)

| Code | HTTP | Mobile remediation |
|---|---|---|
| `UNAUTHENTICATED` | 401 | Re-authenticate |
| `NO_PATIENT_RECORD` | 403 | Contact clinic — account incomplete |
| `PROFILE_INACTIVE` | 403 | Contact clinic |
| `EMAIL_NOT_CONFIRMED` | 403 | Route to verification |
| `CONSENT_REQUIRED` | 403 | Route to consent |
| `PASSWORD_CHANGE_REQUIRED` | 403 | Route to password change |
| `UNKNOWN_TEMPLATE` | 400 | Client out of date — prompt update |
| `UNKNOWN_FIELD` | 400 | Client out of date — prompt update |
| `FIELD_REQUIRED` | 400 | Highlight field |
| `FIELD_INVALID` | 400 | Highlight field with reason |
| `AGE_REQUIREMENT_NOT_MET` | 403 | Explain eligibility |
| `DUPLICATE_PENDING` | 409 | Point at existing pending document |
| `IDEMPOTENCY_CONFLICT` | 409 | Do not retry; surface for reconciliation |
| `IN_PROGRESS` | 409 | Wait, do not retry yet |
| `SERVER_ERROR` | 5xx | Retry with same `request_id` |

`FIELD_REQUIRED` / `FIELD_INVALID` should identify the offending field key so
mobile can highlight it rather than showing a form-level error.

---

## 9. Audit

- Exactly one attributed `DOCUMENT_SUBMITTED` event per **new** document.
- Idempotent replay emits **no** event.
- **Decision needed:** audit-failure recovery. If the document commits and the
  audit write fails — roll back the submission, or commit and reconcile the
  audit gap separately? Mobile has no visibility either way; this is purely a
  backend behavior to state.

---

## 10. Mobile adapter responsibilities (Stage 1)

- Replace the direct `documents` insert in `templates_repository.dart:42` with
  a call to the function. Remove the direct insert path entirely.
- Generate and persist `request_id` at draft creation; reuse across retries.
- Never send `patient_id`, `uploader_id`, `status`, `file_type`, `file_name`,
  `file_path`, or `submitted_at`.
- Stop injecting `patient-intake` demographics once the function does.
- Map every error code in §8 to its specific remediation.
- Mirror server field bounds client-side as UX only, once Decision 2 lands.
- Keep the client-side duplicate check as fail-fast UX; treat the server as the
  guarantee.
- Lift containment for the template path only; upload path stays contained.

**Not in Stage 1:** storage path change, assessment, test selection, offline
upload replay. All Stage 2.

---

## 11. Test matrix

### Backend (fixtures disposable, no production patient data)

| Scenario | Expected |
|---|---|
| Valid submit, each of the six templates | 201/200, document created, `status=pending`, one audit event |
| Replay, same `request_id`, same content | Same `document_id`, `replayed: true`, no second insert, no second audit event |
| Replay, same `request_id`, different content | 409 `IDEMPOTENCY_CONFLICT` |
| Concurrent calls, same `request_id` | Exactly one document; second returns replay or `IN_PROGRESS` |
| Concurrent duplicate across web + mobile | Exactly one pending document for the category |
| Client sends `patient_id` | 400, rejected not ignored |
| Client sends `status: 'approved'` | 400, rejected not ignored |
| Unknown `template_id` | 400 `UNKNOWN_TEMPLATE` |
| Unknown field key | 400 `UNKNOWN_FIELD` |
| Required field empty / whitespace-only | 400 `FIELD_REQUIRED`, field identified |
| Field over max length | 400 `FIELD_INVALID` |
| Date outside bounds | 400 `FIELD_INVALID` |
| Select value not in allowed set | 400 `FIELD_INVALID` |
| `patient-intake`, patient under 18 | 403 `AGE_REQUIREMENT_NOT_MET` |
| Unconfirmed email | 403 `EMAIL_NOT_CONFIRMED` |
| Consent not accepted | 403 `CONSENT_REQUIRED` |
| `must_change_password` set | 403 `PASSWORD_CHANGE_REQUIRED` |
| Inactive profile | 403 `PROFILE_INACTIVE` |
| Authenticated user with no `patients` row | 403 `NO_PATIENT_RECORD`, no insert with null `patient_id` |
| Second pending of same category | 409 `DUPLICATE_PENDING` |
| `patient-intake` metadata | `date_of_birth`, `contact_number`, `address` injected by server |
| Non-intake template metadata | Those three fields absent |
| Replay beyond retention window | Behavior defined and documented (second document, or rejection) |

### Mobile (fully mocked — no live Supabase initialization)

| Scenario | Expected |
|---|---|
| Successful submit | Function invoked with correct body; no direct `documents` insert |
| Request body contents | Contains only `request_id`, `template_id`, `fields` |
| Retry after failure | Same `request_id` reused, not regenerated |
| Replay response (`replayed: true`) | Treated as success, no duplicate shown in UI |
| Each error code in §8 | Routes to its specific remediation, not a generic error |
| `IDEMPOTENCY_CONFLICT` | Surfaces for reconciliation, does not auto-retry |
| Ambiguous timeout | "Could not be confirmed, refresh before retrying"; no false success |
| `extracted_metadata` parity | Server-built metadata renders correctly in mobile reception |

Mobile tests must be inspected for live connections before running — per the
test incident documented in the overnight-queue walkthrough, a legacy suite
performed a live signup against production.

---

## 12. Stage 2 scope (noted, not specified here)

Per the backend owner's requirement, Stage 2 must cover **both** paths:

- **Online upload** — `assess_upload` + `submit_upload`, plus mobile's storage
  path change to `<user>/pending-submissions/`. These ship **together**: fixing
  the storage path alone would upload files that then orphan when the insert
  fails.
- **Offline synchronization** — mobile's offline replay path
  (`document_submission_provider.dart:352`, insert at 407) re-uploads a queued
  file and inserts. It is a distinct execution path from the online upload and
  needs explicit treatment: stable `request_id` persisted with the queued item,
  reconciliation of items queued during containment, and no bulk automatic
  replay on restore.

Open items carried into Stage 2: assessment expiry and consumption, storage
staging paths, PR #117 zero-detection acknowledgement field, orphaned-file
cleanup ownership, and reuse of the existing service-role
`submit_assessed_document` primitive (PR #106 / migration 34) rather than
inventing a competing one.

---

## 13. What mobile needs to proceed

1. Answers to Decisions 1–4 (§5)
2. Confirmation of the `extracted_metadata` shape and who injects intake
   demographics (§6)
3. Idempotency retention window (§7)
4. Audit-failure behavior (§9)
5. Agreement on the error-code set, or a replacement set (§8)
6. A reachable environment with the function deployed

Mobile can draft the function source and tests for review in parallel with 1–5,
but cannot finalize the adapter until the contract is fixed and the function is
reachable.
