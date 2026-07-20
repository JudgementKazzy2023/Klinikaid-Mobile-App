# SPEC — Admin RBAC Viewer (read-only) + Staff Edit Update

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates plan
(Gate B) + on-device walkthrough (Gate D).**

Two deliverables in one build cycle:
1. **RBAC Viewer** — a read-only "Role & Access Management" screen on mobile
   admin, showing all roles (system + custom) and their granted permissions.
2. **Staff-edit parity** — update the admin staff-edit flow to support custom
   roles in the role dropdown + position title(s) editing.

Plus: explicitly document **why staff creation is web-only** (for the defense
narrative, not a build).

---

## STANDING RULES (self-contained)
- **Investigate before changing** — report current state first.
- **Trim testing:** one regression guard + one happy path per change; touched
  test files during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth) — no live client in tests.
- **Real-device verification** mandatory.
- No native/dep change expected → **release build not required** (state it).
- No images/mockups. Terse pass/fail. Don't claim a check you didn't run.

---

## WHY STAFF CREATION IS WEB-ONLY (document, don't build)

Staff account creation requires:
- **Supabase Auth admin API** (`auth.admin.createUser`) — needs the **service
  role key**, which mobile **never holds** (anon key only).
- **Password-reset email** — triggered server-side via the service role.
- **Auth-metadata sync** — setting role/profile data atomically with the auth
  record.

These are **permanently web-only by architectural design**, not a missing
feature. The mobile app's security model (anon key + RLS only) deliberately
excludes service-role operations so the APK contains no privileged credentials.
This is consistent across the entire mobile app: staff creation, password-reset
emails, session revocation, and RAG document upload/embedding are all web-only
for the same reason.

**Defense line:** *"Staff account creation requires the service-role key for
server-side auth operations. The mobile client carries only the public anon key
by design — privileged operations stay on the web portal, so the APK contains
no administrative credentials."*

Write this into the admin mobile docs / MASTER_CONTEXT at closeout if not
already there. Do NOT attempt to build staff creation on mobile.

---

## INVESTIGATE FIRST

1. **New RBAC tables.** The permission flip added tables (`roles`,
   `permissions`, `role_permissions`, `user_roles` or similar). Confirm the
   exact table/column names and their RLS — can admin SELECT all roles +
   permissions? (Admin should be able to read the full role catalog for the
   viewer.)

2. **Staff edit — current mobile state.** The admin staff-edit currently has a
   role dropdown with the 4 system roles (`admin`, `department_staff`,
   `medical_specialist`, `receptionist`). Confirm:
   - Where the role list is sourced (hardcoded enum? query?).
   - Whether `employee_type` (position titles) editing exists yet on mobile.
   - How `role` is stored on profiles now — still a string, or a `role_id` FK
     to the new `roles` table?

3. **Custom roles shape.** From the web screenshots:
   - System roles: `admin` (13 perms), `department_staff` (4), `medical_specialist` (5),
     `patient` (2), `receptionist` (5).
   - Custom roles: e.g. "Limited Receptionist" — cloned from a system template,
     with modified permissions, marked `CUSTOM`.
   - Each role has: `name`, `description`, `is_system` flag, granted permissions
     list.
   - Confirm the exact schema from the DB.

4. **Permissions catalog.** Web groups permissions by category (ADMIN, AUDIT,
   DOCUMENTS, etc.). Each permission has an id + a human description. Confirm
   where this is defined (a `permissions` table? constants?).

Report all findings before coding.

---

## Part 1 — RBAC Viewer (read-only)

A new **"Role & Access Management"** screen accessible from the admin
navigation (sidebar / drawer). **Strictly read-only** — admin can view, not
create/edit/delete roles or permissions on mobile.

### What it shows (mirror web's Role Management page, read-only)
- **All roles** — system + custom — rendered as cards.
- Per role card:
  - Role **name** + badge (`SYSTEM` or `CUSTOM`).
  - **Description** (one-liner).
  - **Granted permissions count** + the permission list (as chips/tags).
  - For custom roles: which system role it was **cloned from** (if that data is
    stored — check schema).
- **Permissions catalog** — optionally a separate section or expandable, showing
  all available permissions grouped by category (ADMIN, AUDIT, DOCUMENTS, etc.)
  with their descriptions. This helps admin understand what each permission
  means.

### What it does NOT do (web-only)
- No "Build Custom Role" — no create/edit/delete roles on mobile.
- No "Toggle Permissions" — no permission assignment on mobile.
- No "Save Custom Role" button.
- Display a subtle note: *"Role creation and editing is available on the web
  portal."* — so it's clear this is intentionally read-only, not broken.

### Data source
- Query the roles + role_permissions + permissions tables (the new RBAC schema).
- **Read-only** — only SELECT. No INSERT/UPDATE/DELETE.
- Admin RLS must allow reading all roles + permissions (confirm in
  investigate-first).

---

## Part 2 — Staff-edit update

Update the existing admin staff-edit flow to reflect the new RBAC:

### Role dropdown — now includes custom roles
- Currently hardcoded to 4 system roles → **query the `roles` table** instead
  and populate the dropdown dynamically.
- Show both system AND custom roles (e.g. "Limited Receptionist (Custom)").
- Display the role type (`SYSTEM` / `CUSTOM`) as a subtle indicator in the
  dropdown items.
- On save, write the selected **`role_id`** (or whatever the new FK is) — NOT
  the old role string, if the schema changed. Confirm the write target in
  investigate-first.

### Position title(s) — `employee_type` editing
- Web shows a chip/tag input with "Add" button for position titles.
- **If #11 is still mid-change on web** (it was parked earlier): mirror the
  CURRENT web behavior, knowing it may evolve. The #11 brief already defines
  pipe-delimited storage — use that format.
- Add a chip/tag input to the edit panel. Admin adds/removes titles. Serialize
  to pipe-delimited on save. Parse on `|` for display.
- "Optional display labels only. System role still controls access permissions."
  — show this note under the input (web has it).

### Other edit fields (confirm parity)
- Web's edit panel shows: Full Name, Email Address (read-only?), Account
  Password (Send Password Reset — **web-only, service-role**), Position(s)/
  Title(s), Role dropdown.
- Mobile should show: Full Name (editable), Email (read-only — changing email
  is a service-role op), Position(s)/Title(s), Role dropdown, Department,
  Active/Inactive toggle.
- **Do NOT add** "Send Password Reset Email" on mobile — service-role op,
  web-only.

---

## Tests (mocked)

- **Widget — RBAC viewer:** renders system + custom role cards with correct
  permission counts and badges; no create/edit buttons exist; the "web portal"
  note is visible.
- **Widget — staff-edit role dropdown:** populated from (mocked) roles query,
  includes custom roles; selecting a custom role writes the correct `role_id`.
- **Widget — position titles:** adding/removing titles serializes to
  pipe-delimited; display parses chips from pipe-delimited string.
- **Regression:** existing staff activate/deactivate + department edit still
  works after touching the edit screen.

## Real-device verification

1. Admin → Role & Access Management → all system roles (admin, dept_staff,
   medical_specialist, patient, receptionist) + any custom roles visible with
   permissions listed. No create/edit controls.
2. Admin → Staff Management → edit a staff member → role dropdown shows custom
   roles alongside system roles → select one → save → role updates.
3. Same edit → add/remove position title(s) → save → titles display as chips,
   stored pipe-delimited.
4. Confirm "Send Password Reset" is NOT present on mobile.
5. No native/dep change → release build not required (state it).

## Files affected (expected)

**New:**
- RBAC viewer screen (admin feature)
- RBAC data model / repository (roles + permissions read)
- tests

**Modified:**
- admin staff-edit screen (dynamic role dropdown + position titles input)
- admin staff repository / provider (query roles table instead of hardcoded
  enum)
- admin navigation (add Role & Access Management entry)

No schema changes. No service-role. No write to roles/permissions tables.
Staff creation stays web-only (documented above, not built).
