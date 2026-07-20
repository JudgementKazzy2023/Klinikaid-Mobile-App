# SPEC — Permission-Based Route Guards (replace legacy role-string routing)

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates plan
(Gate B) + on-device walkthrough (Gate D).**

Replace mobile's legacy `profiles.role` string-based route guards with
**permission-based** guards, matching web's enforcement exactly. This fixes
custom roles being misrouted (a custom "Lab Supervisor" currently gets
receptionist screens regardless of its actual permissions).

---

## STANDING RULES (self-contained)
- **Investigate before changing** — report current state first.
- **Trim testing:** one regression guard + one happy path; touched test files
  during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth) — no live client in tests.
- **Real-device verification** mandatory.
- No native/dep change expected → **release build not required** (state it).
- No images/mockups. Terse pass/fail. Don't claim a check you didn't run.
- **No DB changes, no RLS changes, no Edge Function changes, no web changes.**
  This is purely mobile client-side routing.

---

## THE MAPPING TABLE (source of truth — match exactly)

| Screen / Area | Permission(s) required | Logic |
|---|---|---|
| Staff Management | `staff.manage` | — |
| Role Management (view) | `roles.read` | — |
| Role Management (create/edit/delete) | `roles.manage` | — |
| System Logs | `system_logs.read` | — |
| Chatbot Logs | `chatbot_logs.read` | — |
| RAG Manager | `rag_documents.manage` | — |
| Reception Queue / Documents | `documents.manage` + `queue.manage` | **AND** |
| Department Records / Daily Queue | `records.manage` / `records.manage.own_dept` | **ANY** |
| Department OCR Entry | `records.manage` / `records.manage.own_dept` | **ANY** |
| Specialist Dashboard | `specialist.analytics` | — |
| Specialist Patients | `specialist.patients` | — |
| Specialist Records | `specialist.records` | — |
| Patient documents storage read | `storage.patient_documents.read` | — |
| Patient chat | `chat.access` | — |
| Patient screens (dashboard/submissions/results) | **role-based, no permission gate** | route by role |

**AND = user must have ALL listed permissions.**
**ANY = user must have at least ONE.**
**Single = just that one permission.**
**Patient = keep current role-based routing, unchanged.**

---

## FULL PERMISSION CATALOG (match these strings byte-exact)

```
staff.manage
roles.manage
roles.read
system_logs.read
chatbot_logs.read
rag_documents.manage
documents.manage
queue.manage
queue.manage.own_dept
queue.read
records.manage
records.manage.own_dept
patients.manage
patients.read
profiles.manage
profiles.read_staff
specialist.analytics
specialist.patients
specialist.records
storage.patient_documents.read
chat.access
ocr_rows.manage.all
ocr_rows.manage.own
```

Store these as **constants** in a shared file (e.g. `lib/core/permissions/
permission_constants.dart`). Never use raw strings scattered across the
codebase — always reference the constants. Typo in a permission string =
silent misgate.

---

## ARCHITECTURE (3 parts)

### Part 1 — Permission Provider (load at login)

A provider/service that:
1. On successful login, reads the user's `role_id` from their profile.
2. Queries `role_permissions` joined with `permissions` for that `role_id`.
3. Caches the result as a **`Set<String>`** of permission name strings.
4. Exposes:
   - `bool has(String permission)` — single check.
   - `bool hasAll(List<String> permissions)` — AND logic.
   - `bool hasAny(List<String> permissions)` — ANY logic.
5. Refreshes on profile change (e.g. admin changes someone's role mid-session —
   next login picks it up; you don't need real-time refresh).
6. Clears on logout.

**Fallback:** if `role_id` is null OR the permissions query fails (network
error, table issue), **fall back to the legacy `profiles.role` string routing.**
This is belt-and-suspenders during the transition — a broken permission load
must not lock users out of the app entirely. Log when fallback activates so
you can monitor.

### Part 2 — Route Guards (replace role-string checks)

In `app_router.dart`, replace the current role-string checks with permission
checks:

**Before (current — broken for custom roles):**
```dart
if (profile.role == 'admin') → /admin/*
if (profile.role == 'receptionist') → /reception/*
if (profile.role == 'department_staff') → /department/*
if (profile.role == 'medical_specialist') → /specialist/*
if (profile.role == 'patient') → patient routes
```

**After:**
```dart
// Determine which shell/nav to show based on permissions
if (permissions.hasAny(['staff.manage', 'system_logs.read', 'rag_documents.manage', ...])) → admin shell
if (permissions.hasAll(['documents.manage', 'queue.manage'])) → reception shell
if (permissions.hasAny(['records.manage', 'records.manage.own_dept'])) → department shell
if (permissions.hasAny(['specialist.analytics', 'specialist.patients', 'specialist.records'])) → specialist shell
// Patient = role-based (no permission gate)
if (role == 'patient') → patient shell
```

**The shell-selection logic** is the one place where you derive "which broad
navigation does this user see" from their permission set. This is the tricky
design decision — here's how to handle it:

- **System roles** have well-defined permission sets that map cleanly to one
  shell (admin has admin permissions, receptionist has reception permissions,
  etc.).
- **Custom roles** may have a MIX of permissions from different shells. For
  custom roles, pick the shell by **which group of permissions the role has the
  most of**, or by the role's `base_role` as a tiebreaker. Document your rule.
- **If unsure:** ask the web team how web resolves shell/layout for a custom
  role with mixed permissions (e.g. a role with `staff.manage` + `queue.manage`
  — is it admin layout or reception layout?).

### Part 3 — Nav Item Visibility (within a shell)

Within each shell, **hide nav items the user lacks permission for:**

**Admin drawer:**
| Item | Show if |
|---|---|
| Dashboard | always (admin shell) |
| Staff Management | `has('staff.manage')` |
| Role & Access | `has('roles.read')` |
| System Logs | `has('system_logs.read')` |
| Chatbot Audit | `has('chatbot_logs.read')` |
| RAG Manager | `has('rag_documents.manage')` |
| My Profile | always |

**Reception bottom nav:**
| Item | Show if |
|---|---|
| Queue | `hasAll(['documents.manage', 'queue.manage'])` |
| Profile | always |

**Department bottom nav:**
| Item | Show if |
|---|---|
| Daily Queue | `hasAny(['records.manage', 'records.manage.own_dept'])` |
| Records History | `hasAny(['records.manage', 'records.manage.own_dept'])` |
| Profile | always |

**Specialist bottom nav:**
| Item | Show if |
|---|---|
| Dashboard | `has('specialist.analytics')` |
| My Patients | `has('specialist.patients')` |
| Profile | always |

**Patient bottom nav:** unchanged (role-based, all tabs always visible).

---

## INVESTIGATE FIRST

1. **Current route guard code** — confirm exact location + structure in
   `app_router.dart`. How many places check `profile.role`?
2. **`admin_repository` RBAC queries** — confirm the existing queries for
   `roles`, `permissions`, `role_permissions` can be reused by the permission
   provider, or need a separate lightweight query (the provider loads at every
   login, so it should be fast — a single joined query, not three separate).
3. **Shell selection for custom roles** — does web's code resolve which
   layout/shell a custom role gets? If yes, capture the logic. If not, ask.
4. **Other `profile.role` reads** — grep the codebase for all role-string
   usages beyond `app_router.dart` (providers, guards, conditional UI). List
   them — they all need converting or documenting as patient-only.

---

## TESTS (mocked)

- **Unit — permission provider:** loads permissions from mocked
  `role_permissions` + `permissions` query → exposes correct `has`/`hasAll`/
  `hasAny`. Null `role_id` → fallback activated (logged). Empty permissions →
  fallback.
- **Unit — AND vs ANY:** `hasAll(['documents.manage', 'queue.manage'])` returns
  true only when BOTH present; `hasAny(['records.manage',
  'records.manage.own_dept'])` returns true when either present. This is the
  parity-critical test.
- **Widget — nav visibility:** admin shell with `staff.manage` but NOT
  `system_logs.read` → Staff Management visible, System Logs hidden. Reception
  shell without `queue.manage` → Queue tab hidden.
- **Widget — custom role routing:** a custom role with only
  `specialist.analytics` + `specialist.patients` → routes to specialist shell,
  sees Dashboard + My Patients, doesn't see admin/reception/department.
- **Regression:** a standard system-role user (e.g. full admin, full
  receptionist) sees exactly the same screens as before — no tabs lost, no
  routing changed. This is the "we didn't break system roles" guard.

---

## REAL-DEVICE VERIFICATION

1. **System role — admin:** log in → sees all admin drawer items → same as
   before (regression).
2. **System role — receptionist:** log in → receptionist shell, queue visible →
   same as before.
3. **Custom role — Limited Receptionist (has `documents.manage` +
   `queue.manage` + `patients.manage` + `profiles.read_staff`, missing
   `storage.patient_documents.read`):** log in → routes to reception shell →
   Queue visible → any nav item for a permission they lack is hidden.
4. **Patient:** log in → patient shell → all tabs → unchanged (role-based).
5. **Fallback:** (if testable) simulate null `role_id` or failed permissions
   load → falls back to legacy role-string routing → still works, logged.
6. No native/dep change → release build not required (state it).

---

## FILES AFFECTED (expected)

**New:**
- `lib/core/permissions/permission_constants.dart` (string constants)
- `lib/core/permissions/permission_provider.dart` (load + cache + has/hasAll/
  hasAny)
- tests

**Modified:**
- `app_router.dart` (role-string guards → permission guards)
- admin drawer widget (hide items by permission)
- reception/department/specialist nav widgets (hide tabs by permission)
- app initialization / auth flow (load permissions on login, clear on logout)

**Not modified:**
- No DB changes. No RLS changes. No Edge Functions. No web code.
- Patient routing unchanged (stays role-based).
- The `profiles.role` column and dual-write are **untouched** — this spec adds
  permission routing alongside the existing role routing, it doesn't remove the
  column or change the write path. The legacy column retirement is a separate,
  coordinated effort.
