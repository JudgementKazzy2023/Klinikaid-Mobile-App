# RBAC Viewer + Staff Edit Walkthrough

## What changed

- Added a read-only Admin > Role & Access Management screen.
- The viewer reads `roles`, `permissions`, and `role_permissions`, then renders the full role catalog with permission counts and permission chips.
- Mobile role creation/editing remains web-only. There are no create, edit, delete, toggle, or save controls on the RBAC viewer.
- Staff edit now loads roles from the live `roles` table instead of a hardcoded enum list.
- Custom role assignment writes:
  - `profiles.role_id` = selected role id
  - `profiles.role` = selected role's `base_role` from the `roles` table
- Position titles now edit `profiles.employee_type` as pipe-delimited text and render back as chips.
- Staff creation and password reset remain web-only service-role operations.

## Confirmed live schema

- `roles.base_role` exists and is used for custom-role legacy writes.
- `profiles.role_id` exists and FK references `roles.id`.
- `profiles.employee_type` exists as nullable text.
- `get_auth_user_role()` still resolves access from legacy `profiles.role`.
- Admin/staff SELECT policies exist for `roles`, `permissions`, and `role_permissions`.

## Tests run

- `flutter test test\phase_a2_staff_writes_test.dart`
- `flutter test test\phase_a2_admin_receptionist_test.dart test\phase_a3_rag_delete_test.dart`
- `flutter analyze --no-fatal-infos ...`
- `flutter test`

Analyzer note: one pre-existing info remains in `admin_repository.dart` for an existing `print`.

## Gate D real-device checklist

1. Log in as an admin.
2. Open Admin drawer > Role & Access.
3. Confirm all system roles and custom roles are visible, including Limited Receptionist.
4. Confirm permission counts/lists render and no role editing/building controls exist.
5. Open Admin drawer > Staff Management.
6. Edit a staff account.
7. Confirm the role dropdown shows system and custom roles.
8. Select Limited Receptionist and save.
9. Confirm in DB:
   - `profiles.role_id` is the Limited Receptionist role id.
   - `profiles.role` is `receptionist`, copied from `roles.base_role`.
10. Log in as that staff member and confirm they still route to/access receptionist screens.
11. Reopen the staff member in Admin > Staff Management.
12. Add/remove position titles and save.
13. Confirm `profiles.employee_type` is stored pipe-delimited and titles render as chips.
14. Confirm Send Password Reset is not present on mobile.

No native dependency changed, so release build is not required for this gate.
