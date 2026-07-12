# SPEC — Phase A2.5: Admin-as-Department-Staff (Queue + Result Entry)

Focused add-on to the admin arc. Gives the admin the department-staff capability the web admin has: view any department's daily queue AND enter results (lab structured + free-text), across all four departments. This is the department parallel to A2's admin-as-receptionist.

**Reuses D1/D2 department screens** exactly as A2 reused the receptionist screens. No rebuilt queue/entry UI. The only differences from a normal department staffer: the admin is NOT session-scoped to one department (they pick any via a switcher), and they reach it through admin routes.

## User Review Required

> [!IMPORTANT]
> **Reuse D1/D2 screens — do NOT rebuild.** The department daily-queue screen, the result-entry screen (lab param grid + free-text Findings/Impression), the gender-aware flag engine (`lab_reference_ranges.dart` + `flag_calculator.dart`) are all built and tested. Admin reuses them verbatim. Duplicating any of this is a defect.

> [!IMPORTANT]
> **Admin is cross-department; department staff is session-scoped.** A normal department staffer resolves their ONE department from the session. The admin instead selects the department via a switcher (Laboratory / Imaging / Ultrasound / ECG) — the same switcher the current admin "Clinical Records" screen already has. That selected department drives which queue + which entry mode (lab vs free-text) is shown. This cross-department selection is the intended, correct exception (admin oversight spans all departments).

> [!IMPORTANT]
> **RLS write coverage must be confirmed (like A2).** Result entry writes `department_records` (INSERT) and updates `patient_queue` (→ completed). A2 proved admin can write `documents`/`patient_queue` for reception. This phase writes `department_records` — confirm the admin policy (FOR ALL / oversight) covers that table too. If admin isn't covered, the entry screen opens but the write fails — flag it as a web-team RLS question, don't let it silently fail.

> [!IMPORTANT]
> **No queue for lab vs no-queue distinction:** department result entry (D2) writes N rows to `department_records` then updates the shared `patient_queue` entry to completed (two-call, non-atomic, web parity). Admin does the SAME — this is the shared clinic flow, not the specialist private flow. Do not confuse with the specialist no-queue path.

## Confirmed Backend
- `department_records` (11-column shape from D2), `patient_queue` — existing shared tables.
- Lab ranges + flag logic: reuse `lib/features/department/domain/lab_reference_ranges.dart` + `flag_calculator.dart` (Constraint #13 coupling already documented).
- Department values: `laboratory, imaging, ultrasound, ecg`.
- Entry modes: lab = structured panels (laboratory); free-text Findings+Impression (imaging/ultrasound/ecg) — same split as D2.
- RLS: admin FOR ALL / oversight on `department_records` + `patient_queue` — **confirm at build** (see above).

## Open Questions
*None* — pending the build-time RLS confirmation, which is a verify-step not a blocker.

---

## Proposed Changes

### 1. Convert admin "Clinical Records" into the full department view
#### [MODIFY] lib/features/admin/presentation/screens/admin_records_screen.dart (or add a sibling)
- The current admin department screen is records-history only (read). The web admin department portal has TWO tabs: **Daily Queue** (with Enter Results) + **Records History**. Add the Daily Queue tab.
- Keep the existing department switcher (Laboratory / Imaging / Ultrasound / ECG). Selecting a department drives both tabs.
- **Daily Queue tab:** reuse the D1 department queue rendering (waiting/in-progress list, patient cards) for the selected department. Each queued patient has an **Enter Results** action (reused D1/D2 button).
- **Records History tab:** the existing read view (unchanged).

### 2. Wire Enter Results → reused D2 entry screen under admin route
#### [MODIFY] lib/core/routing/app_router.dart
- Add `/admin/department/result-entry/:patientId` (or reuse the existing result-entry route if the guard can be broadened safely) under the **admin** guard chain (auth → role==admin → AAL2). Full pushed route in admin provider scope — same standalone-route pattern A2 used for `/admin/document/:id` to avoid the department shell's role guard rejecting admin.
- The route must carry the selected department (path/param/extra) so the entry screen knows which mode (lab vs free-text) and which department to write.

#### [MODIFY] admin department queue → tap Enter Results
- Navigate to the admin result-entry route with the patient + selected department.

#### [REUSE] lib/features/department/presentation/screens/result_entry_screen.dart
- Reuse the D2 result-entry screen (lab param grid with gender-aware flagging, OR free-text Findings/Impression, depending on department). It must accept the department from the admin route rather than only from session. If it currently reads department strictly from session, adapt minimally so an admin-supplied department is accepted — without breaking the normal department-staff path.

### 3. Repository
#### [MODIFY] lib/features/admin/data/admin_repository.dart (or reuse DepartmentRepository)
- Prefer reusing `DepartmentRepository.submitLabResults` / `submitFreeTextResult`. If those resolve department strictly from session, add an admin-callable variant that accepts an explicit department (admin is cross-dept), still writing under the admin session (RLS governs). Do NOT duplicate the flag/range logic.
- Queue read for the selected department: reuse the D1 queue fetch, parameterized by the admin-selected department (this is the one correct place for a department arg — admin spans depts).

### 4. Provider
- Reuse/extend the admin provider or the department provider to hold the admin-selected department + queue + entry state. Surface errors visibly.

---

## Verification Plan

> Standing rule: user-observable correctness. Admin picks Imaging → sees the IMAGING queue (not lab). Admin enters a result for patient X → X's record is written and X's queue entry completes. Not just "the screen renders."

### Automated Tests

#### [NEW] test/phase_a25_admin_department_test.dart
1. Admin department screen has TWO tabs (Daily Queue + Records History).
2. Department switcher → selecting Imaging shows the Imaging queue; Laboratory shows the Lab queue (right dept, route/state correctness — the recurring lesson).
3. Lab department → Enter Results opens the reused lab param-grid entry (CBC/FBS/Renal/Lipid).
4. Imaging/Ultrasound/ECG → Enter Results opens the reused free-text entry (Findings + Impression).
5. Lab entry: value out of gender-resolved range → flagged; gender-resolved range stored on the row (reuses D2 engine — assert not recomputed/duplicated).
6. Submit lab results → N rows INSERT into department_records + patient_queue updated to completed, under the ADMIN session.
7. Submit free-text → 2 rows (Findings/Impression), is_flagged false.
8. **RLS coverage test:** admin session writes department_records successfully; a non-admin/non-department session attempting the same is blocked (proves admin policy governs).
9. Reuses the D1/D2 screens/widgets (assert shared components used, not a rebuilt UI).
10. Route guard: admin allowed on /admin/department/result-entry/*; non-admin blocked.

### Regression
```bash
flutter analyze
flutter test test/phase_d2_lab_entry_test.dart        # D2 engine unchanged + green
flutter test test/phase_d2_freetext_entry_test.dart
flutter test test/phase_d1_department_queue_test.dart
flutter test test/phase_a2_admin_receptionist_test.dart
flutter test
```
- If DepartmentRepository/screens were adapted to accept an admin-supplied department, confirm the normal department-staff path (session-scoped) still passes unchanged.

### Manual Verification (real device)
1. Admin → department screen → switch to Laboratory → see lab queue → Enter Results on a patient → lab param grid → enter values → submit → record written, patient's queue entry completes, record appears in Records History.
2. Switch to Imaging → free-text entry → Findings + Impression → submit → NORMAL record written.
3. Confirm gender-resolved flagging works (female Creatinine 1.15 → flagged, stored range 0.5–1.1) — proves reused D2 engine.
4. Cross-check on web: the admin-entered record appears identically (parity).
5. Switch departments → queue + entry mode change correctly (lab grid vs free-text).
6. Non-admin cannot reach /admin/department/*.
7. APK grep: no service-role/secrets.

---

## Out of Scope
- **A3** — RAG delete.
- **A4** — Constraint #10/#12 rewrite + consolidation.
- No new lab ranges file (reuse D2's).
- No specialist-flow confusion (this is the shared clinic queue flow, with queue completion — not the specialist no-queue path).
- Account creation / password reset / session revoke / metadata sync — permanently web-only.

---

## Build Rules
- SPEC locked. No scope creep. Reuse D1/D2 department screens + engine; do not duplicate.
- Admin is cross-department (switcher-driven); do not break the session-scoped normal department-staff path.
- Admin writes under admin JWT; confirm RLS covers department_records + patient_queue for admin (crafted-request test). If not covered, flag as web-team question — don't silently fail.
- Result entry is a standalone pushed route in admin scope (avoid the department shell guard rejecting admin, like A2's /admin/document route).
- Reuse the gender-resolved range + stored-range-on-row behavior from D2 exactly.
- Every write validates + surfaces errors; no silent catch.
- Tests assert user-observable correctness (right dept selected, record actually written, queue actually completes), not just render.
- flutter analyze clean; tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase ref — placeholder. RLS governs.
- No image/mockup generation. Concise walkthrough.
- Full suite green before Gate D.
