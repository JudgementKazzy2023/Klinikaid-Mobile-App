# Patient Provisioning Fix Walkthrough

## Scope

This build moves patient registration provisioning out of the mobile client's direct `patients` insert and into a staging Edge Function:

- Edge Function: `create-patient-record`
- Staging Supabase project: `jlnabjmwmpnaomjighpn`
- Mobile caller: `AuthProvider.signUp()`

No commit or push has been made.

## Files Changed

- `lib/features/auth/data/patient_provisioning_service.dart`
  - New mobile service that invokes `create-patient-record`.
  - Sends `first_name`, `last_name`, `date_of_birth`, `gender`, `contact_number`, `email`, and `address`.
  - Marks normal function failures as `functionRan: true`.
  - Marks timeout/offline/no-response failures as `functionRan: false`.

- `lib/features/auth/presentation/providers/auth_provider.dart`
  - Registration no longer calls `_patientsRepo.createPatient()`.
  - Registration now invokes `create-patient-record`.
  - If invoke fails before the function likely ran, it calls `VerificationService.deletePendingUser()` before local sign-out.
  - If the function ran and returned an error, it signs out locally without fallback auth deletion.
  - Existing `_patientsRepo.createPatient()` is kept because it is still used by `submitOnboarding()`.
  - Profile consent updates preserve `role_id` and `employee_type`.

- `supabase/functions/create-patient-record/index.ts`
  - New Edge Function.
  - Requires authenticated user JWT.
  - Uses service role only server-side.
  - Inserts into `patients` with `profile_id = authenticated user id`.
  - Includes `email` in the insert.
  - Does not trust any client-supplied `profile_id`.
  - If patient insert fails, deletes the just-created auth user using admin cleanup.

- `supabase/config.toml`
  - Adds JWT verification config for `create-patient-record`.

- `test/patient_provisioning_fix_test.dart`
  - Focused mocked tests for success, function-ran failure, and network/no-response cleanup.

## Important Git Note

The repo currently ignores some relevant paths:

- `supabase/config.toml` is ignored by `supabase/*`
- `supabase/functions/create-patient-record/index.ts` is ignored by `supabase/functions/*`
- `test/patient_provisioning_fix_test.dart` is ignored by `test/`

So the server function exists locally and is deployed to staging, but it will not be included in a commit until the ignore rules are adjusted or the files are force-added intentionally.

## Deployed

`create-patient-record` was deployed to staging project:

`jlnabjmwmpnaomjighpn`

## Verification Completed

- Focused mobile tests passed:
  - registration success calls provisioning service
  - registration does not use direct patient insert
  - function-ran failure signs out without fallback auth delete
  - network/no-response failure calls `deletePendingUser()`

- Dart analysis passed with only existing info-level print/interpolation notes in `auth_provider.dart`.

- Edge Function Deno check passed.

- Release APK build passed:
  - `build/app/outputs/flutter-apk/app-release.apk`
  - size: about 101.6 MB

## Gate D Staging Checks Still Needed

Use the web team's staging project `jlnabjmwmpnaomjighpn`.

1. Create a patient account from the mobile registration screen.
2. Confirm the app reaches verification-code sending after patient provisioning.
3. In Supabase staging, confirm:
   - one auth user exists
   - one matching `profiles` row exists
   - one matching `patients` row exists
   - `patients.profile_id` matches the auth user id
   - `patients.email` is populated
4. Test a forced function insert failure if possible:
   - auth user should be cleaned up by the Edge Function.
5. Test a network/timeout/no-response failure if possible:
   - mobile should call `deletePendingUser()` before signing out.
6. Confirm no registration path writes directly to `patients` from the mobile app.

## Not Changed

- No web app code changed.
- No database schema migration was added.
- No patient write-path changes were made outside registration.
- No git commit or push was performed.
