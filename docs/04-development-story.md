# The Capstone Development Story — KlinikAid Mobile

This document records the complete development journey of KlinikAid Mobile. It traces the project from its clinical requirements through its structured nine-phase development protocol to the final integration hardening sprint.

---

## 1. The Legacy Clinical Intake Problem at Bloodcare Medical Laboratory

Bloodcare Medical Laboratory historically operated on a manual, paper-dependent administrative system. The typical clinical path was slow, inefficient, and prone to error:
- **Transcription Bottlenecks**: Patients arriving at the clinic presented physical paper diagnostic referral forms filled out by their physicians. The front-desk receptionist had to transcribe these details manually—including patient names, requested tests, diagnostic codes, and referring physician metadata—into the laboratory's desktop software.
- **Data Inaccuracies**: Manual transcription of handwritten notes regularly introduced spelling errors and formatting discrepancies in patient profiles and clinical tests. This led to misaligned diagnostic files, lost records, and delays in processing results.
- **Physical Queue Congestion**: Patients had to wait in physical lines for receptionist verification. Once queued, patients had no visibility into their waitlist position or estimated wait times, leading to crowded waiting areas.
- **Data Privacy Risks**: Physical referral sheets containing highly sensitive health details were stored in open folders at the receptionist's desk, exposing patient information to unauthorized view.
- **Results Latency**: Laboratory results were manually printed, requiring patients to return to the clinic to retrieve physical sheets, preventing convenient tracking of their personal health histories.

To resolve these administrative bottlenecks, Bloodcare Medical Laboratory initiated the KlinikAid project. The project's goal was to build a unified database backend serving two clients: a web portal for desk-bound staff and a mobile application for patients and mobile clinic staff.

---

## 2. Team Structure and the Four-Gate Protocol

Development of the KlinikAid ecosystem was completed by **Healthioneers**, a four-member capstone team:
- **Mobile Developer**: `[Team Member Name / GitHub Handle]` (sole developer responsible for the Flutter Android codebase)
- **Web Developers**: `[Team Member Name]`, `[Team Member Name]`, and `[Team Member Name]` (responsible for the management web portal)

Because the mobile application was built by a single developer coordinating with a separate web team, the team adopted a strict **Four-Gate Development Protocol** for each feature phase to prevent architectural drift:
1. **Plan**: Write a detailed design specification detailing routing, schemas, and provider states.
2. **Gate B Review**: Technical walkthrough of the plan with the project leads to align database triggers and RLS policies.
3. **Build**: Execute the development. Write the code, unit tests, and widget tests.
4. **Gate D Review**: Verify the build against the phase requirements, run tests, compile code, and review static analysis.

This discipline kept the mobile client aligned with the web team's database modifications, ensuring integration testing was smooth.

---

## 3. The Nine Development Phases

The mobile application progressed through nine development phases:

### Phase 0: Setup and Backend Alignment
- **Technical Goal**: Configure the local development environment and align data models with the shared backend.
- **Implementation**: Established the base Flutter project directory, configured Android build requirements (minSdk 26), and aligned dependencies (Supabase, Drift, Google ML Kit). Set up local environment files and mapped initial client routes.
- **Outcome**: Successfully compiled the initial shell and verified connectivity to the Supabase client.

### Phase 1: Connectivity and Data Layer
- **Technical Goal**: Establish secure data communication pathways.
- **Implementation**: Configured connection to the shared Supabase project. Integrated the database layer to map local SQLite databases to Postgres schemas. Developed offline network checkers to handle intermittent internet connections.
- **Outcome**: Successfully ran test queries against RLS-protected tables.

### Phase 2: Authentication, Privacy Consent, and Onboarding
- **Technical Goal**: Implement secure access controls and onboarding flows.
- **Implementation**: Built email/password login and registration. Enforced RA 10173 compliance by gating access behind a mandatory privacy consent agreement. Implemented patient onboarding to collect demographic records.
- **Key Resolution**: Discovered that the shared schema separated logins (`profiles`) from demographics (`patients`). We mapped them using client-side joins in the auth provider, linking the two records.

### Phase 3: Patient Dashboard and Core App Shell
- **Technical Goal**: Build the primary navigation structure and dashboard.
- **Implementation**: Built the persistent bottom navigation shell containing five main tabs: Dashboard, Document Upload, Patient Records, Queue Status, and Profile. Created the dashboard UI to display status summaries.
- **Outcome**: Patients can view active tickets, pending uploads, and recent lab results in a unified dashboard.

### Phase 4: On-Device OCR with Google ML Kit
- **Technical Goal**: Automate referral intake with local text extraction.
- **Implementation**: Developed the photo capture and gallery document intake system. Integrated Google ML Kit's Text Recognizer to extract text locally on the device. Implemented an on-device "AI Quality Pre-Screen" parser to check for request dates, doctor credentials, patient names, and laboratory keywords.
- **Outcome**: Enabled privacy-first document processing, verifying legibility before upload.

### Phase 5: RAG Chatbot via Supabase Edge Function
- **Technical Goal**: Provide an AI-powered administrative assistant.
- **Implementation**: Created the chatbot interface. Developed a Supabase Edge Function to process queries using the Gemini API. Leveraged `pgvector` similarity search on Postgres to query clinical FAQs and guidelines.
- **Outcome**: Chatbot returns grounded answers and handles key protection by keeping the Gemini API key on the server.

### Phase 6: Records, Waitlists, and Realtime Updates
- **Technical Goal**: Implement realtime status updates.
- **Implementation**: Implemented read-only list views for diagnostic records and patient queues. Enabled Realtime PostgreSQL replication listeners to push status changes to the client instantly.
- **Outcome**: App updates dynamically when staff update waitlist numbers or document statuses on the web.

### Phase 7: Role-Aware GoRouter Configuration and Security Guards
- **Technical Goal**: Enforce access boundaries.
- **Implementation**: Integrated role-aware GoRouter configurations. Implemented the admin block to reject logins from `admin` accounts. Configured staff routing to redirect staff users to their designated home pages.
- **Outcome**: Secured mobile entry points, preventing role bypass.

### Phase 8: Specialized Staff Portals
- **Technical Goal**: Build views for clinic staff.
- **Implementation**: Developed read-only views for receptionists (three-tab directory), department staff (department-scoped waitlist), and specialists (patient search and timelines).
- **Outcome**: Staff on the move can check queue positions and document details without modifying data.

### Phase 9: Testing, Hardening, and ISO 25010 Evaluation
- **Technical Goal**: Verify application stability.
- **Implementation**: Wrote unit and widget tests for RLS, login routing, caching, and database migrations. Evaluated performance on an older Android device (Android 8.0 / 4GB RAM) against ISO 25010 benchmarks.
- **Outcome**: Validated offline reliability and memory efficiency.

---

## 4. Post-Phase-9 Hardening and Scope Tightening

Integration testing with the web team's portal surfaced several data-representation gaps and operational discrepancies. We resolved these during a post-Phase-9 final hardening sprint, implementing the following eight scope tightenings:

### Fix 1: Department Staff Read-Only Conversion
- **The Problem**: Initial designs exposed "Start Service" and "Complete" buttons to department staff on mobile, risking operational conflicts with desktop technicians.
- **The Fix**: We removed all status modification buttons from the mobile UI. RLS policies continue to permit these operations on the database (as the web portal relies on them), but the mobile client is strictly read-only.
- **Impact**: Staff can monitor waitlists from their phones, but must process queue changes from web terminals.

### Fix 2: Triage Notes JSON Formatter
- **The Problem**: The web team stored queue metadata inside a `patient_queue.triage_notes` JSON column. The mobile client was displaying raw JSON strings (e.g., `{"notes":"Fasting","height":170}`) directly to users.
- **The Fix**: We implemented `TriageNotesFormatter` to extract the human-readable `notes` field.
- **Impact**: Restored clean text rendering on patient-facing screens and prevented the leakage of internal queue parameters.

### Fix 3: Receptionist Documents Three-Tab View
- **The Problem**: Receptionists had a single list showing only pending documents, preventing them from looking up already processed or rejected referrals.
- **The Fix**: We replaced the single list with a three-tab view: **Pending**, **Approved**, and **Rejected**. Approved and Rejected documents are filtered to a 30-day window, and Rejected documents display the staff's rejection reasons.
- **Impact**: Provides receptionists with complete document verification histories.

### Fix 4: Receptionist Queue Tab Hidden
- **The Problem**: The receptionist screen included a queue management tab, which contradicted the design boundary that queue management belongs on the web portal.
- **The Fix**: We hid the "Today's Queue" tab from the receptionist mobile UI.
- **Impact**: Focuses the mobile receptionist view strictly on document verification. The underlying provider logic and realtime subscriptions are preserved for future extension.

### Fix 5: Records Grouping
- **The Problem**: The Postgres schema stores laboratory measurements as separate database rows. A patient receiving an ultrasound with two findings saw two separate cards on mobile, whereas the web portal consolidated them.
- **The Fix**: We implemented a records grouper that groups records by `(patient_id, department, recorded_at)` within a 5-minute window.
- **Impact**: Consolidates findings into a single card showing stacked details and a worst-case-wins status badge (e.g., if one finding is "critical", the entire card is flagged "critical").

### Fix 6: Binary Queue Status Display
- **The Problem**: The patient queue UI displayed a "0 min estimated wait" alongside a "NOW CALLING" header, which was confusing. Since the schema does not support wait-time projections, the wait time was inaccurate.
- **The Fix**: We updated the status formatter to map `patient_queue.status` to clear status labels: patients see "IN QUEUE" or "NOW CALLING", and staff see "WAITING" or "IN PROGRESS".
- **Impact**: Removed false precision wait-time estimates from the UI.

### Fix 7: Medical Specialist Portal Fixes
- **The Problem**: Multi-word patient searches with spaces broke; specialist timelines duplicated multi-parameter records; and long findings text overflowed card layouts.
- **The Fix**:
  - Implemented a whitespace tokenizer for case-insensitive, order-independent search.
  - Integrated the records grouping helper into the specialist timeline.
  - Updated card layouts with `Flexible` and `softWrap` rules.
  - Extracted the detailed record modal into a shared widget.
- **Impact**: Fixed timeline rendering and patient search functionality.

### Fix 8: OCR Retake Redirect
- **The Problem**: Tapping the "Retake" button on the OCR preview screen re-launched the camera picker directly, forcing patients to re-take photos even if they wanted to switch to picking an image from the gallery.
- **The Fix**: Modified the button callback to clear the local image path and reset the provider's OCR state.
- **Impact**: Correctly returns patients to the OCR landing page (Camera / Gallery option screen) and prevents stale OCR states.

---

## 5. Key Architectural Decisions

- **Why Flutter**: Allowed a single developer to build, test, and package a responsive Android client. Flutter's type safety aligned well with the web team's TypeScript configurations, simplifying model mapping.
- **Why Supabase**: Sharing a single Supabase instance allowed both teams to share a database schema and authentication system. Using Supabase Storage and Edge Functions reduced backend hosting complexity.
- **Why On-Device OCR**: Keeping document text extraction on-device prevents unverified patient files from hitting the server. This maintains strict compliance with RA 10173 data privacy rules.
- **Why Read-Only Staff Portals**: Staff on the move require viewing access to patient records and queues, but actual database writes and status transitions are restricted to desktop web terminals to prevent errors.
- **Why Centralized Helpers**: Centralizing formatters (`triage_notes_formatter.dart`, `record_grouper.dart`, `queue_status_formatter.dart`) prevents visual discrepancies and rendering errors across screens.

---

## 6. ISO 25010 Performance Benchmarks

During Phase 9, we evaluated the application against ISO 25010 standards on a low-end test device (Android 8.0 / 4GB RAM) under four operational load scenarios:
- **Scenario 1: Network Loss during Upload**: Checked that the local Drift cache successfully stored and queued the document when offline. The upload synced automatically when connection was restored, displaying a temporary SnackBar warning to confirm sync.
- **Scenario 2: Realtime Database Sync Load**: Verified that realtime updates to queue tickets updated the UI smoothly without frame drops.
- **Scenario 3: Memory Footprint during OCR**: Monitored RAM usage during on-device OCR processing. Memory footprint stayed within acceptable system thresholds.
- **Scenario 4: Startup Session Restoration**: Verified that authenticated sessions restore immediately on app launch, bypassing the login screen and loading cached data first for a fast startup.

---

## 7. Defense-in-Depth Security Patterns

Security is enforced at both the client and database layers (defense-in-depth):
- **Role Registration Guard (Constraint #11)**: The registration screen hard-codes `'role': 'patient'` during signup, and a database trigger defaults any missing role parameters to `'patient'`.
- **Admin Login Block (Constraint #10)**: The mobile login form blocks administrator access, and the session-restore router guard checks the database profile to prevent bypassed entry.
- **Department Isolation**: Staff routes are guarded client-side by GoRouter, query parameters are filtered in providers, and Postgres RLS policies block unauthorized cross-department data requests.

---

## 8. What We'd Do Differently

- **Sooner Shared Backend Coordination**: Early database structure differences required a mid-project Supabase migration. Earlier alignment on table schemas would have saved migration time.
- **Earlier Design System Synchronization**: Shared UI styles were unified late in development, requiring stylesheet refactoring in Phase 6.
- **Comprehensive Offline Path Testing**: We should have introduced automated offline simulation tests earlier in the project lifecycle.
