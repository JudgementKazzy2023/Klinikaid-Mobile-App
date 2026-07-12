# SPEC — Phase A2: Admin Staff Management Writes + Admin-as-Receptionist

Second admin phase. Adds the RLS-governed WRITES that A1 deliberately deferred:
1. **Staff Management writes** — activate/deactivate (`is_active`), edit role/department.
2. **Admin-as-Receptionist** — admin can open a queue submission and approve/route/reject, reusing the existing receptionist workstation screens.

Service-role operations remain permanently web-only: **account creation and password-reset emails are NOT in this phase, ever.** Admin writes only what RLS permits with the anon key + admin JWT.

## User Review Required

> [!IMPORTANT]
> **Column is `is_active` (boolean), NOT `status`.** Activate = `is_active: true`, deactivate = `is_active: false`. Do not write a `status` column — it does not exist. (Confirmed against `web_context_schema.sql`.)

> [!IMPORTANT]
> **RLS policy path matters.** `profiles` has TWO policies: the admin `"Admins have full access to profiles" FOR ALL USING (get_auth_user_role() = 'admin')` (the one we want), and a self-update policy with an anti-role-hijack `WITH CHECK`. The admin write MUST run under the admin session so the FOR ALL policy applies — if it somehow evaluates as a self-update, a role change is silently blocked. Never pass a caller-supplied identity; the admin's own JWT drives the policy. A crafted-request test must prove admin UPDATE succeeds and non-admin fails.

> [!IMPORTANT]
> **Two documented parity gaps (web-confirmed, not bugs — surface them honestly):**
> 1. **Deactivate does NOT revoke active sessions.** Web additionally calls service-role `admin.auth.admin.signOut(id)`; mobile can't. A deactivated user's current session persists until token expiry. Mobile sets `is_active = false` and shows a note that immediate session revocation requires the web portal.
> 2. **Role/department edit does NOT sync Auth metadata.** Web additionally calls service-role `updateUserById` to sync `user_metadata`. Mobile can't. This is acceptable because app role checks are **profile-based** — the `profiles.role` UPDATE is authoritative for access control; the metadata desync is secondary.

> [!IMPORTANT]
> **Admin-as-Receptionist REUSES existing receptionist screens.** Do NOT rebuild the document detail / approve-route / reject-with-reason UI. The admin routes into the same receptionist workstation components built in phases R1–R5. The only difference is entry point (admin queue) and that admin is not department-limited.

## Confirmed Backend
- `profiles.is_active boolean DEFAULT true NOT NULL` — exists.
- `CREATE POLICY "Admins have full access to profiles" ON public.profiles FOR ALL USING (public.get_auth_user_role() = 'admin')` — exists; FOR ALL covers UPDATE.
- Allowed roles: `admin, receptionist, department_staff, medical_specialist, patient`.
- Department values: `laboratory, imaging, ultrasound, ecg`.
- Receptionist write operations (approve/route → `patient_queue` + `documents`; reject → `documents`) already implemented in R1–R5 and RLS-permitted; admin (via FOR ALL / oversight policies) can perform the same.

## Open Questions
*None.* Schema + RLS confirmed against the file. Parity gaps documented.

---

## Proposed Changes

### 1. Repository — staff writes
#### [MODIFY] lib/features/admin/data/admin_repository.dart
- `setStaffActive({ required String userId, required bool isActive })`:
  - UPDATE `profiles` SET `is_active` = isActive WHERE id = userId.
  - Runs under the admin session (FOR ALL policy). No service-role.
  - Returns updated row; surface errors (no silent catch).
- `updateStaffRole({ required String userId, required String role, String? department })`:
  - UPDATE `profiles` SET `role` = role, `department` = department WHERE id = userId.
  - `role` ∈ {admin, receptionist, department_staff, medical_specialist, patient}.
  - `department` ∈ {laboratory, imaging, ultrasound, ecg} or null (null for non-department roles like receptionist/specialist/admin/patient).
  - Runs under admin session. No metadata sync (documented gap).
- Do NOT add `createStaff` or `sendPasswordReset` — service-role, web-only, out of scope permanently.

### 2. Repository — admin receptionist actions
#### [MODIFY] lib/features/admin/data/admin_repository.dart (or reuse ReceptionRepository directly)
- Prefer reusing the existing `ReceptionRepository` methods for approve/route/reject rather than duplicating. If the reception repo resolves identity/queue-number generation the same way, the admin just calls it. Confirm the reception repo methods don't hard-assume a receptionist-only session; if they do, adapt minimally so an admin session can call them (RLS still governs).
- Operations: approve+route (INSERT `patient_queue` with generated queue number + UPDATE `documents`), reject (UPDATE `documents` with reason). Same as R1–R5.

### 3. Provider
#### [MODIFY] lib/features/admin/presentation/providers/admin_provider.dart
- Add: `toggleStaffActive(userId, isActive)`, `editStaffRole(userId, role, department)` → call repo, on success refresh the staff list + dashboard active-staff count. Surface errors.
- Reuse the existing reception provider/flow for the document actions rather than re-implementing triage state.

### 4. Screens — Staff Management (now write-capable)
#### [MODIFY] lib/features/admin/presentation/screens/admin_staff_screen.dart
- Enable the per-staff edit affordance (removed/disabled in A1).
- Tapping a staff row (or an edit icon) opens an **Edit Staff** sheet/screen:
  - Read-only: name, email.
  - **Active toggle** → activate/deactivate (`is_active`). On deactivate, show the parity note: "Marked inactive. The user's current session remains valid until it expires; for immediate sign-out, use the web portal."
  - **Role dropdown** (5 roles) + **Department dropdown** (4 depts, shown only when role = department_staff; hidden/null otherwise).
  - Save → repo update → refresh list.
  - **NO "Add Staff" button, NO "Send Password Reset"** — those are web-only. If helpful, show a static note: "Account creation and password resets are managed on the web portal."
- Deactivated staff visually distinct (dimmed / "Inactive" badge).

### 5. Screens — Admin Reception Queue (now interactive)
#### [MODIFY] lib/features/admin/presentation/screens/admin_queue_screen.dart
- Tapping a submission opens the **existing receptionist document detail** screen (reused from R1–R5), where the admin can view the document and approve/route/reject.
- Admin is NOT department-limited (unlike a receptionist scoped to their function) — but the actions themselves are identical.
- After an action, return to the queue and refresh counts/status.
- Approve/route generates a queue number via the existing helper (PHT start-of-day), same as receptionist.

### 6. Constraint note
- Do NOT rewrite Constraint #10/#12 in A2 (that's A4). But the walkthrough should note that admin is now performing RLS-governed writes (staff management + reception triage), setting up the A4 rewrite.

---

## Verification Plan

> Standing rule: assert user-observable correctness. Deactivating staff X actually flips X's `is_active`; editing X's role actually persists; approving document Y actually routes Y. Not just "the button exists."

### Automated Tests

#### [NEW] test/phase_a2_staff_writes_test.dart
1. Activate/deactivate → UPDATE `profiles.is_active` with correct boolean for the correct user.
2. Deactivate shows the session-persistence parity note.
3. Edit role → UPDATE `profiles.role`; department set when role=department_staff, null otherwise.
4. Role dropdown offers exactly the 5 valid roles; department exactly the 4 valid depts.
5. **RLS path test (the caveat):** admin session UPDATE succeeds; a NON-admin session attempting the same UPDATE fails (proves the FOR ALL policy governs, not the self-update path). This is the crafted-request test.
6. After write, staff list + active-staff dashboard count refresh.
7. NO create-staff / password-reset controls present (assert absent).
8. Save error surfaces visibly (no silent catch).

#### [NEW] test/phase_a2_admin_receptionist_test.dart
9. Tapping a queue submission opens the reused receptionist document-detail screen.
10. Admin approve+route → INSERT patient_queue (queue number generated) + UPDATE documents; queue refreshes.
11. Admin reject with reason → UPDATE documents with reason; status flips to rejected.
12. Actions reuse the existing reception components (not a rebuilt UI) — assert the shared screen/widget is used.
13. Post-action queue counts update.

### Regression
```bash
flutter analyze
flutter test test/phase_r2_approve_route_test.dart      # reception approve/route still green
flutter test test/phase_r3_reject_test.dart              # reception reject still green
flutter test test/phase_a1_admin_read_views_test.dart    # A1 reads unaffected
flutter test
```
- If reused reception repo/screens are adapted for admin, confirm the R-phase tests still pass unchanged.

### Manual Verification (real device)
1. Admin → Staff Management → deactivate a staffer → `is_active` flips, row shows Inactive, parity note shown.
2. Reactivate → flips back.
3. Edit a staffer's role (e.g. department_staff → receptionist) → persists; department clears when role no longer department-based.
4. Change a department_staff member's department (laboratory → imaging) → persists.
5. Cross-check on web: the same `profiles` row reflects the change (parity, minus the documented metadata/session gaps).
6. Confirm NO Add Staff / password-reset on mobile.
7. Admin → Reception Queue → tap a Submitted document → detail opens → approve+route → patient appears in the department queue with a queue number.
8. Tap another → reject with reason → moves to Rejected.
9. Deactivate a staffer, then confirm the parity gap honestly: their existing session still works until expiry (expected; note it).
10. APK grep: still zero service-role/secret keys.

---

## Out of Scope
- **A3** — RAG delete.
- **A4** — Constraint #10/#12 rewrite + consolidation + defense narrative.
- Account creation, password-reset emails, session revocation, Auth-metadata sync → permanently web-only (service-role).
- No `status` column (it's `is_active`).

---

## Build Rules
- SPEC locked. No scope creep. No service-role, ever — APK grep stays clean.
- Column is `is_active` boolean, not `status`.
- Admin writes run under the admin JWT so the FOR ALL policy applies (not the self-update path). Prove with the RLS crafted-request test.
- REUSE receptionist screens for document actions — do not rebuild triage UI.
- Surface the two parity gaps in UI/notes; don't hide them.
- Every write validates + surfaces errors visibly; no silent catch.
- Tests assert user-observable correctness (the right row actually changed), not just render.
- Atomic order: repo staff-writes → repo/reuse reception actions → provider → staff edit screen → admin queue wiring → tests.
- flutter analyze clean after each group; tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase ref — placeholder. RLS governs writes.
- No image/mockup generation. Concise walkthrough.
- Full suite green before Gate D.
