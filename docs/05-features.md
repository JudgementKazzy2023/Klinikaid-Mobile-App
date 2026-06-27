# Feature Inventory and Role-Based Permissions

This document provides a detailed catalog of the features, screens, and permission sets configured for each user role in the KlinikAid Mobile Application.

---

## 1. Introduction to Role Scoping

KlinikAid Mobile enforces a strict **Role-Based Access Control (RBAC)** model. Features are grouped into distinct workflows based on the user's role defined in the database (`profiles.role`). 

To prevent operational conflicts with desktop clinic staff, mobile staff portals are designed as read-only directories, while patient flows allow data entry for registration, consent, onboarding, and document uploads.

---

## 2. Role Matrix: Patient

Patients are the primary users of the mobile application's self-service features.

### Persona
A clinic client who needs to submit referral forms, check queue positions, view clinical history, and ask administrative questions.

### Accessible Screens & Layouts
- **Sign In / Sign Up**: Email/password forms. Registration hard-codes `role='patient'`.
- **Consent Gate**: RA 10173 consent disclosure blocking dashboard access until accepted.
- **Onboarding Form**: Profile creation gathering name, birthday, gender, contact info, and address.
- **Patient Dashboard**: Summary widgets displaying active tickets, document statuses, and recent records.
- **Document Upload (OCR)**: Integrates the camera/gallery picker with Google ML Kit quality checks.
- **Waitlist Tracker**: Visual card showing real-time queue position.
- **Health Records**: Grouped clinical findings list with detailed breakdown modals.
- **QA Chatbot**: Scrollable chat bubble layout.

### Permitted Actions
- Create a new account and onboarding profile.
- Upload referral images (processed locally via ML Kit before upload).
- Query the Gemini RAG chatbot.
- View personal waitlist tickets and queue positions in real-time.
- Read own completed diagnostic records and download results.
- Update personal contact information (phone number, address).

### Prohibited Actions
- **No Cross-Patient Access**: Cannot view other patients' profiles or records (enforced by RLS).
- **No Staff Level Access**: Cannot access receptionist directories, specialist tools, or department lists.
- **No Database Modifications**: Cannot alter database configurations or change user roles.
- **No Document Verification**: Cannot approve or reject submitted documents.

---

## 3. Role Matrix: Receptionist

Receptionists use the mobile app on the clinic floor to look up and verify document submissions.

### Persona
Front-desk staff who verify patient referral uploads on-the-go.

### Accessible Screens & Layouts
- **Document Verification Directory**: A three-tab interface showing patient uploads:
  - **Pending**: List of documents awaiting administrative review.
  - **Approved**: Documents verified and approved within the last 30 days.
  - **Rejected**: Documents rejected within the last 30 days, showing the staff's rejection reasons.

### Permitted Actions
- View and search document uploads across all patients.
- View document details, including uploader name, upload time, and OCR-extracted metadata.
- View rejection comments to explain re-submission requirements to patients.

### Prohibited Actions
- **No Status Modifications**: Cannot approve or reject document uploads from mobile (web-only).
- **No Queue Actions**: Cannot view active waitlists or manage queue tickets from mobile (web-only).
- **No Clinical Access**: Cannot view patient clinical findings or laboratory records.

---

## 4. Role Matrix: Department Staff

Department staff members (e.g., Lab Technicians, Radiologists) use the mobile app to monitor waitlists scoped to their department.

### Persona
Technicians who review their department's active queue and recent records while away from desktop terminals.

### Accessible Screens & Layouts
- **Department Dashboard**: A split screen containing:
  - **Active Waitlist**: Realtime list of patients queued for their department (e.g., Laboratory waitlist for Lab staff).
  - **Recent Records**: Historical list of completed records created in their department.

### Permitted Actions
- View active queue tickets matching their department.
- View recent records created in their department.
- Search waitlists and records by patient name.

### Prohibited Actions
- **No Cross-Department Access**: Cannot view other departments' waitlists or records (enforced by RLS).
- **No Ticket State Transitions**: Cannot start service or complete tickets from mobile (web-only).
- **No Record Creation**: Cannot write, edit, or upload patient results or clinical findings.

---

## 5. Role Matrix: Medical Specialist

Medical specialists (e.g., Doctors, Cardiologists) use the mobile app to search patient histories.

### Persona
Physicians who review a patient's cross-department diagnostic history during consultations.

### Accessible Screens & Layouts
- **Patient Search Directory**: Search bar matching name tokens.
- **Patient History Timeline**: Consolidated list of laboratory and imaging records for a selected patient.
- **Grouped Record Details**: Modal displaying test parameters, findings, and impressions.

### Permitted Actions
- Search the clinic patient directory using multi-term queries.
- View any patient's cross-department history timeline.
- Read historical findings, impressions, and values from all diagnostic visits.

### Prohibited Actions
- **No Write Permissions**: Cannot create, edit, or delete patient records or findings.
- **No Queue Views**: Cannot access active waitlists or ticket tracker queues.
- **No Document Access**: Cannot view uploaded document referral files or images.

---

## 6. Master Feature Comparison Table

| Feature / Action | Patient | Receptionist | Department Staff | Medical Specialist | Admin |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Self-Registration** | Yes | No | No | No | No |
| **Consent & Onboarding** | Yes | No | No | No | No |
| **Upload Referrals (OCR)** | Yes | No | No | No | No |
| **Use QA Chatbot** | Yes | No | No | No | No |
| **View Own Records & Queue**| Yes | No | No | No | No |
| **Verify Submissions** | No | Read-Only | No | No | No |
| **View Scoped Queue** | No | No | Read-Only | No | No |
| **Search Patients & Timelines**| No | No | No | Read-Only | No |
| **Clinic Writes & Edits** | No | No | No | No | Web-Only |
| **Queue State Changes** | No | No | No | No | Web-Only |
