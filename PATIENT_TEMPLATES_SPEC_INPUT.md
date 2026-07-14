# Patient Templates Spec Input (Reconnaissance Output)

This document provides the extracted facts from the Next.js web application regarding the **Structured Document Template Module** to guide the mobile app port.

## 1. Submission Data Model

- **Table Written:** `public.documents`
- **Columns Set on Insert:**
  - `patient_id` (uuid): The patient's database record UUID (obtained from the `patients` table where `profile_id = auth.uid()`).
  - `uploader_id` (uuid): The current authenticated user's ID (`auth.uid()`).
  - `file_name` (text): Formatted as `${templateName} - ${formattedDate}` (e.g. `Referral Form - Jul 14, 2026`).
  - `file_path` (text): Formatted as `template://${templateId}-${timestamp}` (e.g. `template://referral-form-1718919012345`).
  - `file_type` (text): Set to the exact lowercase string `'template'`.
  - `status` (text): Initialized to `'pending'`.
  - `extracted_metadata` (jsonb): Houses the structured form values and metadata payload.

### `extracted_metadata` Payload Structure
All templates store fields as key-value string pairs in `extracted_metadata`, alongside injected fields:
```json
{
  "template_id": "referral-form",
  "template_name": "Referral Form",
  "submission_type": "template",
  "submitted_at": "2026-07-14T00:10:35.000Z",
  "patient_name": "John Doe",
  "referring_physician": "Dr. Smith",
  "referring_clinic": "Central Health",
  "reason_for_referral": "Persistent back pain evaluation.",
  "requested_service": "Imaging",
  "referral_date": "2026-07-14"
}
```
*Note: For the `patient-intake` template only, the server also injects the following fields from the patient profile into the metadata:*
- `date_of_birth` (date string)
- `contact_number` (text)
- `address` (text)

- **Type Discriminator:**
  - `file_type = 'template'`
  - `extracted_metadata.submission_type = 'template'`
- **Status Field:** `status` with initial value `'pending'`.

---

## 2. Template Field Definitions

The 6 templates and their fields are defined in Next.js at `src/lib/documentTemplates.ts`.

### 1. Referral Form (`referral-form`)
- **Description:** Submit doctor recommendations and requests for clinic services.
- **Fields:**
  - `referring_physician` (Label: "Referring Physician", Type: `text`, Required: `true`)
  - `referring_clinic` (Label: "Referring Clinic / Hospital", Type: `text`, Required: `false`)
  - `reason_for_referral` (Label: "Reason for Referral", Type: `textarea`, Required: `true`)
  - `requested_service` (Label: "Requested Service", Type: `select`, Required: `true`, Options: `["Laboratory", "Imaging", "Ultrasound", "ECG"]`)
  - `referral_date` (Label: "Referral Date", Type: `date`, Required: `true`)

### 2. Laboratory Request (`lab-request`)
- **Description:** Submit request forms for specific blood and urine diagnostic tests.
- **Fields:**
  - `ordering_physician` (Label: "Ordering Physician", Type: `text`, Required: `true`)
  - `tests_requested` (Label: "Tests Requested", Type: `textarea`, Required: `true`)
  - `fasting_required` (Label: "Fasting Required?", Type: `select`, Required: `false`, Options: `["Yes", "No"]`)
  - `request_date` (Label: "Request Date", Type: `date`, Required: `true`)

### 3. Medical Certificate Request (`med-cert`)
- **Description:** Request official health certifications for school or work clearances.
- **Fields:**
  - `purpose` (Label: "Purpose of Certificate", Type: `textarea`, Required: `true`)
  - `date_needed` (Label: "Date Needed", Type: `date`, Required: `true`)

### 4. Consent Form (`procedure-consent`)
- **Description:** Acknowledge and consent to clinical laboratory diagnostic operations.
- **Fields:**
  - `procedure` (Label: "Clinical Procedure", Type: `text`, Required: `true`)
  - `consent_given` (Label: "I Give My Consent?", Type: `select`, Required: `true`, Options: `["Yes", "No"]`)
  - `consent_date` (Label: "Date of Consent", Type: `date`, Required: `true`)

### 5. Patient Intake Form (`patient-intake`)
- **Description:** Submit basic demographics and complaints before visiting the clinic.
- **Fields:**
  - `chief_complaint` (Label: "Chief Health Complaint", Type: `textarea`, Required: `true`)
  - *Prefilled fields injected from Patient Profile:* Full Name, Date of Birth, Contact Number, Address.

### 6. Results Release Authorization (`results-release`)
- **Description:** Authorize third-party release or sharing of diagnostic lab results.
- **Fields:**
  - `release_to` (Label: "Authorize Release To (Name)", Type: `text`, Required: `true`)
  - `results_type` (Label: "Clinical Results Authorized for Release", Type: `text`, Required: `true`)
  - `authorization_date` (Label: "Authorization Date", Type: `date`, Required: `true`)

### Onboarding / Profile Autofill Source Columns
The profile details auto-filled into read-only fields on the client (and injected into the intake payload) come from the `patients` table:
- **Full Name:** Combined client-side via `${first_name} ${last_name}` from `patients.first_name` and `patients.last_name`.
- **Date of Birth:** `patients.date_of_birth`
- **Contact Number:** `patients.contact_number`
- **Address:** `patients.address`

### Client-side Validation Rules
- Fields marked `required` must be non-empty and non-whitespace strings.
- **Age Restriction:** For `patient-intake` forms, the patient must be 18 years old or above (determined by date of birth vs current UTC+8 Manila time).

---

## 3. Row-Level Security (RLS) & Write-Path Gate

### RLS Policies
The patient inserts the records directly into the `documents` table. RLS policies on the `public.documents` table are defined as:
```sql
CREATE POLICY "Patients can insert own documents" 
  ON public.documents FOR INSERT 
  WITH CHECK (uploader_id = auth.uid());

CREATE POLICY "Patients can update own pending documents" 
  ON public.documents FOR UPDATE 
  USING (uploader_id = auth.uid() AND status = 'pending')
  WITH CHECK (uploader_id = auth.uid() AND status = 'pending');
```

- **Allowed Columns:** Patients can insert any columns, but the verification ensures that `uploader_id` matches the user's session JWT.
- **Service-Role Verification:** The submission action is governed strictly by the user's RLS session (anon key + user JWT). No service-role bypass is present in `submitTemplateDocumentAction`.

---

## 4. Reception-Side Handling

- **Queue Distinction:** 
  - Submissions of type template are marked with `file_type = 'template'`.
  - The reception approval UI displays a custom `"Validated Template Form"` panel instead of running OCR text highlighter.
  - The `"View Original Document"` button is disabled and displays `'Structured Form (No Image)'` label.
  - The validation status is hardcoded to render `100% Validated` on the reception screen.
- **Mobile Reception Parity:** The mobile companion reception views (if present or in-development) must skip image downloading and OCR text rendering when `file_type == 'template'`, and parse `extracted_metadata` values directly to display the structured form details.

---

## 5. Redaction Confirmation
No secrets, credentials, or actual Supabase project references have been written to this document.
