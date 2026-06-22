# KlinikAid Mobile Guide — Staff Scope Addendum (Phases 7-9)

> **Companion to `klinikaid_mobile_guide.md`.** This file documents the new
> Phases 7, 8, and 9 added after the 2026-06-11 scope expansion. The original
> guide covers Phases 0-6 (patient flow), which remain unchanged. Renumbered:
> the original Phase 7 (Testing, hardening & release) becomes Phase 9.
>
> **Audience:** read alongside `MASTER_CONTEXT.md`. Both files apply to every
> phase from 7 onward. The 12 non-negotiable constraints in Master Context
> Section 4 are binding for every staff feature.

---

## Scope reminder — the staff role policy

The mobile app is **patient-primary, staff-scoped**. The web portal remains the
primary staff interface. Mobile gives staff a **read-only** companion
experience for on-the-go use.

| Role | On mobile? | Mobile scope |
|---|---|---|
| Patient | ✅ Register + login | Full feature set (Phases 0-6) |
| Receptionist | ✅ Login only | Document lookup only (read-only; three sub-tabs) |
| Department Staff | ✅ Login only | Department queue + records view (scoped to their `department`, read-only) |
| Medical Specialist | ✅ Login only | Cross-department patient/queue/records view (read-only) |
| **Admin** | **❌ BLOCKED** | **Login rejected; web portal only** |

**Things staff CAN do on mobile:**
- Sign in with email + password (existing account created by Admin on web).
- View data their role + RLS permits in a read-only screen.

**Things staff CANNOT do on mobile (web-portal only):**
- Mark queue entries as arrived or update queue status.
- Approve or reject document submissions.
- Create new patient records (walk-ins).
- Enter new lab/imaging/ECG values into `department_records`.
- Edit clinic policies, working hours, or service catalog.
- Create or edit staff accounts.
- View audit logs.
- Run analytics or generate reports.

---

## Phase 7 — Role-aware login & routing

**Goal:** the existing login flow becomes role-aware. After login, the app reads
`profiles.role` and routes to the correct home screen. Admins are blocked at login.
Register continues to hard-code `role='patient'`.

### Tasks (Gate B plan should cover all of these)

1. **Login response handling.** After `auth.signInWithPassword()` succeeds, fetch
   the user's `profiles` row, read `profiles.role`, and stash it in an auth state
   object the router can read.
2. **Admin-block at login.** If `role == 'admin'`, immediately call `auth.signOut()`
   and show a modal: *"Admin accounts must sign in via the web portal."* No
   dashboard reached. No session retained.
3. **Role-based routing.** Update `app_router.dart` to branch on `role`:
   - `patient` → `/patient` (existing dashboard from Phase 3)
   - `receptionist` → `/staff/reception`
   - `department_staff` → `/staff/department/:department` (use `profiles.department`)
   - `medical_specialist` → `/staff/specialist`
4. **Register screen lockdown.** Audit `register_screen.dart` — confirm the
   `auth.signUp()` call hard-codes `data: { 'role': 'patient' }` and exposes no
   role selector in the UI. If exposing one, remove it.
5. **Session restore branching.** On app launch, if a session exists, fetch
   `profiles.role` before showing any home screen. Route accordingly.
6. **Logout consistency.** All four role home screens use the same `signOut()`
   flow back to `/login`.
7. **A "switch role" trick must NOT be possible.** A patient who somehow gets a
   staff role assigned (only Admin can do this, via web) must explicitly log out
   and log back in for the role change to take effect. Cached state from the prior
   role should be purged on logout.

### Files to create / modify

- `lib/features/auth/presentation/providers/auth_provider.dart` — add `role` field
  to auth state; populate after login.
- `lib/features/auth/presentation/screens/login_screen.dart` — add admin-block
  modal handler.
- `lib/features/auth/presentation/screens/register_screen.dart` — verify role
  hard-coding.
- `lib/core/routing/app_router.dart` — branch by role on login + session restore.
- `lib/features/staff/` — new top-level directory.
  - `lib/features/staff/presentation/screens/reception_home_screen.dart` —
    placeholder for Phase 8.
  - `lib/features/staff/presentation/screens/department_home_screen.dart` —
    placeholder.
  - `lib/features/staff/presentation/screens/specialist_home_screen.dart` —
    placeholder.

### Tables touched

- `profiles` — read-only (read `role`, `department` after sign-in).
- No writes. No new tables. No schema changes.

### Exit criteria

- [ ] Login as a `patient` account routes to the existing patient dashboard.
- [ ] Login as a `receptionist` account routes to the reception home placeholder.
- [ ] Login as a `department_staff` account routes to the department home
      placeholder, with the correct `department` in the URL/state.
- [ ] Login as a `medical_specialist` account routes to the specialist home
      placeholder.
- [ ] Login as an `admin` account is **rejected** with a clear message; no
      dashboard is reached; session is terminated.
- [ ] Register screen produces only `role='patient'` accounts. Verified by
      registering a test user and reading the resulting `profiles.role` from
      Supabase Table Editor.
- [ ] Session restore on app launch reads the role and routes correctly even if
      the patient closed the app on a staff screen (or vice versa).
- [ ] Logout fully purges role-tied cached state.

### Reviewer focus (Gate D)

- Inspect the actual `auth.signUp()` call site for the role hard-coding.
- Walk through the admin-block flow on the emulator with a real admin account
  (use Supabase Auth UI to manually set a test user's `profiles.role = 'admin'`,
  then attempt login).
- Verify all four routes work via the router code (not just claim — show the
  code).

---

## Phase 8 — Staff mode (read-mostly)

**Goal:** populate the three staff home screens with the actual scoped read views
and the minimal state changes specifically permitted per role.

### Three staff home screens

#### 8a. Reception Home (`receptionist` role)

**Primary view:** Document lookup view (Pending / Approved / Rejected).

**Permitted actions on mobile:**
- View documents (in the "Documents" tab layout) in a read-only list with status badges and timestamps.
- Tap a document card to open a read-only details modal showing extended metadata and OCR preview.

**Out of scope on mobile (web only):**
- Today's Queue view (hidden from UI, queue management belongs to the web portal).
- "Mark as arrived" (updating queue status).
- "Approve / Reject" documents.
- Adding new patients (walk-in entry).
- Re-ordering the queue.
- Editing patient profile fields.
- Generating reports.

#### 8b. Department Home (`department_staff` role, scoped to their `department`)

**Primary view:** today's `patient_queue` filtered to the staff's department, plus
the most recent `department_records` they've entered (read-only — entries happen
on web).

**Permitted actions on mobile:**
- Tap a queue entry → details modal showing the patient's profile + that patient's `department_records` from
  this department.

**Out of scope on mobile:**
- "Mark in progress / completed" (updating queue status).
- Entering new lab values into `department_records` (web only).
- Editing existing records.
- Accessing other departments' data.

#### 8c. Specialist Home (`medical_specialist` role)

**Primary view:** searchable patient list. Tap a patient → that patient's
cross-department `department_records` timeline.

**Permitted actions on mobile:**
- Read-only viewing across departments.
- (No state changes from mobile — specialists annotate / interpret on web.)

**Out of scope on mobile:**
- Analytics dashboards / charts (web only).
- Trend reports.
- Comparing patients side-by-side (web only).

### Tasks (Gate B plan should cover all of these)

1. **Reception queue provider + screen.** Read `patient_queue` ordered by
   `created_at`. Realtime subscription for live updates. Tap-into details.
2. **Reception document review.** Pending `documents` list. Approve/reject UI with
   rejection reason input.
3. **Department queue provider + screen.** Filter by `profiles.department` (from
   the auth state). Realtime subscription.
4. **Department records view.** Read-only list of `department_records` for the
   staff's department, most recent first.
5. **Specialist patient search.** Search `patients` by name. Tap into a patient
   to see their `department_records` timeline.
6. **Empty / error states.** All three screens handle: no data yet, network error,
   RLS denied (shouldn't happen if role is correct, but handle anyway).
7. **Cross-role data leakage check.** Verify that signing in as one staff role
   does NOT expose another role's data even by accident. E.g., a department_staff
   in laboratory cannot see imaging's `department_records` even by manipulating
   URLs.

### Files to create / modify

Per the structure established in Phase 7:

- `lib/features/staff/data/repositories/staff_queue_repository.dart` (shared
  across the three home screens; respects RLS server-side and applies extra
  role-filter logic client-side as defense-in-depth).
- `lib/features/staff/presentation/providers/reception_provider.dart`
- `lib/features/staff/presentation/providers/department_provider.dart`
- `lib/features/staff/presentation/providers/specialist_provider.dart`
- `lib/features/staff/presentation/screens/reception_home_screen.dart` (real)
- `lib/features/staff/presentation/screens/department_home_screen.dart` (real)
- `lib/features/staff/presentation/screens/specialist_home_screen.dart` (real)
- `lib/features/staff/presentation/widgets/queue_entry_card.dart`
- `lib/features/staff/presentation/widgets/document_review_card.dart`
- `lib/features/staff/presentation/widgets/patient_search_field.dart`
- Tests:
  - `test/phase8_staff_reception_test.dart`
  - `test/phase8_staff_department_test.dart`
  - `test/phase8_staff_specialist_test.dart`

### Tables touched

| Table | Reception | Department staff | Specialist |
|---|---|---|---|
| `patient_queue` | Read all + UPDATE status | Read scoped + UPDATE status | Read all (read-only) |
| `documents` | Read all + UPDATE status (approve/reject) | — | — |
| `patients` | Read all (linked from queue) | Read all (linked from queue) | Read all (search + detail) |
| `department_records` | — | Read scoped to own department | Read all (read-only) |
| `profiles` | Read all (linked from queue) | Read scoped | Read all (linked from patients) |

**RLS is the canonical source of truth.** The mobile app does not "implement"
permissions — it just calls Supabase and trusts what RLS returns. The role check
on the client side is for UX (showing the right screens), not for security.

### Exit criteria

- [ ] Each of the three staff roles, on logging in, sees a populated home screen
      with real data from the shared Supabase project.
- [ ] Receptionist can mark a queue entry as arrived; UI updates live via
      Realtime; database confirms the `status` change.
- [ ] Receptionist can approve and reject documents; rejections require a reason;
      patient (in a separate device/session) sees the status flip live.
- [ ] Department staff sees only their own department's queue and records — verify
      with a multi-department test (e.g., two `department_staff` users in
      different departments cannot see each other's data).
- [ ] Specialist can search and view any patient's cross-department records;
      no state changes possible from this screen.
- [ ] No staff role can see another role's-only UI (e.g., a `department_staff`
      cannot deep-link to `/staff/reception`).
- [ ] All three home screens handle offline gracefully (cached last view + offline
      banner; no crashes).

### Reviewer focus (Gate D)

- Live demo of each of the three roles, signed in on the emulator, showing the
  correct home screen and the correct data.
- Cross-role isolation check: sign in as `department_staff` in `laboratory`,
  attempt to navigate to `/staff/department/imaging`. The app must refuse
  (either redirect, or show "department mismatch" guard, or rely on RLS to
  return empty — any of these is acceptable as long as no imaging data leaks).
- Realtime live update demo: from Supabase SQL editor, INSERT a new queue entry;
  watch the receptionist screen update without a refresh.

---

## Phase 9 — Testing, hardening & release

> *Renumbered from the original Phase 7. Now expanded to cover staff features
> too.*

**Goal:** comprehensive testing across all roles, security hardening, ISO 25010
evaluation including the new staff scope, release APK.

### Tasks

1. **Patient regression suite.** All Phase 0-6 functionality still works after
   the role-aware routing changes.
2. **Staff functional tests.** Each of the three staff roles' permitted actions
   and read scopes are tested end-to-end.
3. **Admin-block security test.** An admin account cannot reach any mobile screen
   beyond the login error modal. Tested with a real admin account.
4. **Cross-role isolation test.** RLS + client guards prevent any role from
   accessing another role's data through any path (deep links, URL manipulation,
   stored sessions, etc.).
5. **ISO 25010 evaluation.** Now includes the four user populations (patient +
   three staff roles).
6. **APK security pass.** Decompile APK, `grep` for `AIzaSy`, `GEMINI`,
   `service_role`. Zero matches expected.
7. **Mobile/web integration test.** A receptionist signs in on mobile, marks a
   patient as arrived; the web portal's queue updates live. A patient on mobile
   submits a document; the receptionist on mobile reviews and approves it; the
   patient sees the status change live. This is the cross-app workflow demo.
8. **Release APK.** Signed, versioned, ready for the defense demo.

### Exit criteria

- [ ] All Phase 0-8 features work in the release APK.
- [ ] ISO 25010 evaluation covers all four user populations.
- [ ] No Gemini key or `service_role` key in the APK (verified by decompile).
- [ ] Cross-app integration demo works as scripted.
- [ ] Admin-block enforced and demonstrated.
- [ ] Capstone paper Chapter 4 updated to reflect the staff scope (or staff
      scope documented as an addendum if the paper text can't be amended).

### Reviewer focus (Gate D)

- Side-by-side demo: mobile + web at the same time, multiple roles signed in.
- The full security pass (decompile + greps).
- ISO 25010 results recorded.
- A clean release APK is produced.

---

## Reviewer notes for the agent

1. **The web portal is the source of truth for staff workflows.** When in doubt
   about a UX detail, look at how the web team handled it — don't invent.
2. **RLS is the security boundary.** Client-side role checks improve UX but are
   never the only check. Every database query relies on RLS to filter.
3. **No new tables in Phases 7-9.** Everything is read against existing tables.
   If a feature requires a schema change, file it in `schema_proposals.md` and
   stop.
4. **State changes from mobile are narrow.** Only the specifically-listed UPDATE
   operations are permitted from mobile. Anything else — new patients, new lab
   values, new policies — is web-portal work.
5. **The four-gate phase protocol applies to Phases 7-9.** Each phase: Plan ->
   Gate B review -> Build -> Gate D review. Don't skip Gate B. The reviewer will
   refuse to substantively review a Phase 8 walkthrough that didn't go through
   Gate B first — this commitment from Phase 6 still stands.
