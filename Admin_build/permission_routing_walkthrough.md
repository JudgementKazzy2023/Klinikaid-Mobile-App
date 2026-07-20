# Permission-Based Mobile Routing Walkthrough

## Scope

This is a mobile-only routing/navigation change.

- No DB changes
- No RLS changes
- No Edge Function changes
- No web changes
- `profiles.role` and dual-write remain untouched
- Patient routing remains role-based

## What Changed

### Permission Constants

Added all 23 permission strings byte-exact in:

`lib/core/permissions/permission_constants.dart`

### Permission Loading

Added:

`lib/core/permissions/permission_service.dart`

`AuthProvider` now:

- reads `profile.roleId`
- loads permissions from `role_permissions` joined to `permissions`
- caches them as `Set<String>`
- exposes `hasPermission`, `hasAllPermissions`, and `hasAnyPermission`
- clears permissions on logout/session cleanup
- falls back to legacy role routing if `role_id` is missing, permission loading fails, or permissions are empty
- logs when fallback activates

### Route Policy

Added:

`lib/core/permissions/permission_route_policy.dart`

The policy enforces:

- Reception Queue/Documents: `documents.manage` AND `queue.manage`
- Department routes: `records.manage` OR `records.manage.own_dept`
- Specialist Dashboard: `specialist.analytics`
- Specialist Patients: `specialist.patients`
- Specialist Records: `specialist.records`
- Admin Staff: `staff.manage`
- Admin Roles: `roles.read`
- Admin Logs: `system_logs.read` OR `chatbot_logs.read`
- Admin RAG: `rag_documents.manage`

Shell selection rule:

1. Patient stays role-based.
2. If permissions are unavailable, legacy `profiles.role` routing is used.
3. If permissions are loaded, the legacy role picks the shell only when that shell is valid for the permission set.
4. If legacy role and permissions disagree, the app routes to the first shell with a permitted feature.

### Navigation Visibility

Updated:

- `AdminShell`
- `ReceptionShell`
- `DepartmentShell`
- `SpecialistShell`
- `AdminLogsScreen`

Restricted nav items/tabs are hidden, and restricted data loads are not kicked off during shell initialization.

### Document Validation Back Navigation

Fixed:

`DocumentValidationScreen` no longer branches on `UserRole.admin`.

Routes now pass an explicit return route:

- `/reception/document/:id` returns to `/reception/queue`
- `/admin/document/:id` returns to `/admin/queue`

The screen also uses `context.pop()` first when there is navigation history.

## Verification Completed

Passed:

- `flutter analyze --no-fatal-infos` on touched files
- `flutter test test/permission_routing_test.dart`
- `flutter test test/phase7_role_routing_test.dart`
- `flutter test test/csv_export_test.dart`
- `flutter test`

Full suite result:

- 493 passed
- 2 skipped
- 0 failed

Notes:

- Analyzer still reports existing info-level notes, mostly pre-existing `print` usage and style/deprecation hints.
- No release APK build was run because the spec says no native/dependency change is expected and release build is not required.
- `test/permission_routing_test.dart` is currently ignored by `.gitignore` via `test/`, so it exists locally and was run, but will not be included in a normal commit unless intentionally unignored or force-added.

## Real-Device Gate D

Use production-facing mobile config carefully.

1. Log in as full admin.
   - Admin dashboard opens.
   - Staff, Queue, Records, Logs, RAG, Role & Access show according to the full admin permission set.
   - Admin without AAL2 still goes to MFA.

2. Log in as full receptionist.
   - Reception shell opens.
   - Dashboard, Queue, Profile are visible.
   - Queue opens normally.

3. Log in as Limited Receptionist with `documents.manage` + `queue.manage`.
   - Reception shell opens.
   - Queue is visible.
   - Screens without granted permissions are hidden or blocked.

4. Log in as a custom role with specialist permissions only.
   - App routes to specialist shell.
   - Dashboard appears only with `specialist.analytics`.
   - My Patients appears only with `specialist.patients`.

5. Log in as patient.
   - Patient shell and tabs are unchanged.

6. Open document validation from reception and admin routes.
   - Back button returns to the correct source route.
   - It must not use role-string guessing.

7. If possible, test a profile with missing `role_id`.
   - App should fall back to legacy role routing.
   - Fallback log should appear.
