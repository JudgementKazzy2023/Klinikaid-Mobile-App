# SPEC — Phase S2: Specialist Private Record Entry (Lab-Structured)

Second phase of the specialist workstation. Enables the "Enter Record (Coming Soon)" action from S1. Specialists enter structured lab results for their private patients, writing to `specialist_records`. Lab-structured only — no free-text mode (matches the web specialist portal, which is lab panels only).

**This is mostly D2 reuse.** The lab reference ranges, gender-aware flag calculation, and parameter-grid pattern are already built and tested (D2). S2 reuses them verbatim against the specialist's isolated tables. The main differences from D2: a different destination table (`specialist_records`), different scoping columns (`specialist_patient_id` + `specialist_id`, no `department`/`patient_queue`), and **no queue step** — record entry is a single INSERT with no follow-up queue update.

## User Review Required

> [!IMPORTANT]
> **Reuse the D2 engine — do NOT re-implement.** `lib/features/department/domain/lab_reference_ranges.dart` and `flag_calculator.dart` are the single source of truth for ranges + flagging. Import and reuse them. Do not copy the ranges into a new file (that would create a THIRD copy and a new drift risk beyond Constraint #13).

> [!IMPORTANT]
> **No queue.** Unlike department result entry (D2), specialist entry has NO `patient_queue` interaction. It is a single INSERT into `specialist_records`. There is no second UPDATE call, no auto-complete, no start-of-day match clause. Simpler than D2.

> [!WARNING]
> **Dialog provider-scope trap (learned in S1).** If the record-entry UI is shown via `showDialog`, the dialog route is pushed onto the ROOT navigator, ABOVE `SpecialistShell` where `SpecialistProvider` lives — causing `ProviderNotFoundException` and a silently dead submit button (this was the S1 Save-Patient bug). AVOID this: either (a) make record entry a full pushed route INSIDE the specialist provider scope (recommended — matches the web full-page "Enter Private Record" screen), or (b) if a dialog/sheet is used, pass the provider explicitly via `.value` or resolve it above the dialog. Widget tests MUST exercise the real navigation topology (pushed route / real showDialog), not an inline-rendered form, or they will pass while the real button is dead.

## Confirmed Backend (from web team — deployed)

### Destination table: `specialist_records`
```
id                    uuid PRIMARY KEY DEFAULT gen_random_uuid()
specialist_patient_id uuid NOT NULL  REFERENCES specialist_patients(id) ON DELETE CASCADE
specialist_id         uuid NOT NULL  REFERENCES profiles(id) ON DELETE SET NULL
test_type             text NOT NULL   -- diagnostic group name (e.g. "Complete Blood Count (CBC)")
test_name             text NOT NULL   -- parameter name (e.g. "Hemoglobin")
test_value            text NOT NULL   -- stringified value
unit                  text
reference_range_min   numeric
reference_range_max   numeric
is_flagged            boolean NOT NULL DEFAULT false
notes                 text            -- shared batch clinical note, same on all rows
created_at            timestamptz NOT NULL DEFAULT timezone('utc', now())
updated_at            timestamptz NOT NULL DEFAULT timezone('utc', now())
```

RLS: `Specialist manages own records` — FOR ALL, `specialist_id = auth.uid()` USING + WITH CHECK. Client never supplies `specialist_id`; resolve from session.

### Column mapping vs D2 `department_records`
| D2 (department_records) | S2 (specialist_records) |
| :--- | :--- |
| patient_id | specialist_patient_id |
| recorder_id | specialist_id |
| department | (none) |
| test_type / test_name / test_value / unit / reference_range_min / reference_range_max / is_flagged / notes | identical |

Same value semantics: `test_value` stringified; `notes` is one batch note repeated across all rows; N rows per N parameters; gender-resolved range stored on each row (consistent with its flag); empty params skipped, ≥1 required.

## Open Questions

*None.* Lab-only confirmed; engine reuse confirmed; schema deployed.

---

## Proposed Changes

### 1. Repository

#### [MODIFY] lib/features/specialist/data/specialist_repository.dart
- `submitRecord({ required String specialistPatientId, required String testType, required List<SpecialistRecordRow> rows, String? notes })`:
  - Single `.insert(rows)` into `specialist_records`. **No queue update, no second call.**
  - `specialist_id` set from `auth.uid()` on every row (never from caller). RLS enforces the same.
  - One row per parameter (N rows for N params).
  - On failure → surface the error (no silent catch — S1 lesson).
- `getPatientRecords(String specialistPatientId)` — SELECT the patient's records (for record-count refresh + later S3 analytics). RLS auto-scopes.
- Row model `SpecialistRecordRow` (or reuse `SpecialistRecord` for insert): fields map to the 11 insert columns; `test_value` stringified; gender-resolved `reference_range_min/max` stored.

### 2. Provider

#### [NEW] lib/features/specialist/presentation/providers/record_entry_provider.dart
- Holds entry state: selected patient, selected diagnostic group, per-parameter values, batch clinical note, loading/error.
- Reuses D2 domain: import `kLabTestGroups`, `kLabReferenceRanges` from `lib/features/department/domain/lab_reference_ranges.dart`, and `isValueFlagged` from `flag_calculator.dart`.
- Resolves the patient's gender from the `SpecialistPatient` record (passed in / fetched) → drives range resolution (male default for null/other, per D2/web parity).
- `computeStatus()`: flagged if any param out of range (mirrors D2). No free-text path.
- `submit()`: validates ≥1 non-empty numeric param, builds N rows with gender-resolved ranges + stringified values + `is_flagged` per row + batch note, calls repo, on success refreshes directory/dashboard record counts and pops.
- Non-numeric input → block with validation message (S1 lesson: no silent block).

### 3. Route + Screen

#### [MODIFY] lib/core/routing/app_router.dart
- Add `/specialist/record-entry/:patientId` under the specialist guard chain (auth → role → AAL2 if applicable). **Full pushed route** (not a root-navigator dialog) so it stays within the specialist provider scope — see the dialog-trap warning. If it must live outside the shell, ensure `SpecialistProvider` (and the new `RecordEntryProvider`) are provided above the route.

#### [MODIFY] lib/features/specialist/presentation/screens/specialist_directory_screen.dart
- Enable the "Enter Record" action (remove "Coming Soon" / disabled). Tap → navigate to `/specialist/record-entry/:patientId`.

#### [NEW] lib/features/specialist/presentation/screens/record_entry_screen.dart
- Header: "Enter Private Record" + "Log clinical data for {Last, First}." + an "End-to-End Isolated" badge (matches web).
- Diagnostic Group dropdown: CBC / FBS / Renal Function / Lipid Profile (from `kLabTestGroups`).
- On group select → render parameter rows (name, "Enter value" numeric field). Show a per-param reference hint ("Reference matches male" / resolved to the patient's gender) matching the web wording.
- Optional live flag indicator per param (out-of-range → red/Flagged), reusing `isValueFlagged`.
- Clinical Notes field (multiline → `notes`, batch-level, same on all rows).
- Cancel / Save Record buttons. Save disabled until ≥1 valid param.
- Save success → toast + pop to directory; directory record count for that patient increments; dashboard flagged/critical refresh if applicable.
- Save error → error toast, stay on screen (no silent failure).

---

## Verification Plan

### Automated Tests

> Tests MUST exercise the real navigation topology — reach the entry screen via the pushed route (as a user does), not by rendering the form inline. This is the specific gap that let the S1 dialog bug pass tests.

#### [NEW] test/phase_s2_specialist_record_entry_test.dart
1. Enter Record action navigates to `/specialist/record-entry/:patientId` (real route push).
2. CBC group → 3 param rows (Hemoglobin, WBC, Platelets) via reused kLabTestGroups.
3. Enter 3 values → submit → repo receives 3 rows into specialist_records.
4. One param out of gender-resolved range → that row is_flagged true; record reads flagged.
5. All normal → all rows is_flagged false.
6. Female patient Creatinine 1.15 (F max 1.1) → flagged; stored reference_range_min/max == 0.5/1.1 (gender-resolved range persisted — reuses D2 engine).
7. Null/other gender → male range used and stored.
8. test_value stringified ("10.5" not 10.5).
9. Empty param skipped; all-empty → submit blocked.
10. Non-numeric input → blocked with a visible validation message (no silent block).
11. Batch clinical note → same notes value on all rows.
12. submit sets specialist_id from session, never from UI; specialist_patient_id set from the route patient.
13. NO patient_queue interaction occurs (single insert only — assert no queue call).
14. Save-button submit path actually fires through the provider (guards against the S1 dialog-scope dead-button class of bug — reach it via the real route).

#### [NEW/MODIFY] test/phase_s2_specialist_routing_test.dart (or extend S1 routing test)
15. `/specialist/record-entry/:patientId` guarded — non-specialist blocked.
16. Specialist reaches record entry from directory; provider is in scope (no ProviderNotFoundException).

### Regression
```bash
flutter analyze
flutter test test/phase_d2_flag_calculator_test.dart   # engine still green (reused, unchanged)
flutter test test/phase_d2_lab_entry_test.dart
flutter test test/phase_s1_add_patient_test.dart
flutter test test/phase_s1_specialist_directory_test.dart
flutter test
```

### Manual Verification (real device)
1. Specialist → My Patients → Enter Record on a patient → record-entry screen opens (no dead button, provider in scope).
2. CBC → enter Hemoglobin low, WBC/Platelets normal → Save → toast, back to directory, that patient's record count increments, dashboard flagged count updates.
3. Female patient, Creatinine 1.15 → flagged; the stored range on the record is 0.5–1.1 (gender-resolved) — verify the record shows the correct range for its flag.
4. Enter non-numeric value → blocked with a visible message.
5. Empty form → Save blocked; one valid param → allowed.
6. Confirm NO queue behavior (specialists have no queue).
7. Different specialist cannot see these records (RLS isolation).
8. APK grep unaffected.

---

## Out of Scope
- **S3** — Diagnostic Analytics (longitudinal chart; adds `fl_chart`).
- **S4** — Constraint #12 rewrite (specialist → write-capable) + consolidation + defense.
- No free-text mode (specialist is lab-only).
- No queue logic.
- No new lab ranges file — reuse D2's.

---

## Build Rules
- SPEC locked. **No scope creep** — do NOT add validators, fields, or modes beyond this spec (the S1 Save bug traced partly to added-beyond-spec behavior; keep to what's written).
- Reuse D2 domain (ranges + flag calc); do not duplicate.
- Record entry is a pushed route within specialist provider scope — avoid the root-navigator dialog trap. Widget tests use the real route/topology.
- Every validation failure surfaces a visible message; no silent blocks; no swallowed insert errors.
- Atomic order: repo → record_entry_provider → route/directory-button → record_entry_screen → tests.
- flutter analyze clean after each group; tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase ref — placeholder. RLS does isolation; never pass specialist_id.
- **No image/mockup generation. Keep the walkthrough concise.**
- Full suite green before Gate D.
