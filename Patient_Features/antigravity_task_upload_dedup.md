# SPEC — Upload Optimization: One Pending Document Per Type (Dedup)

> **Type:** NEW optimization on the patient submission flow (both photo/PDF
> uploads AND structured templates). Addresses panelist feedback: "require users
> to upload their lab requests only once."
> **Rule:** a patient may have at most **one `pending` document per document
> type** at a time. Attempting a second same-type submission (by upload OR
> template) is blocked until the first is reviewed (approved/rejected).
>
> **⚠️ Standing rules: Trim testing budget, all Supabase/auth MOCKED, terse
> pass/fail, no images.**
> **⚠️ No new native deps → release build not required (state it), unless
> pubspec/manifest ends up touched.**

---

## Canonical document types (reuse — do NOT redefine)

Reuse the 6 categories already defined in `document_templates.dart` (PT1):
`referral-form`, `lab-request`, `med-cert`, `procedure-consent`,
`patient-intake`, `results-release`. Add one upload-only value **`other`** for
photos/PDFs that don't fit a category. **`other` is EXEMPT from the once-rule**
(patients can upload multiple misc docs freely).

Single source of truth for the category list — reference the existing template
config, do not duplicate the list (Constraint #13 discipline).

---

## Part 1 — Upload flow: capture the document type

The photo/PDF upload path currently stores `file_type = PNG/PDF` with **no
document category** — that's why upload duplicates are invisible today. Fix:

- Add a **required "Document Type" picker** to the upload flow (the 6 categories
  + "Other"), shown on the review/submit step (after capture + the OCR quality
  gate, before final submit).
- Store the chosen type as **`extracted_metadata.document_type`** on the upload's
  `documents` row. No new DB column — `extracted_metadata` (jsonb) already
  exists on uploads (it holds OCR output).
- Templates already carry their category via `extracted_metadata.template_id` —
  do NOT modify template submission payloads (preserve the mobile↔web template
  byte-parity from PT1).

## Part 2 — Category resolver (uniform read)

A small shared helper resolves any `documents` row to a canonical category:
- `file_type == 'template'` → category = `extracted_metadata.template_id`
- else (upload) → category = `extracted_metadata.document_type` (or `other` /
  null if unset on legacy rows)

Legacy uploads with no `document_type` → treat as `other` (unclassifiable →
never block; they predate the rule).

## Part 3 — Dedup check (pre-submit, both paths)

Before inserting ANY new submission (upload or template) for patient P with
category C:
1. If `C == other` → skip the check, allow.
2. Query P's `documents` where `status = 'pending'`; resolve each to its
   category via Part 2.
3. If any pending doc resolves to `C` → **BLOCK** the submit. Do NOT insert.
   Show: *"You already have a pending [Laboratory Request] submitted on
   [date]. You can submit a new one once it's reviewed."* Offer a button to
   view the existing pending submission if that screen exists.
4. Else → proceed with the insert.

- Only `pending` blocks. Approved/rejected same-type docs do NOT block → after
  review, the patient may submit that type again. (Matches "one at a time.")
- Cross-method: a pending lab-request **template** blocks a lab-request
  **upload**, and vice-versa. Same category = blocked regardless of method.
- Hard block (panelist said "require"), not a soft warning.

Put the check in a shared place used by BOTH the upload submit and the template
submit (the templates repository from PT1 + the upload repository) — one dedup
helper, not two.

---

## Scope / caveats to document (not blockers)

- **Shared DB:** this is a mobile client-side guard → it stops MOBILE duplicates.
  A web patient could still create one. True cross-platform "once" needs a
  DB-level rule (a partial unique index on patient + resolved-type WHERE
  status='pending'), which requires a generated column/trigger and **web-team
  coordination** since the DB is shared. Note this in the walkthrough as the
  "complete" path; the mobile guard is the scoped deliverable that demonstrates
  the optimization and answers the panelist.
- **Race condition:** two near-simultaneous submits could both pass the check
  before either inserts. Acceptable for the client-side guard; the DB-level rule
  above is the definitive fix. Note it, don't over-engineer a client lock.
- **Existing queue dupes** (the ~167 pending, repeated files) predate the rule —
  it's preventive, not retroactive. Clear test dupes separately if desired.

---

## Tests (Trim — mocked)

- **Unit — category resolver:** template row → `template_id`; upload row →
  `document_type`; legacy upload (no key) → `other`.
- **Unit — dedup logic (the guard):** patient with a pending `lab-request`
  (template) → a new `lab-request` (upload OR template) is BLOCKED; a new
  `referral-form` is ALLOWED; if the pending one is approved/rejected, a new
  `lab-request` is ALLOWED; `other` uploads never blocked.
- **Widget — upload:** Document Type picker is required; submitting a duplicate
  type shows the block message and performs NO insert; a new type inserts with
  `document_type` written into `extracted_metadata`.
- **Regression:** a normal (non-duplicate) upload and a normal template submit
  still succeed. Mock Supabase throughout.

## Verification (real device)

1. Upload a lab-request photo → pick type "Laboratory Request" → submits;
   confirm `document_type` is stored.
2. Try a second Laboratory Request while the first is pending — by **upload**
   AND by **template** → both blocked with the message, nothing inserted.
3. Submit a Referral while the lab request is pending → allowed (different type).
4. Approve or reject the pending lab request → a new lab request is now allowed.
5. An "Other" upload is never blocked.
6. Full suite green. No secret surface / no deps changed — state APK grep N/A,
   release build not required.

## Files affected (expected)

**New:**
- shared dedup helper + category resolver (e.g. `lib/features/patient/
  submissions/document_dedup.dart`)
- test additions

**Modified:**
- upload flow screen (add Document Type picker; write `document_type`)
- upload submit repository + templates repository (call the shared dedup check
  before insert)

**Reused:** the 6-category list from `document_templates.dart`.

No schema changes. No template-payload changes. No service-role. No new features
beyond the dedup guard + upload type picker.
