# Mobile Provisioning Fix — patient registration orphan

## The bug (proven on staging-copy)

Mobile patient registration creates an orphaned account: `auth.users` row + `profiles` row exist, but **no `patients` row**. The patient dashboard then fetches the patients record, gets nothing, and hangs (infinite loading) — or on web renders "Profile Configuration Error." Confirmed on `ralagarcia014@gmail.com`: profile present, `patients` row NULL.

## Root cause

Mobile registration inserts the `patients` row directly from the **anon/authenticated Supabase client**:

```dart
// lib/core/repositories/patients_repository.dart
await _client.from('patients').insert(patient.toJson())...
```

`public.patients` has **no patient self-insert RLS policy** — and never did, pre-flip or post. The insert is RLS-denied. Auth user + profile (from the `handle_new_user` trigger) get created, the patients insert fails silently, account orphans. Mobile's failure handling only does a local `signOut()`, so the half-created auth user is left in the DB.

This is NOT caused by the RBAC flip (migration_17). It's pre-existing — the anon-client insert was always denied. The flip only made it visible because you were testing patient flows on staging-copy.

## Why web doesn't have this

Web creates the patients row **server-side with the service-role client** (`adminClient`), which bypasses RLS, and deletes the auth user if the insert fails (cleanup, no orphan):

```ts
// web: src/lib/patient/createPatient.ts
const { error: patientError } = await adminClient.from("patients").insert({...});
if (patientError) { await adminClient.auth.admin.deleteUser(userId); }
```

Mobile is the only path doing this client-side. The fix makes mobile match the web pattern.

## The fix

Move the `patients` row creation off the mobile client and into a **service-role Edge Function** — exactly the pattern your existing functions already use (`send-verification-code`, `verify-registration-code`, `update-user-email` all do privileged writes with `createClient(supabaseUrl, serviceRoleKey)`).

### New Edge Function (or fold into signup path): `create-patient-record`

- Service-role client (`SUPABASE_SERVICE_ROLE_KEY`) — bypasses RLS, same as web's adminClient.
- Validates the caller's JWT first (`getUser()` with an anon client on the Authorization header) — confirm the caller is the account the patients row is for.
- Inserts the `patients` row (profile_id = caller uid, plus the registration fields).
- On insert failure: delete the auth user (`admin.deleteUser`) so no orphan is left — mirror web's cleanup.
- Returns success/failure to mobile.

### Mobile registration flow change

- After `auth.signUp()`, instead of `_client.from('patients').insert(...)`, call the new Edge Function (`functions.invoke('create-patient-record', ...)`).
- On function failure, surface the error and do NOT leave the user in a half-state (the function handles auth-user cleanup; mobile just clears local session).
- Then continue to the OTP flow (`send-verification-code`) as today.

### Ordering

signUp → create-patient-record (service-role, with cleanup) → send-verification-code (OTP). The patients row must be created and confirmed before the account is considered provisioned.

## What NOT to do

**Do not add a patient self-insert RLS policy on `patients`.** That "fixes" the denial by letting any authenticated user insert arbitrary patients rows — it punches a hole in the exact isolation the security model depends on. The service-role Edge Function is the correct fix; it keeps the privileged write server-side where the service-role key belongs (never in a client).

## Secondary defect (separate, lower priority)

`handle_new_user` swallows exceptions (`WHEN OTHERS THEN RETURN new`), which is how NULL role_id went silent. Web side hardened this in migration_18 (explicit fallback + loud log + raise). If your accounts still show NULL role_id after the backfill, that trigger version needs to be live on your target env too — coordinate on which migration set is applied where.

## Verification (once implemented)

- Register a fresh patient through mobile against staging-copy.
- Confirm all three rows exist: `auth.users`, `profiles` (with role_id), `patients` (with profile_id = uid).
- Load the patient dashboard — no infinite loading, no config error.
- Induce a patients-insert failure — confirm the auth user is cleaned up, no orphan left.
