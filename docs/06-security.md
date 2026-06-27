# Security Architecture and Compliance

This document details the security design, compliance measures, and data isolation boundaries of the KlinikAid Mobile Application.

---

## 1. Security Constraints and Implementation

KlinikAid Mobile enforces twelve strict security and scoping constraints to protect clinical data and maintain compliance:

### #1: No Secrets in the App
- **Design**: Storing API keys or admin database credentials in the application code risks key extraction if the APK is decompiled.
- **Enforcement**: The Gemini API key is stored as a secret in the Supabase backend. The mobile app routes chatbot requests through a server-side Supabase Edge Function, which appends the secret key and queries the Gemini endpoint. The client bundles only the public Supabase URL and Anon Key.

### #2: Shared Schema Compliance
- **Design**: Unilateral schema changes by either client team can break database queries and trigger failures.
- **Enforcement**: The mobile app's database models conform exactly to `src/lib/db/schema.sql` from the shared web repository. No tables, columns, or RLS policies are altered from the mobile client.

### #3: Data Model Parity
- **Design**: Mismatched object fields cause serialization errors and application crashes.
- **Enforcement**: Dart classes in `lib/core/models/` map exactly field-for-field with Next.js TypeScript definitions in `src/types/index.ts`.

### #4: Chatbot Medical Advice Restrictions
- **Design**: AI models must not diagnose conditions or recommend medical treatments.
- **Enforcement**: The Supabase Edge Function's system prompt instructs Gemini to refuse medical advice and limit responses to administrative and laboratory guidelines.

### #5: No Mobile Patient Analytics
- **Design**: Specialist analytics dashboards require complex data processing and are out of scope for mobile.
- **Enforcement**: The mobile specialist dashboard is limited to Patient Search and Patient History views. Analytics graphs are restricted to the web portal.

### #6: On-Device OCR Processing
- **Design**: Sending patient documents to third-party endpoints for text extraction introduces privacy risks.
- **Enforcement**: OCR text extraction is processed locally on the device using Google ML Kit's Text Recognizer. The referral image remains on the phone during the quality pre-screen check.

### #7: Human-in-the-Loop Verification
- **Design**: Automated document approvals can lead to clinical tracking errors if OCR text is misread.
- **Enforcement**: The OCR pre-screen checklist only flags readable fields for the patient. Final document validation and status updates are completed manually by staff via the web portal.

### #8: Scope Discipline
- **Design**: Restricting development to implemented backend tables prevents integration bugs.
- **Enforcement**: The app implements only screens matching the active schema tables.

### #9: RLS as the Primary Security Boundary
- **Design**: The mobile app runs in an untrusted environment using the public Anon Key.
- **Enforcement**: Access controls are enforced directly in the database. All Postgres queries from the client include authenticated session headers, which Postgres matches against Row-Level Security (RLS) policies.

### #10: Block Administrator Mobile Access
- **Design**: Stolen mobile devices with active admin sessions present high security risks.
- **Enforcement**: Mobile login rejects accounts with the `admin` role, logs out the user, and directs them to the web portal. GoRouter checks metadata on restore to boot administrative sessions.

### #11: Patient-Only Mobile Registration
- **Design**: Allowing users to select their role during signup can lead to unauthorized access.
- **Enforcement**: The registration screen hard-codes `'role': 'patient'` in the `auth.signUp()` call. The database trigger `handle_new_user` defaults any missing or modified role parameters to `patient`.

### #12: Read-Only Mobile Staff Portals
- **Design**: Modification screens on mobile increase the risk of operational errors.
- **Enforcement**: Mobile staff portals are viewing directories. All status changes and document approvals must be completed on the desktop web portal.

---

## 2. Row-Level Security (RLS) Policy Configurations

Row-Level Security (RLS) policies in the Postgres database isolate patient data:

### Patient Data Isolation
Patients can only read and write rows matching their authenticated `auth.uid()`.
- **`patients` Table Policy**:
  ```sql
  CREATE POLICY "Patients read own profile" ON patients
  FOR SELECT USING (profile_id = auth.uid());
  ```
- **`documents` Table Policy**:
  ```sql
  CREATE POLICY "Patients insert own documents" ON documents
  FOR INSERT WITH CHECK (uploader_id = auth.uid());
  ```

### Staff Portal Scoping
Staff access is scoped by checking their role and department:
- **`get_auth_user_role()`**: Database function that reads the authenticated user's role from the `profiles` table.
- **`get_auth_user_dept()`**: Database function that reads the department assigned to the staff member's profile.
- **Department Staff Scoping**: Staff can only view queue tickets matching their assigned department:
  ```sql
  CREATE POLICY "Staff view department queue" ON patient_queue
  FOR SELECT USING (
    get_auth_user_role() = 'department_staff' 
    AND department = get_auth_user_dept()
  );
  ```

---

## 3. Defense-in-Depth Implementation

KlinikAid Mobile uses multiple security checks to verify data integrity:

```
┌────────────────────────────────────────────────────────┐
│                    REGISTRATION FLOW                   │
├───────────────────────────┬────────────────────────────┤
│ Client-Side Guard         │ Database-Side Guard        │
├───────────────────────────┼────────────────────────────┤
│ Register UI hard-codes    │ Postgres signup trigger    │
│ role='patient' metadata.  │ defaults missing/modified  │
│ No role selector exposed. │ role columns to 'patient'. │
└───────────────────────────┴────────────────────────────┘
```

- **Patient Registration**: Enforced both client-side (no role selector, hard-coded metadata) and database-side (trigger defaulting empty or modified roles to `patient`).
- **Staff Access**: Isolated by GoRouter route guards client-side, query filters in providers, and RLS policies in the database.

---

## 4. Security Verification Tests

Three test suites verify the security implementation:
- **`test/phase7_role_routing_test.dart`**: Verifies that Patient, Receptionist, Department Staff, and Medical Specialist logins route to their designated home screens. Asserts that Admin login attempts are blocked and the session is cleared.
- **`test/phase4_document_submission_test.dart`**: Asserts that if a queued offline document is modified with a different uploader ID, the sync system flags the item as "orphaned" and blocks submission.
- **`test/phase8_staff_department_test.dart`**: Simulates Lab staff attempting to query Imaging records, verifying that the database filters out other department rows. Executes an unauthorized insert attempt to verify that cross-department writes are blocked.

---

## 5. APK Security Audit

Before compiling a release build, the build is audited for credential leaks:
1. Compile the release package: `flutter build apk --release`.
2. Decompile the resulting APK using `apktool`:
   ```bash
   apktool d build/app/outputs/flutter-apk/app-release.apk -o decompiled_audit
   ```
3. Search decompiled resources for keys:
   ```bash
   # Search for Gemini API keys
   grep -r "AIzaSy" decompiled_audit/

   # Search for database secrets
   grep -r "service_role" decompiled_audit/
   ```

Both queries must return **zero matches** to pass deployment requirements.

---

## 6. RA 10173 (Data Privacy Act of 2012) Compliance

The application is structured to comply with the Philippine Data Privacy Act (RA 10173):
- **Privacy Consent Gating**: First-time patient logins are locked behind an interactive consent screen. Access to the dashboard remains blocked until the patient accepts the terms. Acceptance is recorded in `profiles.accepted_privacy_at`.
- **Privacy-First OCR**: Document text extraction is completed entirely on-device via Google ML Kit. No raw image data is sent to external services for text processing.
- **Private Data Storage**: Approved clinical files are stored in a private Supabase Storage bucket. Access is restricted to authenticated staff via temporary, signed URLs.
