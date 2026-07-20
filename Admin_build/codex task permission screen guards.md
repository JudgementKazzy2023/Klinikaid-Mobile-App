# SPEC — Permission-Aware Screen Guards (Mobile RBAC Enforcement)

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates plan
(Gate B) + on-device walkthrough (Gate D).**

Complete the RBAC system on mobile: screen/route access is gated by
**permissions**, not just role strings. Custom roles with stripped permissions
are blocked from screens they shouldn't access — matching web's behavior.

---

## STANDING RULES (self-contained)
- **Investigate before changing** — report current state first.
- **Trim testing:** one regression guard + one happy path; touched test files
  during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth) — no live client in tests.
- **Real-device verification** mandatory.
- No native/dep change expected → **release build not required** (state it).
- No images/mockups. Terse pass/fail. Don't claim a check you didn't run.

---

## THE PROBLEM

Mobile route guards check the **old role string** (`profiles.role`). A custom
role like "Limited Receptionist" has `base_role = receptionist`, so
`profiles.role = 'receptionist'` → mobile's guard sees "receptionist" → grants
**full** receptionist screen access, ignoring the permission restrictions.

Web blocks correctly because it checks **permissions**. The DB's RLS also
enforces permissions (the flip landed), so data queries would be denied — but
mobile lets the user **navigate** to the screen first, causing empty/error
states instead of a clean block.

## THE FIX

Mobile reads the user's granted permissions on login and uses them to gate
screen access — same data web already reads, purely a mobile-side routing
change. **No effect on web, no DB changes, no RLS changes.**

---

## INVESTIGATE FIRST

1. **Current route guard mechanism.** Where and how does mobile gate screen
   access? Likely in `app_router.dart` or a guard/redirect callback that checks
   `UserRole`. List every guarded route and what role string it currently checks.

2. **The permission-to-screen mapping.** This is the key data. For each mobile
   screen, which **permission** should gate it? The web team's permission catalog
   (from the RBAC viewer) has these permissions — map them to mobile screens.

   Expected mapping (confirm against the actual web enforcement + permission
   catalog):

   | Mobile Screen | Current Guard (role string) | Required Permission |
   |---|---|---|
   | Reception Queue | `receptionist` | `documents.manage` or `queue.manage` |
   | Document Validation | `receptionist` | `documents.manage` |
   | Dept Records / Result Entry | `department_staff` | `records.manage.own_dept` |
   | Dept Queue | `department_staff` | `queue.manage.own_dept` |
   | Specialist Dashboard | `medical_specialist` | `specialist.patients` |
   | Specialist Records | `medical_specialist` | `specialist.records` |
   | Specialist Analytics | `medical_specialist` | `specialist.analytics` |
   | Admin Dashboard | `admin` | (any admin permission) |
   | Staff Management | `admin` | `staff.manage` or `profiles.manage` |
   | RBAC Viewer | `admin` | (any admin permission) |
   | System Logs | `admin` | `system_logs.read` |
   | Chatbot Audit | `admin` | `chatbot_logs.read` |
   | RAG Manager | `admin` | `rag_documents.manage` |
   | Patient Dashboard | `patient` | (any patient permission) |
   | Patient Submit | `patient` | `ocr_rows.manage.own` |
   | Patient Records | `patient` | (any patient permission) |
   | Patient Chat | `patient` | `chat.access` |

   **Get the definitive mapping from the web team or the web codebase** — don't
   guess. The mapping above is my best estimate from the permission catalog in
   the RBAC viewer screenshots. If web gates a screen on a different permission,
   mobile must match.

3. **How web enforces it.** Check web's routing/middleware — does it check ONE
   permission per page, or does it check for ANY permission in a set? (e.g.
   "admin dashboard requires ANY admin permission" vs "requires
   `system_logs.read` specifically"). Mirror the same logic.

4. **The user's permissions at login.** Mobile already fetches `profiles` on
   login. Does it also fetch `role_id`? If so, the permissions lookup is:
   `role_permissions WHERE role_id = user's role_id` → joined with
   `permissions` → gives the granted permission strings. Confirm the query path
   and whether it can run under the user's own RLS.

Report all findings before coding.

---

## Part 1 — Permission provider (fetch + cache on login)

On successful login / session restore:
1. Read the user's `role_id` from their profile (already fetched, or add to the
   profile query).
2. Query `role_permissions` joined with `permissions` where `role_id` matches →
   get the list of granted permission strings (e.g.
   `['documents.manage', 'queue.manage', 'profiles.read_staff']`).
3. Cache the permission set in the auth provider / a dedicated permission
   provider — available app-wide for guard checks.
4. **On logout:** clear the cached permissions.
5. **On role change (admin edits own role — edge case):** refresh permissions.

**Performance:** this is one query on login, cached for the session. Not
per-screen. Lightweight.

## Part 2 — Screen guards (check permissions, not just role)

Replace or augment the current role-string checks in the router/guard with
permission checks:

**Before:** `if (user.role == 'receptionist') → allow reception screens`
**After:** `if (user.permissions.contains('documents.manage')) → allow reception screens`

For each guarded route, check the **specific permission** from the mapping
(Part 1 investigate). A user without that permission is **redirected** to their
appropriate home screen (or shown an "access restricted" message) — not left
on an empty/error screen.

**System roles (admin, receptionist, etc.) must still work identically.** They
have ALL their permissions granted, so the permission check passes the same
way the old role check did. This is a superset, not a replacement — system
roles see no difference. Only custom roles with stripped permissions see the
change.

**The legacy `profiles.role` string is still used for:**
- The initial routing decision (which home screen to land on — patient vs
  staff). Keep this.
- `get_auth_user_role()` for RLS. Untouched.
- Edge Function role checks (`extract-lab-values`). Untouched.

The permission check is an **additional** gate on top, not a replacement for
the role string. Both must pass.

## Part 3 — Blocked-screen UX

When a user navigates to (or is deep-linked to) a screen they lack permission
for:
- **Do NOT show the screen with empty/error data.** That's the current broken
  behavior.
- **Option A (recommended):** hide the screen from navigation entirely — the
  drawer/nav item doesn't appear if the user lacks the permission. Clean,
  matches web.
- **Option B:** show the nav item but redirect to a "You don't have access to
  this feature" screen on tap. Acceptable but noisier.
- State which you chose.

For admin specifically: if a custom admin role lacks `system_logs.read`, the
"System Logs" drawer item should not appear (or be disabled). Same for
`chatbot_logs.read` → Chatbot Audit, `rag_documents.manage` → RAG Manager,
etc.

---

## Tests (mocked)

- **Unit — permission fetch:** given a mocked `role_id`, the query returns the
  correct permission set; a different `role_id` returns a different set.
- **Unit — guard logic:** user with `documents.manage` → reception screen
  allowed; user WITHOUT it → blocked/redirected. User with all receptionist
  permissions → identical access to old `role == 'receptionist'` check
  (regression).
- **Widget — nav visibility:** a "Limited Receptionist" (missing e.g.
  `chatbot_logs.read`) → the nav items for blocked screens are hidden; granted
  screens are visible.
- **Regression — system roles:** a full `receptionist` / `admin` /
  `department_staff` sees exactly the same screens as before the change (all
  permissions granted → all screens visible).

## Real-device verification

1. Log in as a **system role** (full receptionist) → all receptionist screens
   visible and accessible. **No regression.**
2. Log in as a **custom role** (Limited Receptionist) → screens for stripped
   permissions are **hidden** from nav / blocked on access. Screens for granted
   permissions work normally.
3. Confirm the blocked screens are also blocked at the **data level** (RLS
   denies the query if someone bypasses the UI guard — already true from the
   RBAC flip, just confirm).
4. Admin with a custom limited-admin role → System Logs / Chatbot Audit / RAG
   hidden if permissions stripped.
5. No native/dep change → release build not required (state it).

## Files affected (expected)

**New:**
- Permission provider / service (fetch + cache)
- tests

**Modified:**
- Auth provider (fetch permissions on login, clear on logout)
- Router / route guards (permission checks alongside role checks)
- Navigation drawers / bottom nav (conditionally show/hide based on permissions)

**Not modified:**
- No DB schema changes
- No RLS policy changes
- No web code changes
- No Edge Function changes
- `profiles.role` string still written + used for initial routing + RLS
