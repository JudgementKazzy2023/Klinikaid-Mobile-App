# 04 — Development Story: Phases & Hardening Fixes

The app was built in structured phases. Each phase locked requirements before implementation, built incrementally, and verified with automated tests plus real-device checks. This is the narrative arc, not an exhaustive changelog.

## Registration & Onboarding UX Restructure

Merged the separate registration and onboarding flows into one. Introduced a read-only patient profile with editable contact/address fields, a hard 13+ age minimum on date of birth, an RA 10173 privacy-policy modal and a separate terms-and-conditions modal (two independent checkboxes), and a secure email-change flow gated by OTP verification.

## Staff Password Change

Added a staff password-change flow that is MFA-aware: AAL2 sessions skip current-password reauthentication, while non-MFA accounts reauthenticate via `signInWithPassword`.

## Receptionist Workstation (R1–R5)

Built the receptionist's write-capable workstation:
- **Document validation** — review the raw uploaded image alongside OCR output; approve or reject.
- **Approve & Route** — writes to `patient_queue` with generated queue numbers, using a Philippine-time start-of-day helper for correct daily scoping.
- **Reject** — preset reason chips plus an editable free-text box with a minimum-length requirement.
- **Reception dashboard** — operational summary.

This phase produced **Constraint #12**: the system's write model evolved from "staff are read-only" to **role-differentiated write permissions**. Reception writes queue and document state; other roles remained scoped accordingly. All receptionist write flows were cross-verified against the web platform.

## Department Staff Shell + Queue + Records — Read (D1)

The read-only foundation for the department workstation, scoped per department (Laboratory, Imaging, Ultrasound, ECG):
- Department-scoped daily queue and records history, resolved from the session (never a caller-supplied department).
- Realtime queue updates filtered `department=eq.{dept}`; records fetched on mount.
- Route guard chain `authenticated → role match → department assigned → AAL2 → allow`.
- Defensive parsing of `triage_notes` JSON with graceful fallbacks; recorder-name join with an "Entered by Unknown" fallback.
- Department-aware role labels ("Laboratory Staff", "Imaging Staff", …) rather than a generic enum string.

Status badges were standardized to two values, **NORMAL** and **FLAGGED**; earlier `CRITICALHIGH`/`CRITICALLOW` values were stale mock artifacts and were removed (legacy database values map to `flagged` for backward compatibility).

## OCR Quality Refactor (Patient Side)

Reworked the patient document-upload flow around panelist feedback:
- A single quality **score threshold** (≥ 85 = pass, < 85 = warn) replaces the older multi-tier verdict for pass/fail purposes.
- On a passing score there is **no warning and no issues list** — the patient submits directly.
- On a sub-threshold score the patient sees a plain-language warning and the specific quality issues, but **can still submit** — low quality never hard-blocks; the receptionist reviews flagged submissions manually.
- The picked document and its assessment are **cached in the provider**, so navigating away and back does not force a re-upload. State clears only on explicit Retake, a successful submit, or logout.
- Identity-mismatch warnings stack independently of the quality score.
- The image preview degrades gracefully to a "Preview unavailable" placeholder if a file cannot be decoded.

## Department Result Entry — Write (D2)

Enabled clinical result entry for all four departments in one phase, matching the web platform's two entry modes:
- **Lab mode** — a preset test-group picker (CBC, FBS, Renal Function, Lipid Profile) renders a parameter grid; values are entered per parameter, flags auto-compute against gender-aware reference ranges, and the overall record reads FLAGGED if any parameter is out of range.
- **Free-text mode** (Imaging / Ultrasound / ECG) — a typed test name plus required Findings and Impression fields; these records are always NORMAL.

Both modes write **one row per result**, then separately mark the queue entry `completed`. Results are visible to the patient and specialist immediately — there is no approval gate in the shared schema. This phase produced **Constraint #13**: lab reference ranges and test groups are duplicated from the web platform's `constants.ts`, with the deliberate non-atomic two-call write and male-default gender fallback preserved for cross-platform parity.

## Department Consolidation (D4)

The department workstation arc (D1 read, D2 write) was closed with a consolidation phase that rewrote **Constraint #12** to move department staff from read-only into the write-capable clause, adding an evolution note recording the deliberate staged read-then-write rollout.

## OCR Upload Polish (Patient Side)

Two refinements to the document-upload flow after panelist feedback: a processing spinner during on-device OCR and quality assessment (the delay previously read as a frozen upload), and score-driven Retake visibility — on a clean pass (score ≥ 85 and the patient's name found) the Retake button is hidden and only Submit is shown; Retake reappears only when there is something worth retaking for (sub-threshold quality or an identity mismatch).

## Specialist Workstation (S1–S4)

A private-practice model distinct from the shared clinic flow. Unlike department staff (who work the reception-fed shared queue), the specialist owns a private, isolated patient roster stored in dedicated tables (`specialist_patients`, `specialist_records`) with RLS scoped to `specialist_id = auth.uid()` — invisible to admins, other specialists, and every other role.

- **S1** — Specialist dashboard (own aggregates), private patient directory, and add-private-patient. Patient codes are derived client-side from the row id (no stored code column), so mobile and web produce identical codes.
- **S2** — Private lab record entry, reusing the D2 lab range + gender-aware flag engine verbatim, writing to `specialist_records`. No queue (single insert), unlike the shared department flow.
- **S3** — Diagnostic analytics: a read-only longitudinal trajectory chart per parameter (fl_chart) plus a history audit table. Descriptive only — no AI inference, no prediction — to satisfy Specific Objective C, with the disclaimer surfaced in-app. The chart's reference band and per-point flags come from each record's stored range, keeping historical points audit-consistent.
- **S4** — Consolidation; rewrote **Constraint #12** a second time to move medical specialists into a write-capable clause scoped to their isolated tables, explicitly noting they have no write access to shared clinic data.

## Admin Workstation (A1–A3)

The admin role, previously blocked from mobile entirely, was brought onto the client as an oversight-plus-management workstation — deliberately scoped so that no service-role operation ever runs on the device.

- **A1** — Read foundation: admin unblocked in routing (with mandatory AAL2 step-up), dashboard (clinic aggregates + department workload chart + system event log), system logs (events / chatbot audit / API cost tracker with CSV export), cross-department records view, reception queue view, and read-only staff and RAG lists. The API cost tracker replicates the web's app-side calculation (a blended per-1M-token rate applied to daily token usage from a Postgres RPC, with prorated weekly budgets) — another documented web-sync coupling in the same class as Constraint #13.
- **A2** — RLS-governed writes: staff activate/deactivate (`profiles.is_active`) and role/department edits, plus admin-as-receptionist (approve/route/reject, reusing the R1–R5 receptionist screens). Two parity gaps are surfaced honestly in-app: deactivation does not revoke live sessions and role edits do not sync Auth metadata, because both require the service-role key. A self-lockout guard prevents an admin from deactivating or demoting their own account.
- **A2.5** — Admin-as-department-staff: a Daily Queue tab plus result entry (lab and free-text) across all four departments, reusing the D1/D2 screens and the flag engine, with the department chosen via a switcher rather than the session.
- **A3** — RAG knowledge-base document delete (RLS-governed, delete-by-`document_id` across all chunks, behind a confirmation dialog).

**Service-role operations remain permanently web-only** and are excluded from mobile by design: staff account creation, password-reset emails, live-session revocation, Auth-metadata sync, and RAG document upload/embedding (the last requires the server-side Gemini key). This boundary is the reason the admin client holds only the public anon key and the APK grep stays clean.

## Recurring Practices

- Requirements and plans are locked before code (a gate-based review workflow).
- Reference to the live Supabase project is always replaced with a placeholder in shared artifacts.
- Release APKs are decompiled and grep-checked to confirm no `AIzaSy`/`GEMINI`/`service_role` strings ship in the client.
- Verification happens on a real device, not an emulator.

## Known Deferred Items

- **Queue number rendering** — some queue cards can display `Queue: —` when the reception routing flow has not written `queue_number` into the `triage_notes` JSON. This is an upstream reception/web concern; the mobile client's defensive fallback is behaving correctly.
