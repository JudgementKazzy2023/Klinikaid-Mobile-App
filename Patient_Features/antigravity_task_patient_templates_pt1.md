# SPEC — PT1: Patient Document Templates (Submit Side)

> **Type:** NEW feature on the mobile patient portal — the Structured Document
> Template Module (submit side). First patient WRITE path on mobile.
> **Goal:** patient picks one of 6 templates → fills a structured form (identity
> auto-filled) → validates → submits → a `documents` row (`file_type='template'`)
> lands in the shared reception queue, byte-parity with web.
>
> **⚠️ Standing rules: Trim testing budget, all Supabase/auth MOCKED in tests,
> terse pass/fail, no images/mockups.**
> **⚠️ New native deps unlikely (date picker is built-in). IF pubspec/manifest/
> native is touched → `flutter build apk --release` is part of Gate D.**

---

## Architecture — data-driven, mirror web (`src/lib/documentTemplates.ts`)

Do NOT hand-code 6 screens. Build:
1. **One template config** (`lib/features/patient/templates/document_templates.dart`)
   — the 6 templates + field defs, mirrored from web. Single source of truth.
2. **One generic form renderer** that builds the form from a template's field
   list (text / textarea / select / date), plus a read-only identity header.
3. A **picker** that lists the 6 and routes into the renderer.

## Part 1 — Template config (mirror web exactly)

Each template: `id`, `name`, `description`, `fields[]` where a field =
`{key, label, type(text|textarea|select|date), required, options?}`.

| id | name | fields (key:type, *=required) |
|----|------|-------------------------------|
| `referral-form` | Referral Form | `referring_physician:text*`, `referring_clinic:text`, `reason_for_referral:textarea*`, `requested_service:select*` [Laboratory, Imaging, Ultrasound, ECG], `referral_date:date*` |
| `lab-request` | Laboratory Request | `ordering_physician:text*`, `tests_requested:textarea*`, `fasting_required:select` [Yes, No], `request_date:date*` |
| `med-cert` | Medical Certificate Request | `purpose:textarea*`, `date_needed:date*` |
| `procedure-consent` | Consent Form | `procedure:text*`, `consent_given:select*` [Yes, No], `consent_date:date*` |
| `patient-intake` | Patient Intake Form | `chief_complaint:textarea*` (+ special injection, see below) |
| `results-release` | Results Release Authorization | `release_to:text*`, `results_type:text*`, `authorization_date:date*` |

Labels/options must match web strings exactly (recon has them verbatim).

## Part 2 — Picker screen
Grid of the 6 templates (name + description), tap → renderer for that template.
Add a **"Document Templates" entry to the patient portal navigation.**

## Part 3 — Generic form renderer
- **Identity header (read-only)** — Full Name (`${first_name} ${last_name}`),
  DOB, Contact Number, Address, from the patient's own `patients` row
  (`patients` where `profile_id = auth.uid()`). Display only, non-editable.
- **Dynamic fields** from config: text/textarea → `TextField`; select →
  dropdown with options; date → date picker.
- **Validation before submit:** every `required` field non-empty /
  non-whitespace; select must have a chosen option; block submit + inline
  errors + summary SnackBar (reuse the submit-gating discipline from S2/D2 —
  wire the block into the actual submit path, not visual-only).
- **`patient-intake` special rule:** patient must be **18+** (DOB vs Manila
  UTC+8). Reuse the DOB/age util from registration but with an **18** threshold
  (registration is 13 — do NOT reuse the 13 constant). Block submit if under 18.

## Part 4 — Submit path (byte-parity is critical)

On submit, INSERT one row into `public.documents` with EXACTLY:
- `patient_id` = the patient's `patients.id` (resolve via `patients` where
  `profile_id = auth.uid()` — **NOT** `auth.uid()` itself; common bug).
- `uploader_id` = `auth.uid()` (RLS `WITH CHECK` requires this).
- `file_name` = `"${templateName} - ${formattedDate}"` (e.g. `Referral Form -
  Jul 14, 2026`).
- `file_path` = `"template://${templateId}-${timestampMs}"`.
- `file_type` = `'template'` (exact lowercase).
- `status` = `'pending'`.
- `extracted_metadata` (jsonb) = the payload below.

**`extracted_metadata` must byte-match web's shape** — same keys, or
mobile-submitted forms won't render on WEB reception (and vice versa):
```json
{
  "template_id": "<id>",
  "template_name": "<name>",
  "submission_type": "template",
  "submitted_at": "<ISO8601 UTC>",
  "patient_name": "<Full Name>",
  "<field_key>": "<value>", ...
}
```
- **`patient-intake` ONLY:** also inject `date_of_birth`, `contact_number`,
  `address` into the metadata (web's server injects these; mobile has no server,
  so the CLIENT injects them from the `patients` row). Other templates do NOT
  get these.
- Success → confirmation + return to portal/picker. Failure → error, no false
  success (the CSV-toast lesson).

---

## Investigate first (strike 1)
1. Confirm patient RLS allows SELECT on the patient's OWN `patients` row (for
   identity auto-fill). If not, resolve how web reads it.
2. Confirm the mobile patient portal has a nav surface to add the "Document
   Templates" entry to.
3. **Check mobile reception NOW:** web patients may already have submitted
   templates → `file_type='template'` rows are already in the shared
   `documents` queue. Open the mobile receptionist queue/validation screen —
   does it crash or mis-render on a template (no-image) row TODAY? Report
   findings; this scopes PT2 (below) and may be a live bug independent of PT1.

## Tests (Trim — mocked)
- **Unit:** template config integrity (6 templates present, required fields
  flagged, select options correct).
- **Unit (byte-parity guard):** metadata builder for one template (e.g.
  referral) produces the exact web key set + `submission_type='template'`; and
  `patient-intake` injects `date_of_birth`/`contact_number`/`address` while
  others do not. This is the regression guard.
- **Widget:** required-field validation blocks submit; a valid form calls
  `documents` INSERT with the exact columns (`file_type='template'`,
  `status='pending'`, `uploader_id=auth.uid()`, resolved `patient_id`). Mock
  Supabase.
- **Unit:** `patient-intake` under-18 blocked; 18+ passes.

## Verification (real device)
1. Patient portal → Document Templates → pick each of the 6 → identity
   auto-filled read-only.
2. Required validation blocks empty submit; intake blocks under-18.
3. Submit → success → the row appears in the **reception queue tagged
   "Structured Form"** (web or mobile reception).
4. Open the submitted row's `extracted_metadata` (or the web reception view) →
   keys/values match web-submitted forms.
5. Full suite green. No secret surface changed (state APK grep N/A) unless deps
   changed → then release-build.

---

## Required companion — PT2: Reception render (separate brief, spec next)

For the feature to work end-to-end on mobile, the receptionist queue +
document-validation screen must handle `file_type='template'`: skip image
download + OCR, render `extracted_metadata` fields directly, disable "View
Original" → "Structured Form (No Image)", show the validated panel, keep
approve/route + reject working. Web already does this.

**Likely already a live bug:** if web templates are in the shared `documents`
queue now, mobile reception may already break on them — see investigate step 3.
PT2 gets its own SPEC after the strike-1 findings; if mobile reception already
mis-renders, PT2 may jump ahead of PT1.

## Constraint note (for the doc later, not this build)
This is the **first patient WRITE on mobile** — RLS-governed, limited to the
patient's own `documents` rows while `pending`, no service-role. Consistent with
the security model (anon key + user JWT). Flag for a constraint update at the
next docs pass (extend #12's role coverage or a new patient-write constraint).

## Files affected (expected)
**New:** `document_templates.dart` (config), picker screen, generic form
renderer, submit/repository method, tests.
**Modified:** patient portal navigation (add entry).
No schema changes. No service-role. No secret handling.
