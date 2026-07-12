# 05 — Features: Scoped Role Matrix

Access is role-gated at the router and enforced again by Supabase RLS on the backend. Roles come from `profiles.role` (`UserRole`: `admin`, `receptionist`, `departmentStaff`, `medicalSpecialist`, `patient`).

## Role Matrix

| Role | Mobile access | Read | Write |
| :--- | :--- | :--- | :--- |
| **Patient** | Full patient app | Own records, own queue status, own documents | Onboarding/profile fields, document upload (OCR + quality), email/password change |
| **Receptionist** | Reception workstation | Pending/approved/rejected document lists, raw OCR | Document approve/route/reject, `patient_queue` writes (queue numbers), reject reasons |
| **Department Staff** | Department workstation (scoped to one department) | Department daily queue, department records history | **Clinical result entry** (lab structured + free-text), queue status → `completed` |
| **Medical Specialist** | Patient lookup | Multi-term patient search, cross-department record timeline | Read-only (may change in a future phase) |
| **Medical Specialist** | Private-practice workstation | Own private roster + records + analytics | Create private patients, enter private lab results (isolated tables; no shared-clinic writes) |
| **Admin** | Oversight + management workstation (AAL2) | Everything (dashboard, logs, cost, cross-dept records, queue, staff, RAG) | Staff activate/deactivate + role/dept edit, admin-as-receptionist (approve/route/reject), admin-as-department-staff (result entry), RAG delete — all RLS-governed |
| **Owner** | **Blocked** | — | — |

> The role model evolved across the project: Receptionist and Department Staff became write-capable (R1–R5, D1–D2); Medical Specialist gained a write-capable private-practice workstation (S1–S3); and Admin — previously blocked entirely — was brought onto mobile as an oversight-plus-management client (A1–A3). Each change aligned mobile with the documented system design and the web platform. **Service-role operations remain permanently web-only**: staff account creation, password resets, live-session revocation, Auth-metadata sync, and RAG upload/embedding. The admin client holds only the public anon key and performs only what RLS permits. See Constraint #12 in [04-development-story](04-development-story.md).

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
