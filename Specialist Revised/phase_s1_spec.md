# SPEC — Phase S1: Specialist Workstation (Dashboard + Private Directory + Add Patient)

First phase of the mobile specialist workstation, mirroring the web platform's specialist portal. Ports the read surfaces (dashboard, private patient directory) plus the first write (add private patient). Record entry (S2) and analytics (S3) follow.

**This is a read-then-write phase like D1/D2 combined at a smaller scale:** directory + dashboard are reads; add-patient is the first write. It makes the specialist role write-capable — a deliberate Constraint #12 evolution, approved by panel/web (third evolution after receptionist and department staff). The #12 rewrite itself is deferred to the specialist arc's closeout phase (S4), same pattern as D4.

## User Review Required

> [!IMPORTANT]
> **Fully isolated data model.** The specialist's patients and records live in dedicated tables (`specialist_patients`, `specialist_records`), NOT the shared `patients`/`department_records`. RLS scopes every row to `specialist_id = auth.uid()`. Admins, receptionists, patients, and OTHER specialists have no access. This is end-to-end isolation by design.

> [!IMPORTANT]
> **Patient code is derived, not stored.** There is no `patient_code` column. The displayed code (e.g. `PT-B65127E0`) is derived client-side from the row `id` so both web and mobile produce the identical code with no coordination. See the shared helper below.

> [!IMPORTANT]
> **Specialist becomes write-capable in this phase** (add private patient). Constraint #12 currently says specialists are read-only; that rewrite lands in S4 (specialist closeout). Do NOT edit Constraint #12 in S1 — just build the capability.

## Confirmed Backend (from web team — already deployed)

### Table: `specialist_patients`
```
id                uuid  DEFAULT gen_random_uuid() PRIMARY KEY
specialist_id     uuid  REFERENCES profiles(id) ON DELETE CASCADE NOT NULL
first_name        text  NOT NULL
last_name         text  NOT NULL
date_of_birth     date  NOT NULL
gender            text  NOT NULL CHECK (gender IN ('male','female','other'))
contact_number    text
email             text
address           text
created_at        timestamptz DEFAULT timezone('utc', now()) NOT NULL
updated_at        timestamptz DEFAULT timezone('utc', now()) NOT NULL
```

### Table: `specialist_records` (S2 will write here; S1 only reads counts)
```
id                    uuid DEFAULT gen_random_uuid() PRIMARY KEY
specialist_patient_id uuid REFERENCES specialist_patients(id) ON DELETE CASCADE NOT NULL
specialist_id         uuid REFERENCES profiles(id) ON DELETE SET NULL NOT NULL
test_type             text NOT NULL
test_name             text NOT NULL
test_value            text NOT NULL
unit                  text
reference_range_min   numeric
reference_range_max   numeric
is_flagged            boolean NOT NULL DEFAULT false
notes                 text
created_at            timestamptz DEFAULT timezone('utc', now()) NOT NULL
updated_at            timestamptz DEFAULT timezone('utc', now()) NOT NULL
```
Note: `specialist_records` mirrors the `department_records` 11-field shape, so the D2 lab-range + flag engine is reusable verbatim in S2. Same male-default gender fallback.

### RLS (both tables)
```sql
CREATE POLICY "Specialist manages own patients"
  ON public.specialist_patients FOR ALL
  USING (specialist_id = auth.uid()) WITH CHECK (specialist_id = auth.uid());

CREATE POLICY "Specialist manages own records"
  ON public.specialist_records FOR ALL
  USING (specialist_id = auth.uid()) WITH CHECK (specialist_id = auth.uid());
```
No migration needed — the backend is deployed.

## Open Questions

*None.* Schema, RLS, patient-code strategy, and age rule are locked.

---

## Proposed Changes

### 1. Models

#### [NEW] lib/core/models/specialist_patient.dart
- `SpecialistPatient` model mapping every `specialist_patients` column.
- `gender` is a plain string constrained to `male`/`female`/`other` (matches DB CHECK).
- A computed getter `age` from `date_of_birth`.
- A computed getter `patientCode` → uses the shared helper below.

#### [NEW] lib/core/models/specialist_record.dart
- `SpecialistRecord` model mapping every `specialist_records` column (needed for S1 dashboard aggregates: flagged counts, last-tested date, record counts).

### 2. Patient code helper (shared, derived)

#### [NEW] lib/core/utils/patient_code.dart
- `String patientCodeFromId(String id)` → strips dashes from the uuid, takes the first 8 hex chars, uppercases, prefixes `PT-`. Example: id starting `b65127e0-...` → `PT-B65127E0`.
- Pure function, unit-tested. Both directory rows and (later) analytics headers use it. Deterministic from `id` so it matches the web platform's derivation.
- If, during build, the web platform is found to derive the code differently (e.g. different slice length or casing), match web exactly — the codes MUST be identical across clients. Note any deviation.

### 3. Repository

#### [NEW] lib/features/specialist/data/specialist_repository.dart
- `getMyPatients()` → SELECT from `specialist_patients` (RLS auto-scopes to `auth.uid()`; do NOT pass specialist_id as an argument — resolve from session, same pattern as department scoping). Ordered by `created_at DESC` or name; confirm against web default.
- `addPatient({ required first, last, dob, gender, contact?, email?, address? })` → INSERT into `specialist_patients` with `specialist_id = auth.uid()`. Returns the created row.
- `getDashboardData()` → the aggregates the dashboard needs (see §5). Implement as scoped queries over the specialist's own patients + records:
  - total patients (count of `specialist_patients`)
  - flagged results in last 7 days (count of `specialist_records` where `is_flagged = true` AND `created_at >= now() - 7 days`)
  - active modalities (distinct `test_type` — or department grouping — present in the specialist's records; confirm what "modalities" maps to on web)
  - critical flagged results list (recent flagged `specialist_records`, joined to patient name, limited ~10)
  - recently updated patients (patients with most recent record activity)
- All reads rely on RLS for isolation; client never supplies `specialist_id`.

### 4. Provider

#### [NEW] lib/features/specialist/presentation/providers/specialist_provider.dart
- Holds directory list + search/filter state, dashboard aggregates, loading/error flags.
- `search` filters the directory client-side by patient name or code.
- `addPatient(...)` calls the repo, on success refreshes the directory + dashboard.
- **No "All Departments" filter** — omit it (stale web artifact, per web team). The directory search box + (optional) date range only.

### 5. Screens

#### [MODIFY] lib/core/routing/app_router.dart
- Specialist currently lands on a read-only screen. Add the S1 routes under the specialist role guard (auth → role match → AAL2 if applicable; specialists follow the same staff guard chain):
  - `/specialist/dashboard`
  - `/specialist/patients` (private directory)
  - `/specialist/profile` (reuse existing ProfileScreen)
- If a specialist shell/nav does not yet exist, add one (Dashboard / My Patients / Profile), mirroring the department shell pattern.

#### [NEW] lib/features/specialist/presentation/screens/specialist_dashboard_screen.dart
- Header: "Specialist Dashboard" + subtitle.
- Stat cards: Total Clinic Patients, Flagged Results (7 days), Active Modalities.
- "Critical Flagged Results" — recent out-of-range records table (patient, test, value, reference range, date), tap → (S3 analytics later; in S1 either inert or routes to patient).
- "Recently Updated Patients" list.
- SO-C compliance banner: "No AI Diagnostics Inference: This dashboard provides clinical descriptive analytics only. No machine learning diagnostics or automated diagnostic suggestions are applied to this patient data (SO-C Compliance)." — replicate the web wording.

#### [NEW] lib/features/specialist/presentation/screens/specialist_directory_screen.dart
- Header: "Private Patient Directory" + subtitle ("Secure, isolated directory of your private patient roster. Invisible to administrators.").
- "Add Private Patient" button → opens the add-patient form/modal.
- Search box (name or `PT-` code). **No All-Departments filter.** Optional date-range filter can be included if trivial; otherwise defer.
- Table/list rows: Code (derived), Patient Name, Demographics (age • gender), Total Records, Flagged Status, Last Tested, Actions (Enter Record → S2 placeholder/disabled in S1; Analytics → S3 placeholder/disabled in S1; delete).
- SO-C banner (same as dashboard).
- In S1, "Enter Record" and "Analytics" actions may be present but disabled/"coming soon" (they light up in S2/S3), OR omitted — recommend disabled-with-label so the row layout matches web now.

#### [NEW] lib/features/specialist/presentation/widgets/add_patient_form.dart (or inline modal)
- Fields: First Name*, Last Name*, Date of Birth*, Gender* (male/female/other dropdown), Contact Number, Email, Address.
- Required: first, last, DOB, gender. Optional: contact, email, address (nullable columns).
- **Age rule: 13+ minimum on DOB**, same as patient registration (consistency — Ralph's call).
- Basic email format validation if provided.
- On save → repo.addPatient → close → refresh directory + dashboard → success toast.

### 6. Delete patient (present in web directory)
- Directory row has a delete action (trash icon in web). Include `deletePatient(id)` in repo (DELETE from `specialist_patients`; ON DELETE CASCADE removes the patient's records). Confirm a confirmation dialog before delete (destructive). If you'd rather defer delete to a later phase, say so — otherwise S1 includes it to match web.

---

## Verification Plan

### Automated Tests

#### [NEW] test/phase_s1_patient_code_test.dart
1. `patientCodeFromId('b65127e0-1234-...')` → `'PT-B65127E0'`.
2. Dashes stripped, first 8 hex, uppercased, `PT-` prefix.
3. Deterministic — same id always same code.

#### [NEW] test/phase_s1_specialist_directory_test.dart
4. Directory lists only the session specialist's patients (RLS-scoped; repo does not pass specialist_id).
5. Search filters by patient name.
6. Search filters by patient code.
7. Empty roster → empty-state shown.
8. Row renders code, name, demographics (age • gender), record count, flagged status, last tested.
9. No "All Departments" filter present.

#### [NEW] test/phase_s1_add_patient_test.dart
10. Valid form (all required + optional) → addPatient called with correct payload, directory refreshes.
11. Missing required field (e.g. no last name) → submit blocked.
12. DOB under 13 → submit blocked (13+ rule).
13. Optional fields empty → still submits (nullable columns).
14. Invalid email format → blocked (if provided).
15. addPatient sets specialist_id from session, not from form.

#### [NEW] test/phase_s1_dashboard_test.dart
16. Total patients count reflects specialist's own patients only.
17. Flagged-results-7-days counts only is_flagged records within window.
18. Critical flagged list shows recent flagged records joined to patient name.
19. SO-C compliance banner rendered on dashboard and directory.

#### [NEW] test/phase_s1_specialist_routing_test.dart
20. Specialist routes guarded — non-specialist blocked from `/specialist/*`.
21. Specialist lands on dashboard (or directory) post-login.
22. Add-patient write path reachable; other roles cannot reach specialist routes.

### Regression
```bash
flutter analyze
flutter test test/phase8_staff_specialist_test.dart   # existing specialist read tests — migrate if they assumed read-only-only
flutter test
```
- If existing specialist tests assert the specialist has NO write capability, update them — specialist is now write-capable for its OWN private roster (still no access to shared clinic tables).

### Manual Verification (real device)
1. Log in as specialist → land on dashboard → stat cards populate from own data.
2. Go to My Patients → see own private roster only; codes render as `PT-XXXXXXXX`.
3. Add Private Patient (all fields) → appears in directory, dashboard total increments.
4. Add patient with DOB under 13 → blocked.
5. Search by name and by code → filters correctly.
6. Confirm NO "All Departments" filter on the directory.
7. Delete a patient (if included) → confirmation → row + its records removed.
8. Log in as a DIFFERENT specialist → cannot see the first specialist's patients (RLS isolation proof).
9. Log in as receptionist/department staff/patient → cannot reach `/specialist/*`.
10. APK security grep unaffected (no new secrets).

---

## Out of Scope (later specialist phases)
- **S2** — Enter Private Record (reuses D2 lab engine writing to `specialist_records`).
- **S3** — Diagnostic Analytics (longitudinal chart; will add `fl_chart` dependency).
- **S4** — Constraint #12 rewrite (specialist → write-capable) + consolidation walkthrough + defense narrative.
- No charting in S1.
- No record entry in S1 (Enter Record action disabled/placeholder).

---

## Build Rules
- SPEC locked, no scope creep.
- Atomic order: models → patient_code helper → repository → provider → routing/shell → dashboard → directory → add-patient form → tests.
- flutter analyze after each group, zero warnings before next.
- Tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase project ref — placeholder only.
- No image/mockup generation in plan or walkthrough.
- RLS does the isolation; client never supplies specialist_id — resolve from session.
- Full suite green before Gate D.
