# SPEC — Patient Provisioning Fix (create-patient-record Edge Function)

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates plan
(Gate B) + on-device walkthrough (Gate D).**

## STANDING RULES (self-contained)
- **Investigate before changing** — report current state first.
- **Trim testing:** one regression guard + one happy path; touched test files
  during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth/functions) — no live client in
  tests.
- **Real-device verification** mandatory — test against **staging** DB.
- This adds a new Edge Function → **deploy to staging first, test, then prod.**
- **`flutter build apk --release`** at Gate D (Edge Function deployment changes
  the registration flow — confirm the app builds).
- No images/mockups. Terse pass/fail. Don't claim a check you didn't run.
- **NEVER put the service-role key in mobile code or any client artifact.**

---

## The bug (proven by web team on staging)

Mobile patient registration creates an **orphaned account**: `auth.users` +
`profiles` rows exist, but **no `patients` row**. The patient dashboard fetches
the patients record, gets nothing, hangs forever (infinite loading).

**Root cause:** mobile inserts the `patients` row directly from the
anon/authenticated client (`_client.from('patients').insert(...)`), but
`public.patients` has **no patient self-insert RLS policy** — never did. The
insert is silently RLS-denied. Auth + profile get created (by the DB trigger),
the patients insert fails silently, account orphans.

**This is pre-existing** — not caused by the RBAC flip. The flip just made it
visible on a clean staging DB.

**Web doesn't have this** because web creates the patients row **server-side
with the service-role client** (bypasses RLS) and cleans up the auth user on
failure.

---

## The fix — match web's pattern

### Part 1 — New Edge Function: `create-patient-record`

Create a Supabase Edge Function that does the privileged `patients` insert
server-side. Follow the exact pattern of your existing functions
(`send-verification-code`, `verify-registration-code`).

**The function must:**
1. **Validate the caller's JWT** — create an anon-key client, call
   `auth.getUser()` with the `Authorization` header from the request. Confirm
   the caller is authenticated and extract their `user.id`. Reject
   unauthenticated calls (401).
2. **Accept the patient registration fields** from the request body:
   `first_name`, `last_name`, `date_of_birth`, `gender`, `contact_number`,
   `address`. Validate they're present and non-empty.
3. **Insert the `patients` row** using a **service-role client**
   (`createClient(supabaseUrl, serviceRoleKey)`) — bypasses RLS, same as web.
   Set `profile_id = caller's user.id` + the registration fields.
4. **On insert failure: clean up the auth user.** Call
   `admin.deleteUser(userId)` with the service-role client so no orphan is left.
   Return an error to mobile.
5. **On success:** return `{ success: true }` (or the created patient row).
6. **CORS headers** — match your existing functions.
7. **`verify_jwt: true`** — same as other functions.

**The function must NOT:**
- Accept or trust a `profile_id` from the client — always derive it from the
  JWT (`user.id`). A client-supplied profile_id is a spoofing vector.
- Be callable by anyone other than the account being provisioned (the JWT check
  ensures this).

### Part 2 — Mobile registration flow change

**In the registration flow** (likely `registration_provider.dart` or
`auth_repository.dart`):

**Before (broken):**
```
signUp → _client.from('patients').insert(...) → send-verification-code
```

**After (fixed):**
```
signUp → functions.invoke('create-patient-record', body: patientFields) → send-verification-code
```

- Replace the direct `_client.from('patients').insert(...)` with
  `Supabase.instance.client.functions.invoke('create-patient-record', body: {...})`.
- Pass: `first_name`, `last_name`, `date_of_birth`, `gender`,
  `contact_number`, `address`.
- **Do NOT pass `profile_id`** — the function derives it from the JWT.
- On function failure: surface the error, clear local session (`signOut()`).
  The function already cleaned up the auth user, so no orphan. Do NOT leave the
  user on a success screen if provisioning failed.
- On success: continue to OTP flow (`send-verification-code`) as today.

### Part 3 — Remove the dead direct insert

After wiring the function call, **delete** the old direct
`_client.from('patients').insert(...)` code path entirely. It was always
RLS-denied; leaving it is confusing and a regression risk.

---

## What NOT to do

**Do NOT add a patient self-insert RLS policy on `patients`.** That "fixes" the
denial by letting any authenticated user insert arbitrary patients rows — a
security hole. The Edge Function is the correct fix: privileged write stays
server-side where the service-role key belongs.

---

## Investigate FIRST

1. **Locate the exact insert call** — find where
   `_client.from('patients').insert(...)` is called during registration. Report
   the file + line.
2. **Confirm the registration flow order** — what happens after `signUp()` and
   before `send-verification-code`? The patients insert sits in between; confirm
   the full sequence.
3. **Check for error handling** — does the current code catch the (silently
   denied) insert failure? Or does it proceed to OTP regardless? (The web team
   says it only does a local `signOut()` — confirm.)
4. **Confirm the `patients` table columns** needed for the insert — the function
   must match exactly.

---

## Tests (mocked)

- **Unit — registration flow:** mock the function invoke; on success → OTP flow
  proceeds; on failure → error surfaced, local session cleared, no success
  screen.
- **Unit — no direct insert:** assert the old `_client.from('patients').insert`
  code path is removed / not called.
- **Regression:** existing registration screens still render correctly (the UI
  didn't break).

The Edge Function itself is tested by the **staging verification** below (it's
server-side TypeScript, not Flutter-testable).

## Verification (on staging — real device)

1. **Deploy `create-patient-record` to staging** (dashboard or CLI).
2. Set `SUPABASE_SERVICE_ROLE_KEY` in staging Edge Function **Secrets** (ask web
   team for the staging service key if not already set — **NEVER put it in
   mobile code**).
3. Register a **fresh patient** through mobile against staging.
4. Confirm all three rows exist in staging DB:
   - `auth.users` ✓
   - `profiles` (with `role_id` set) ✓
   - `patients` (with `profile_id` = uid) ✓
5. Load the patient dashboard — **no infinite loading**.
6. Submit a document, view records — works.
7. **Induce a failure** (e.g. duplicate email) — confirm the auth user is cleaned
   up (no orphan in `auth.users`), and mobile shows an error (not a success
   screen).
8. `flutter build apk --release` passes.

---

## Files affected

**New:**
- `supabase/functions/create-patient-record/index.ts` (Edge Function)
- Track in git (`supabase/functions/` is now un-ignored)

**Modified:**
- Registration flow (provider/repository) — replace direct insert with function
  invoke
- Remove dead direct-insert code path

**Not modified:**
- No RLS policy changes
- No `patients` table schema changes
- No service-role key added to mobile
