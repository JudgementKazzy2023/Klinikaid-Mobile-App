# Walkthrough — Setup, Connectivity, Auth & Patient Onboarding (Phases 0, 1 & 2)

This document details the environment preparation, project skeleton creation, database integration, repository implementation, security policies, and onboarding/auth state gating verification results.

---

## Phase 0: Setup & Backend Alignment

### 1. Environment & Tools Installation
* Installed Git version `2.54.0` using `winget`.
* Installed Puro Flutter version manager version `1.5.0` using `winget`.
* Configured Flutter SDK (`3.44.0` with Dart `3.12.0`).

### 2. Project Initialization
* Created the Flutter project skeleton.
* Added custom ignore paths for `lib/core/config/env.dart` to [.gitignore](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/.gitignore).
* Created environment variables config files:
  * [env.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/config/env.dart) (contains Supabase credentials)
  * [env.dart.example](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/config/env.dart.example) (example template)

### 3. Dependencies
* Configured core packages in [pubspec.yaml](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/pubspec.yaml): `supabase_flutter`, `google_mlkit_text_recognition`, `camera`, `image_picker`, `drift`, `sqlite3_flutter_libs`, `path_provider`, `path`, `go_router`, `provider`, and `pdfx`.

### 4. Database Schema & Type Alignment
* Implemented type-safe Dart models matching [schema.sql](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/web_reference/schema.sql) under `lib/core/models/`:
  * [profile.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/profile.dart)
  * [patient.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/patient.dart)
  * [patient_queue.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/patient_queue.dart) (safely parses `bigint` ids)
  * [document.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/document.dart)
  * [department_record.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/department_record.dart)
  * [chatbot_log.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/chatbot_log.dart) (safely parses `bigint` ids)
  * [rag_document.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/rag_document.dart)

### 5. Android Build Modifications
* Configured `android/app/build.gradle.kts` with `compileSdk = 36`, `targetSdk = 34`, and `minSdk = 26`.

---

## Phase 1: Connectivity & Data Layer

### 1. Supabase Integration
* Created [supabase_client.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/supabase/supabase_client.dart) to initialize the `Supabase` instance using credentials from `Env`. Correctly adapted to `supabase_flutter` v2 by passing the `localStorage` option nested within `authOptions: FlutterAuthClientOptions`.

### 2. Error & Failure Mapping
* Centralized exception handling in [failures.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/errors/failures.dart), mapping `PostgrestException` code `42501` to `DatabaseFailure` (representing access denied / RLS blocking) and network/auth errors to typed failures.

### 3. Repositories Layer
* Created type-safe database repositories mapping the operations defined in our backend contract:
  * [profiles_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/profiles_repository.dart)
  * [patients_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/patients_repository.dart)
  * [patient_queue_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/patient_queue_repository.dart)
  * [documents_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/documents_repository.dart) (updated to strip relation model maps prior to insertion/update)
  * [department_records_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/department_records_repository.dart)
  * [chatbot_logs_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/chatbot_logs_repository.dart)
  * [rag_documents_repository.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/repositories/rag_documents_repository.dart)

---

## Phase 2: Auth & Patient Onboarding

### 1. State Management & Navigation Logic
* **Auth State Management**: Created [auth_provider.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/providers/auth_provider.dart) to govern session persistence, user registration, sign-in, sign-out, RA 10173 data privacy consent, and patient onboarding state updates.
* **Gated Routing & Redirects**: Integrated GoRouter in [app_router.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/routing/app_router.dart) to enforce state-based routing:
  * Redirects unauthenticated traffic to `/login`.
  * Redirects authenticated but non-consented traffic to the Data Privacy Consent Gate (`/consent`).
  * Redirects authenticated and consented but non-onboarded traffic to the Patient Onboarding Form (`/onboarding`).
  * Restricts access to the Main Dashboard (`/`) until all three security gates are cleared.

### 2. Dark-Themed Presentation Screens (UI/UX)
* Created four core onboarding screens conforming to a premium dark-themed aesthetic (deep slate `#0B0E14` background, glowing indigo `#2E5BFF` buttons, smooth input fields, and Outfit typography):
  * **Login Screen** ([login_screen.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/screens/login_screen.dart)) — Secure sign-in with full validation and error banner feedback.
  * **Register Screen** ([register_screen.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/screens/register_screen.dart)) — Registers users with metadata tags to automatically trigger database profile creation via the Postgres trigger.
  * **Consent Gate Screen** ([consent_screen.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/screens/consent_screen.dart)) — Enforces explicit acceptance of Republic Act No. 10173 (Philippine Data Privacy Act) statement, persisting the consent timestamp `privacy_consent_at` in the user's auth metadata.
  * **Onboarding Form Screen** ([onboarding_screen.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/screens/onboarding_screen.dart)) — Captures clinical details (First Name, Last Name, Date of Birth, Gender, Contact, Address) and inserts the onboarding row into the `public.patients` table.

---

## Verification Results

### 1. Static Analysis
Ran static lint analysis:
```bash
puro flutter analyze
```
* **Result**: `No issues found!` (0 errors, 0 warnings, 0 info/deprecated messages remaining).

### 2. Two-Patient Isolation RLS Smoke Test
Implemented a robust integration test under [connectivity_smoke_test.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/test/connectivity_smoke_test.dart). The test registers two distinct patient accounts (Patient A and Patient B), signs in as Patient B to create an authentic clinical document record, and then logs back in as Patient A to verify data access boundaries.
Executed the smoke test:
```bash
puro flutter test test/connectivity_smoke_test.dart
```

* **Outcome (All RLS checks passed):**
  1. **HTTP Connectivity**: Success! The test successfully contacted the live Supabase server on project `vxnkpcqyrxdqxpvutkmm`.
  2. **Patient Registration**: Success! Registered Patient A (`patient.a.xxx@gmail.com`) and Patient B (`patient.b.xxx@gmail.com`). Trigger created corresponding rows in `public.profiles`.
  3. **Patient B Data Entry**: Success! Signed in B, inserted a document record (`uploader_id: patientBId`), which succeeded since Patient B owns the data.
  4. **Logged in as Patient A**: Clean login for Patient A.
  5. **Select Own Profile**: Success! Successfully fetched Patient A's own profile.
  6. **Select Foreign Profile (Blocked)**: Success! Patient A attempted to fetch Patient B's profile (`profiles` table). Postgrest returned 0 rows (RLS filtered out), causing `.single()` to fail and map to `DatabaseFailure` (Cannot coerce result...).
  7. **Select Foreign Documents (Blocked)**: Success! Patient A queried Patient B's documents. The database returned `[]` (empty list, 0 rows) as expected due to RLS select filters.
  8. **Insert Foreign Document (RLS Violation 42501)**: Success! Patient A attempted to insert a document with `uploader_id: patientBId` (violating `WITH CHECK (uploader_id = auth.uid())` policy). The query was denied by the database and failed with `PostgrestException` code `42501`, throwing a `DatabaseFailure` containing `"Access denied"`.
  9. **Clinical Onboarding Status**: Success! Verified that Patient A's record in `public.patients` returns `null` (since they haven't onboarded yet).

### 3. Comprehensive Onboarding Integration Test
Implemented an integration test under [auth_flow_test.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/test/auth_flow_test.dart) covering all onboarding gates.
Executed the onboarding test:
```bash
puro flutter test test/auth_flow_test.dart
```

* **Outcome (All 5 Onboarding Flow Steps PASSED)**:
  1. **Initial State Verification**: Confirmed that the application launches in an unauthenticated, non-consented, and non-onboarded state.
  2. **User Registration & Autologin**: Registered a new test user (`onboard.test.xxx@gmail.com`), validating that the database trigger successfully generated their `public.profiles` row, and verified they are authenticated but not yet consented.
  3. **Data Privacy Consent Gate (RA 10173)**: Submitted the data privacy consent and verified it successfully updated the user's metadata and transitioned their status to consented = true.
  4. **Patient Onboarding Details**: Submitted the patient onboarding clinical details form. Confirmed that the row was successfully inserted into `public.patients` (linked via `profile_id` under the new RLS insert policy), transitioning status to onboarded = true.
  5. **Session Recovery (Sign Out & Sign In)**: Signed out the user (cleared all local variables and reset states) and logged back in using their password. Verified that they bypass the gates automatically as their consent and onboarding statuses are dynamically restored from user metadata and database queries.

### 4. Database RLS Policy Insertion
To support self-onboarding inserts by patients, the following policy was successfully deployed and verified on the database:
```sql
CREATE POLICY "Patients can insert own patient record" 
  ON public.patients FOR INSERT 
  WITH CHECK (profile_id = auth.uid());
```

### 5. Database Schema Reconciliation (RLS Divergence Resolution)
* **Divergence Identified**: During onboarding, patients require `INSERT` access to `public.patients`. Since this was not defined in the canonical schema, the RLS policy was added to the mobile testing database.
* **Reconciliation Action**: Created [schema_proposals.md](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/web_reference/schema_proposals.md) in the `web_reference/` directory to formally document and track this proposal pending web team adoption.
* **Parity Tracking**: Added the proposal to the Phase 6 project merge checklist to ensure database parity prior to release.

### 6. Live Database Catalog Verification
The database catalog was verified on project `vxnkpcqyrxdqxpvutkmm` via the 4-query SQL check in the Supabase SQL Editor:
* **Query 1 (All 8 tables present):** PASSED. `chatbot_logs`, `department_records`, `documents`, `patient_queue`, `patients`, `profiles`, `rag_documents`, and `system_logs` are all present.
* **Query 2 (Trigger present):** PASSED. The `on_auth_user_created` trigger is active.
* **Query 3 (pgvector enabled):** PASSED. The `vector` extension is active.
* **Query 4 (RLS active):** PASSED. All 8 public tables returned `rowsecurity = true` in the pg_tables catalog check.

### 7. Web Schema Alignment & Resilient Gating (May 2026 Update)
* **Profiles Table Additions**: Verified the new web-team schema additions (`is_active` and `accepted_privacy_at` under the `profiles` table).
* **Model Synchronization**: Updated [profile.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/core/models/profile.dart) to map these fields during serialization/deserialization.
* **Resilient Gating Fallback**: Integrated database-backed consent status checks alongside auth user metadata checks in [auth_provider.dart](file:///c:/Users/Ralph/Downloads/Klinikaid%20Mobile%20app/lib/features/auth/presentation/providers/auth_provider.dart). To ensure seamless backward compatibility (e.g. before the web team deploys the schema updates to production), the app catches DB-level field write errors and falls back gracefully to auth metadata tracking.
* **Testing Success**: Verified that both test suites run and pass successfully against the current database configuration.

**All authentication, routing gates, data integrity, and RLS checks passed successfully!**
