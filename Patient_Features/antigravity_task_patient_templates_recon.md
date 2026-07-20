# Antigravity Task — Recon: Web Patient Template Module (READ-ONLY)

> **Type:** read-only reconnaissance to gather the facts needed to SPEC a mobile
> port of the patient "Document Templates" (Structured Document Template Module).
> NOT a build. No code changes. Output one input doc.
>
> **⚠️ Read-only. No writes/branches/commits/push to the web repo.**
> **⚠️ No secrets: never copy `.env`, keys, or the real Supabase project ref
> into any artifact — placeholders only.**
> **⚠️ Surface pass on structure, but go DEEP enough on the data model + RLS +
> template field definitions to write a mobile SPEC from. No images.**

## Repo
Web team repo `Setsuna-guwah/KlinikAid` (Next.js), read-only. Ask Ralph if the
access path differs.

## The feature (context)
Patient side has a "Document Templates" picker → 6 structured forms: **Referral
Form, Laboratory Request, Medical Certificate Request, Consent Form, Patient
Intake Form, Results Release Authorization**. Each auto-fills patient identity
(read-only), has required/optional structured fields, validates before submit,
and "Submit to Reception" routes a structured-form record to the reception
queue tagged "Structured Form" — **no file upload, no OCR, no AI validation**
(per the module's own footer). Receptionist then sees parsed fields (100%
validated, no image) and approves/routes or rejects.

## What to extract (this is SPEC input — be precise)

### 1. Submission data model
- Which **table** does a submitted template write to? (Likely the same
  documents/uploads/submissions table the reception queue reads.) Full column
  list.
- How are the **structured field values** stored? One JSON/JSONB column
  (`structured_data`?), or discrete columns? Give the exact shape/key names for
  at least one submitted template.
- The **type discriminator** that marks a row as a structured template vs a
  file upload (e.g. `file_type = 'TEMPLATE'` / `source = 'structured_form'`).
  Exact field + value.
- Status field + initial value on submit (e.g. `pending_review`).
- Patient linkage (`patient_id` / `uploaded_by`) and any `template_type` field.

### 2. Template field definitions
- Where in web code are the **6 templates' field schemas** defined (a config/
  constants file, or per-form components)? For EACH template, list: field label,
  key, input type (text / textarea / select / date), required?, and select
  options where applicable. This is the spec for the mobile forms — capture all
  6 fully.
- Which identity fields are **auto-filled** from the patient profile (Full Name,
  DOB, Contact Number, Address — confirm exact source columns).
- Client-side **validation rules** enforced before submit.

### 3. RLS (the write-path gate)
- The **RLS policy** on the submission table for **patient INSERT**: can a
  patient insert their own structured-form row? Which columns are they allowed
  to set? Quote the relevant policy from `schema.sql` (redact any project ref).
- Confirm NO service-role / server action is involved in submit (verify the
  footer's claim in code — pure client insert vs a server route).

### 4. Reception-side handling (the risk)
- How does the reception queue **distinguish and render** a structured-form row
  vs a file-upload row? (The "Structured Form" tag + the no-image validation
  view in image 10.)
- What does the receptionist document-validation screen do when `file_type =
  TEMPLATE` / there is no image — does it skip OCR, show the structured fields
  directly, mark "100% validated"?

## Output — `PATIENT_TEMPLATES_SPEC_INPUT.md` (mobile repo)
Concise but complete:
- Submission table + columns + structured_data shape + type/status discriminators
- All 6 template field schemas (label/key/type/required/options)
- Identity auto-fill source columns
- Patient-INSERT RLS policy (quoted, redacted) + confirmation submit is
  service-role-free
- Reception rendering logic for structured forms (+ note whether mobile
  reception likely already needs a companion fix to render no-image TEMPLATE
  rows)
- Redaction confirmation line

Keep it tight — this is the fact base for the mobile SPEC, not a re-doc of the
web app. Do NOT start building anything.
