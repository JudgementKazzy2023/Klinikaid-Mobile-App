# Clinical Scope and Project Overview

KlinikAid Mobile is a specialized, patient-and-staff-facing Android application designed for Bloodcare Medical Laboratory. Developed using the Flutter framework and backed by a shared Supabase Postgres instance, the application digitizes the diagnostic lifecycle, starting from initial patient registration and referral intake up to laboratory waitlist status updates and clinical results distribution.

---

## 1. The Legacy Clinical intake Problem

Bloodcare Medical Laboratory historically operated on a manual, paper-dependent administrative system. The typical clinical path was slow, inefficient, and prone to error:
- **Transcription Bottlenecks**: Patients arriving at the clinic presented physical paper diagnostic referral forms filled out by their physicians. The front-desk receptionist had to transcribe these details manually—including patient names, requested tests, diagnostic codes, and referring physician metadata—into the laboratory's desktop software.
- **Data Inaccuracies**: Manual transcription of handwritten notes regularly introduced spelling errors and formatting discrepancies in patient profiles and clinical tests. This led to misaligned diagnostic files, lost records, and delays in processing results.
- **Physical Queue Congestion**: Patients had to wait in physical lines for receptionist verification. Once queued, patients had no visibility into their waitlist position or estimated wait times, leading to crowded waiting areas.
- **Data Privacy Risks**: Physical referral sheets containing highly sensitive health details were stored in open folders at the receptionist's desk, exposing patient information to unauthorized view.
- **Results Latency**: Laboratory results were manually printed, requiring patients to return to the clinic to retrieve physical sheets, preventing convenient tracking of their personal health histories.

To resolve these administrative bottlenecks, Bloodcare Medical Laboratory initiated the KlinikAid project. The project's goal was to build a unified database serving two clients: a web portal for desk-bound staff and a mobile application for patients and mobile clinic staff.

---

## 2. Mobile App Deliverables

KlinikAid Mobile digitizes clinical workflows at the point of care, shifting data entry to the patient's device and providing specialized, role-scoped directories for clinic personnel on the move.

### Patient Self-Service Flow
- **Demographics Onboarding**: First-time users register, complete their demographic profile, and accept RA 10173 privacy consent terms directly on their phones.
- **On-Device OCR Intake**: Patients capture physical referral sheets using their phone's camera. An on-device AI model extracts the text and runs a quality pre-screen checklist to verify readability of the patient's name, doctor credentials, requested dates, and laboratory keywords before upload.
- **Real-Time Waitlist Tracking**: Patients see their active status in the laboratory or imaging queue, with live updates showing whether they are waiting or now being called.
- **Digital Health Record**: Access to all past completed diagnostic findings, grouped by clinical visit, preventing lost records.
- **AI Administrative Assistant**: A chatbot that answers administrative, scheduling, and laboratory preparation questions (e.g., fasting requirements).

### Scoped Mobile Staff Portals
The mobile application embeds three specialized, read-only portals for clinic personnel:
- **Receptionist**: A lookup directory divided into Pending, Approved, and Rejected document uploads. This enables quick on-the-floor document lookup and verification.
- **Department Staff**: A view of waitlists and completed records scoped exclusively to their operational department (e.g., Laboratory or Imaging).
- **Medical Specialist**: A search engine to find patients and browse their unified, cross-department diagnostic history timelines.

---

## 3. Shared-Backend Web Collaboration

KlinikAid Mobile coordinates with a separate web administration portal used by the laboratory owners, managers, and desk-bound technicians. Both platforms share a single Supabase backend.

### Backend Infrastructure
- **Shared Schema**: The mobile app and the web portal read from and write to the exact same Postgres database tables (e.g., `patients`, `profiles`, `patient_queue`, `documents`, and `department_records`).
- **Unified Row-Level Security (RLS)**: Access controls are enforced directly in the database. When a mobile user requests data, the database uses their Supabase authentication context to filter rows.
- **Private Storage**: Captured document files are uploaded from the mobile app to a private Supabase Storage bucket. The web portal accesses these files via secure, authenticated URLs to review and update document status.

---

## 4. System Boundaries and Out-of-Scope Items

To maintain clinical safety, data integrity, and strict security compliance, specific boundaries are established:
- **No Mobile Administrative Rights**: Administrators and clinic owners are blocked from accessing the mobile app. All system modifications, schema changes, and high-level role promotions are restricted to the desktop web portal.
- **No Mobile Clinic Actions**: Transitioning queues (starting service, completing tests) and modifying document statuses (approving or rejecting files) are web-only actions. The mobile staff portals are viewing tools to ensure staff on the move have context without introducing modification errors.
- **No Medical Diagnoses**: The AI administrative chatbot is restricted from providing medical diagnoses or symptom analysis. If a query requests clinical advice, the system redirects the user to consult a physician.
- **No PDF/DOCX Mobile Uploads**: Document submission on mobile is strictly constrained to captured camera images or gallery photos. Multi-page document uploads like PDFs are deferred to web-based uploaders.
- **Mobile Read-Only Constraint for Staff**: In compliance with the mobile-as-a-viewing-tool design philosophy, staff users cannot modify, write, or enter diagnostic results or queue details from the mobile client.
