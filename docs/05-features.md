# 05 — Features: Scoped Role Matrix

Access is role-gated at the router and enforced again by Supabase RLS on the backend. Roles come from `profiles.role` (`UserRole`: `admin`, `receptionist`, `departmentStaff`, `medicalSpecialist`, `patient`).

## Role Matrix

| Role | Mobile access | Read | Write |
| :--- | :--- | :--- | :--- |
| **Patient** | Full patient app | Own records, own queue status, own documents | Onboarding/profile fields, document upload (OCR + quality), email/password change |
| **Receptionist** | Reception workstation | Pending/approved/rejected document lists, raw OCR | Document approve/route/reject, `patient_queue` writes (queue numbers), reject reasons |
| **Department Staff** | Department workstation (scoped to one department) | Department daily queue, department records history | **Clinical result entry** (lab structured + free-text), queue status → `completed` |
| **Medical Specialist** | Patient lookup | Multi-term patient search, cross-department record timeline | Read-only (may change in a future phase) |
| **Admin / Owner** | **Blocked** | — | — |

> The read-only characterization of Receptionist and Department Staff from early drafts no longer holds: both are write-capable as of the receptionist workstation (R1–R5) and department result entry (D2). See Constraint #12 in [04-development-story](04-development-story.md). Specialist and admin/owner mobile behavior may change in future phases.

## Patient Features

- **Consent & onboarding** — RA 10173 privacy modal + separate T&C modal (two independent checkboxes), hard 13+ age minimum on DOB, merged registration/onboarding, read-only profile with editable contact/address.
- **Document upload with OCR** — camera or gallery capture, on-device ML Kit text recognition, quality scoring via the `assess-document-quality` Edge Function. Score ≥ 85 submits cleanly; below threshold warns but still allows submission; identity-mismatch warnings stack independently. Upload state is cached so navigation doesn't force a re-upload.
- **Records** — view own department records, grouped for readability.
- **Queue** — real-time status of the patient's place in the queue.
- **AI chatbot** — health-assistant Q&A routed through the `chat` Edge Function (no on-device model, no client-side AI key).
- **Account security** — OTP-verified email change, password change.

## Receptionist Features (R1–R5)

- **Document validation** — raw image + OCR side by side; approve or reject.
- **Approve & Route** — writes to `patient_queue` with a generated queue number using a Philippine-time start-of-day helper.
- **Reject** — preset reason chips plus an editable free-text reason with a minimum length.
- **Dashboard** — operational overview.

## Department Staff Features (D1 read + D2 write)

- **Daily queue** — department-scoped, realtime-filtered, with defensive rendering of triage data.
- **Records history** — department-scoped, grouped, with recorder-name fallback.
- **Result entry (D2):**
  - *Lab* — test-group picker → parameter grid, gender-aware auto-flagging, batch technician note.
  - *Free-text* (Imaging/Ultrasound/ECG) — typed test name + required Findings + Impression, batch note; always NORMAL.
  - One row per result; queue entry auto-completes on submit; patient and specialist see the result immediately.

## Medical Specialist Features

- **Multi-term patient search.**
- **Cross-department record timeline** (read-only), grouped by encounter.
