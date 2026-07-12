# SPEC — Phase S3: Specialist Diagnostic Analytics (Longitudinal Trajectory)

Third phase of the specialist workstation. Enables the "Analytics (Coming Soon)" action from the S1 directory. A read-only analytics screen that charts a single lab parameter's values over time for one private patient, plus a chronological history audit table. Mirrors the web specialist "Diagnostic Analytics" page.

**Read-only. No writes.** This phase only SELECTs from `specialist_records` (already isolated by RLS to the owning specialist). It adds one dependency (`fl_chart`) for the trajectory plot.

## User Review Required

> [!IMPORTANT]
> **Descriptive analytics only — no AI/ML, no prediction.** The chart maps historical data points directly. No trend-line fitting, no forecasting, no automated interpretation. This is a hard compliance requirement (Specific Objective C). The SO-C disclaimer banner must be present, matching the web wording.

> [!IMPORTANT]
> **Single-parameter chart with a dropdown selector.** One parameter is plotted at a time (parameters have incompatible units/scales — g/dL vs x10^3/µL vs mg/dL — and cannot share a Y axis). The user picks the parameter; the chart + history table update to that parameter.

> [!IMPORTANT]
> **Reference band comes from the stored per-record ranges.** Each `specialist_record` row already stores `reference_range_min`/`max` (the gender-resolved range used at entry time, from S2). The chart's normal-range band and each point's flagged state come from those STORED values — do NOT recompute against the live D2 ranges. This keeps historical points consistent with the range that was active when they were recorded (the audit-consistency property from D2/S2).

## Confirmed Backend
- Source: `specialist_records`, RLS-scoped `specialist_id = auth.uid()`. Client passes only `specialist_patient_id`; never `specialist_id`.
- Reuses the S2 model `SpecialistRecord` (has test_type, test_name, test_value, unit, reference_range_min/max, is_flagged, notes, created_at). No new table, no new column, no migration.

## Open Questions
*None.* fl_chart chosen; single-parameter dropdown; history table included.

---

## Proposed Changes

### 1. Dependency
- Add `fl_chart` to `pubspec.yaml` (charting). Only new dependency this phase. Pin a version compatible with Flutter 3.44.0 / Dart 3.12.0; run `flutter pub get` and confirm it resolves before building UI.

### 2. Repository
#### [MODIFY] lib/features/specialist/data/specialist_repository.dart
- `getPatientRecords(String specialistPatientId)` already exists from S2 (or add if not) → SELECT all `specialist_records` for that patient, ordered `created_at ASC` (chronological, oldest→newest, for time-series plotting). RLS auto-scopes.
- No new write methods. Read-only phase.

### 3. Analytics domain helper
#### [NEW] lib/features/specialist/domain/analytics_series.dart
- Pure functions (unit-testable, no UI):
  - `List<String> availableParameters(List<SpecialistRecord> records)` → distinct `test_name` values present, in a stable order, so the dropdown only offers parameters the patient actually has data for.
  - `ParameterSeries buildSeries(List<SpecialistRecord> records, String testName)` → filters to that parameter, sorts by `created_at`, produces:
    - ordered points: `(DateTime createdAt, double value, bool isFlagged, double? min, double? max, String? note, String testType, String? unit)`
    - the reference band for the chart: use the min/max from the records (they should be consistent per parameter; if a parameter's stored ranges vary across records, use the MOST RECENT record's range for the band and keep each point's own flagged state from its stored `is_flagged`). Note this choice in code.
  - `test_value` is stored as text → parse with `double.tryParse`; skip/guard unparseable values (should not occur, but defensive).

### 4. Provider
#### [NEW] lib/features/specialist/presentation/providers/analytics_provider.dart
- Holds: loaded records for the patient, the selected parameter, the derived series, loading/error state, patient reference.
- `init(String patientId)` → resolve the patient (reuse `getPatientById` from S2) AND load records; on success default the selected parameter to the first available (or the most recently recorded parameter).
- `selectParameter(String testName)` → rebuild the series for the chart + table.
- Fetch-once on mount (no realtime needed — analytics is historical).
- Errors surface visibly (no silent catch — standing lesson).

### 5. Route + entry point
#### [MODIFY] lib/core/routing/app_router.dart
- Add `/specialist/analytics/:patientId` under the specialist guard chain, as a full pushed route in specialist provider scope (same pattern as S2 record entry — avoid the root-navigator dialog trap; provider created fresh per push and initialized from the route `patientId`).

#### [MODIFY] lib/features/specialist/presentation/screens/specialist_directory_screen.dart
- Enable the "Analytics" action (remove "Coming Soon"/disabled). Tap → navigate to `/specialist/analytics/:patientId` with THAT patient's id.
- (Same route-param discipline as S2: the screen must show the tapped patient, resolved from the route id — not a default. This was the S2 "Jane Miller" bug; do not reintroduce it.)

### 6. Analytics screen
#### [NEW] lib/features/specialist/presentation/screens/analytics_screen.dart
- **Patient header:** name, patient code (derived via `patientCodeFromId`), demographics (age • gender), birth date — matching web.
- **Parameter dropdown:** "Diagnostic Trajectory for parameter: {testName}" — options from `availableParameters`. Empty roster of records → empty state ("No records to chart yet").
- **fl_chart trajectory plot:**
  - X = time (created_at), Y = parameter value.
  - Normal-range band shaded between reference min/max; min and max reference lines drawn + labeled.
  - Points plotted chronologically; out-of-range points visually distinct (flagged color), driven by each point's STORED `is_flagged`.
  - "NORMAL LIMIT: {min} – {max} {unit}" badge.
  - Tap/hover a point → detail: date, value, status (Normal / Out of Range (Flagged)), the point's range limit, and its note if present. (fl_chart touch tooltip.)
  - Single data point → chart still renders the point against the band (don't crash on n=1); the history table carries the detail.
- **SO-C disclaimer banner:** replicate web wording — "No AI Diagnostic Inference Applied: This longitudinal chart maps historical medical data points directly from stored records. No automated machine diagnostics, diagnostic suggestions, or predictive algorithms are used (Specific Objective C compliant)."
- **Parameter History Records table** (below chart, for the selected parameter):
  - Columns: Timestamp, Technologist (the recording specialist — from the record; if only specialist_id is available and no joined name, show the current specialist's name or the id gracefully), Value, Reference Baseline (min–max), Status (Normal/Flagged), Clinical Annotations (notes).
  - Chronological (newest first is fine for an audit list; match web — web shows a single row; use a sensible order and state it).
- Back navigation returns to the directory.

---

## Verification Plan

> Standing test rule: assert user-observable correctness, not just that widgets render. Navigate with patient A's id → the analytics screen shows patient A and A's data (not a default, not B). Select parameter X → chart+table show X's series. "It builds" is not "it works."

### Automated Tests

#### [NEW] test/phase_s3_analytics_series_test.dart (pure domain)
1. `availableParameters` → distinct test_names present, no duplicates.
2. `buildSeries` filters to the selected parameter only.
3. Series sorted chronologically by created_at.
4. Point `isFlagged` reflects the STORED is_flagged (not recomputed).
5. Reference band uses stored min/max (e.g. Cholesterol 100–200).
6. `test_value` text parsed to double; unparseable value guarded (skipped, no crash).
7. Single-record parameter → series of length 1 (no crash).
8. Empty records → empty available-parameters, empty series.

#### [NEW] test/phase_s3_analytics_screen_test.dart (widget)
9. Navigate to `/specialist/analytics/:patientId` for patient A → header shows patient A (route-param correctness; guards the S2 bug class).
10. Dropdown lists only parameters the patient has.
11. Selecting a parameter renders the chart and updates the history table to that parameter.
12. Out-of-range point shows flagged styling / status.
13. SO-C disclaimer banner present.
14. History table renders rows with timestamp, value, reference baseline, status, annotations.
15. Patient with no records → empty state, no crash.

#### [MODIFY] test/phase_s1_specialist_directory_test.dart (or S3 routing test)
16. "Analytics" action enabled (not "Coming Soon").
17. Tapping Analytics on patient A routes to `/specialist/analytics/A` (correct id).
18. `/specialist/analytics/*` guarded — non-specialist blocked.

### Regression
```bash
flutter pub get     # fl_chart resolves
flutter analyze
flutter test test/phase_s2_specialist_record_entry_test.dart
flutter test test/phase_s1_specialist_directory_test.dart
flutter test
```

### Manual Verification (real device)
1. Specialist → My Patients → Analytics on mike Tyson → analytics screen shows mike Tyson (correct patient, not a default).
2. Dropdown → select CBC parameters recorded for him → chart plots his values over time with the normal band; flagged points stand out.
3. Tap a flagged point → tooltip shows value, Out of Range status, range, note.
4. Switch parameter → chart + history table update.
5. History table matches the charted points (timestamp, value, reference, status, notes).
6. Patient with a single record → chart renders the one point, table shows it, no crash.
7. Patient with zero records → clean empty state.
8. Different specialist cannot open these analytics (RLS).
9. Confirm NO trend line / prediction / AI text anywhere; SO-C banner present.
10. APK grep unaffected (fl_chart adds no secrets).

---

## Out of Scope
- **S4** — Constraint #12 rewrite (specialist → write-capable) + consolidation walkthrough + defense narrative. (Specialist is now write-capable via S1 add-patient + S2 record entry; #12 still says read-only. That rewrite is S4, NOT this phase.)
- No writes in S3.
- No predictive/trend/AI analytics (compliance).
- No multi-parameter overlay on one chart.

---

## Build Rules
- SPEC locked. No scope creep — no extra chart types, no trend lines, no fields beyond spec.
- Read-only: no writes to specialist_records.
- Reference band + flags from STORED per-record ranges, not recomputed from live D2 ranges.
- Full pushed route in specialist provider scope; provider fresh per push, initialized from route patientId (no S2 "wrong patient" regression).
- Every validation/error surfaces visibly; no silent catch.
- Tests assert user-observable correctness (right patient, right parameter), not just render.
- Atomic order: pubspec/fl_chart → repo read → analytics_series domain → analytics_provider → route/directory-button → analytics_screen → tests.
- flutter analyze clean after each group; tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase ref — placeholder. RLS does isolation; never pass specialist_id.
- **No image/mockup generation. Concise walkthrough.**
- Full suite green before Gate D.
