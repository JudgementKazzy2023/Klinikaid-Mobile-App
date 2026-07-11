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

## Recurring Practices

- Requirements and plans are locked before code (a gate-based review workflow).
- Reference to the live Supabase project is always replaced with a placeholder in shared artifacts.
- Release APKs are decompiled and grep-checked to confirm no `AIzaSy`/`GEMINI`/`service_role` strings ship in the client.
- Verification happens on a real device, not an emulator.

## Known Deferred Items

- **Queue number rendering** — some queue cards can display `Queue: —` when the reception routing flow has not written `queue_number` into the `triage_notes` JSON. This is an upstream reception/web concern; the mobile client's defensive fallback is behaving correctly.
