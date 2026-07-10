# Antigravity Task — Phase R1: Reception Queue + Document Validation (Read)

> **Type:** first phase of receptionist write-capable workstation build.
> **This phase = READ ONLY foundation.** No write actions yet. Queue
> viewing + document validation viewing. Writes come in R2 (route) + R3
> (reject).
> **Effort:** ~2 days.
> **Scope correction:** this REVERSES Constraint #12's over-restriction.
> Paper documents receptionist as write-capable on both platforms; panel
> confirmed follow-paper + 1:1 web parity. Mobile was over-restricted →
> this phase begins correcting that.
> **Prerequisite:** NONE for RLS. Schema confirms receptionists already
> have FULL access to documents + patients + patient_queue at the DB
> level (web uses these). R1 read + R2/R3 writes all inherit existing
> RLS. No new policies, no migration.

---

## Context

Web team's receptionist is a full workstation (per uploaded screenshots):
- Reception Dashboard (queue counts, pending, recent triage)
- Reception Queue (5-column kanban: Submitted / AI Verified / Staff
  Review / Approved / Rejected)
- Document Validation (patient details, OCR text, AI confidence, view
  original)
- Approve & Route (triage modal → department, vitals, notes)
- Reject (reason + 20-char feedback)

Paper says receptionist is write-capable on BOTH web + mobile. Mobile
currently read-only (Constraint #12 over-restriction). This build
corrects mobile to match paper.

**Phased approach:**
- R1 (this) → Queue view + Document Validation view (READ)
- R2 → Approve & Route (WRITE)
- R3 → Reject w/ reason presets (WRITE)
- R4 → Reception Dashboard
- R5 → Constraint #12 rewrite + full tests + docs

---

## R1 scope → read-only foundation

Build the receptionist's ability to:
1. Navigate via bottom-nav (Dashboard placeholder / Queue / Profile)
2. See queue of submissions organized by status
3. Tap a submission → open Document Validation screen
4. View: patient details, OCR text output, AI confidence, document
   metadata, view original document link

NO writes this phase. Approve/Route/Reject buttons present but DISABLED
w/ "Coming in next update" tooltip OR hidden entirely (agent picks —
recommend disabled+labeled so the screen layout is complete for R2/R3).

---

## Locked design

### Receptionist bottom-nav

Mirror patient bottom-nav pattern for consistency:

```
[ Dashboard ]  [ Queue ]  [ Profile ]
```

- Dashboard → placeholder this phase (R4 builds it) → show "Dashboard
  coming soon" or basic welcome card
- Queue → the main R1 deliverable
- Profile → reuse existing profile pattern (receptionist's own profile,
  read-only staff info)

Role-gated: only `receptionist` role sees this nav. Routing dispatches
receptionist → `/reception/queue` as home.

### Reception Queue → tab bar layout

Mobile-native tabs (not web's 5-column kanban):

```
[ Submitted ] [ Approved ] [ Rejected ]
```

Simplification from web's 5 columns → mobile's 3 tabs:
- **Submitted** → web's "Submitted" + "AI Verified" + "Staff Review"
  combined (all pending states) → receptionist sees everything needing
  action
- **Approved** → web's "Approved"
- **Rejected** → web's "Rejected"

Each tab → scrollable list of submission cards.

**Submission card shows:**
- Patient name (or "Unknown Patient" if OCR couldn't extract)
- Upload source badge (e.g., "Mobile Upload" / "Web Upload")
- Relative time ("about 17 hours ago")
- File name (e.g., patient_b_doc.pdf)
- Uploaded-by name
- Tap target → opens Document Validation

**Search bar** at top → filter by patient name / file name / type.
(Basic client-side filter this phase; server-side search post-defense.)

**Count badge** per tab → number of submissions in that state.

### Document Validation screen

Opened by tapping a submission card. Read-only this phase.

**Sections (stacked vertically for mobile):**

1. **Header** → "Document Validation" + Back to Queue + Status badge
   ("Pending Review" / "Approved" / "Rejected")

2. **Patient Details card:**
   - Name, Date of Birth, Gender, Contact Number, Email, Address
   - Show "—" or "Unknown Patient" for fields OCR couldn't populate

3. **OCR Text Output card:**
   - Monospace raw text of extracted document content
   - "No OCR text extraction available for this document." if empty
   - Label: "MONOSPACE RAW"

4. **AI Validation Report card (STATIC PLACEHOLDER this phase):**
   - Web team has NOT built OCR confidence scoring yet → no score
     exists in the DB to read
   - Card renders in the layout (matches web structure) but is a
     static placeholder → ALWAYS shows:
     - "Overall AI Confidence → No OCR Score"
     - "Confidence score not available for this upload."
   - Do NOT parse extracted_metadata for a score — the field has no
     score yet
   - Post-defense: wire real scoring when web ships it

5. **Document Metadata card:**
   - File Name, File Type, Uploaded At, Uploaded By
   - "View Original Document" button → opens document (Supabase Storage
     signed URL)

6. **Receptionist Actions bar (bottom):**
   - "Reject Document" button → DISABLED this phase (R3 enables)
   - "Approve & Route Patient" button → DISABLED this phase (R2 enables)
   - Tooltip/label on disabled buttons: "Available soon"

---

## What gets built

### 1. MODIFY `app_router.dart`

- Add receptionist route dispatch → `receptionist` role → `/reception/queue` as home
- Add routes:
  - `/reception/queue` → ReceptionQueueScreen
  - `/reception/document/:submissionId` → DocumentValidationScreen
  - `/reception/dashboard` → placeholder (R4)
  - `/reception/profile` → reuse profile
- Role guard → only receptionist reaches these
- Constraint #10 preserved → admin still blocked
- Constraint #12 → NOTE: being revised across R1-R5. This phase adds
  read views. Don't delete #12 yet — R5 rewrites it.

### 2. NEW → `reception_shell.dart` (bottom-nav scaffold)

Location: `lib/features/reception/presentation/reception_shell.dart`

- Bottom nav w/ 3 tabs (Dashboard / Queue / Profile)
- Mirror patient shell pattern
- Receptionist-only

### 3. NEW → `reception_queue_screen.dart`

Location: `lib/features/reception/presentation/screens/reception_queue_screen.dart`

- TabBar: Submitted / Approved / Rejected
- Each tab → ListView of submission cards
- Search bar (client-side filter)
- Count badges per tab
- Tap card → navigate to Document Validation

### 4. NEW → `document_validation_screen.dart`

Location: `lib/features/reception/presentation/screens/document_validation_screen.dart`

- 5 read-only cards (patient / OCR / AI report [static placeholder] / metadata / disabled actions)
- Disabled action bar (Reject / Approve buttons present but inert)
- View Original Document → signed URL open

### 5. NEW → `submission_card.dart` (widget)

Location: `lib/features/reception/presentation/widgets/submission_card.dart`

- Reusable card for queue lists

### 6. NEW → `reception_repository.dart`

Location: `lib/features/reception/data/reception_repository.dart`

- `getSubmissions({status})` → reads from documents/submissions table
  scoped by RLS
- `getSubmissionDetail(id)` → single submission w/ OCR text + patient
  details + metadata (NO AI confidence — not built by web yet)
- `getOriginalDocumentUrl(id)` → signed Storage URL
- READ ONLY this phase — no write methods

### 7. NEW → domain models

Location: `lib/features/reception/domain/`

- `Submission` model → id, patientName, fileName, fileType, uploadedAt,
  uploadedBy, status, source
- `SubmissionDetail` model → adds OCR text, patient details, storage
  path. NO aiConfidence field — web team hasn't built OCR scoring yet
  (see AI Validation Report note below)
- `SubmissionStatus` enum → submitted, aiVerified, staffReview,
  approved, rejected

Match web team's data shapes → coordinate field names w/ shared DB.

### 8. Reuse existing formatter helpers where applicable

- Queue status → may reuse `queue_status_formatter` pattern
- Match existing presentation-layer helper discipline

---

## Confirmed schema (from web team's DB docs)

**Schema verified. Use these EXACT column names.**

### `documents` table

```
id            uuid PK
patient_id    uuid FK patients.id ON DELETE CASCADE
uploader_id   uuid FK profiles.id ON DELETE SET NULL   ← NOT uploaded_by
file_name     text NOT NULL
file_path     text NOT NULL   ← storage object key for signed URL
file_type     text NOT NULL
status        text default 'pending' CHECK: pending | approved | rejected
ocr_text      text nullable
extracted_metadata  jsonb nullable
rejection_reason    text nullable
```

**RLS:** Admins & Receptionists → FULL access. Patients → own docs only
(insert/update only when status='pending').

**Key facts:**
- ONLY 3 statuses: `pending` / `approved` / `rejected`. There is NO
  ai_verified or staff_review DB status. All pending → Submitted tab.
- `uploader_id` NOT `uploaded_by` (common mistake — use uploader_id)
- `file_path` = storage object key → feed to createSignedUrl
- NO ai_confidence column. AI scoring NOT built by web yet → AI
  Validation Report card is a static placeholder (see above)
- **Receptionist already has FULL RLS access** → R2/R3 writes need NO
  new RLS policy. Web uses these writes already; mobile inherits.

### `patients` table (for patient details join)

```
id             uuid PK
profile_id     uuid FK profiles.id
first_name     text NOT NULL
last_name      text NOT NULL
date_of_birth  date NOT NULL
gender         text CHECK: male | female | other
contact_number text NOT NULL
address        text NOT NULL
email          text nullable
```

RLS: Receptionists → FULL access.

**"Unknown Patient" handling:** if `documents.patient_id` is null OR
the joined patients row is missing → show "Unknown Patient" + "—" for
each field. (Happens when OCR couldn't match the upload to a patient.)

### Join for queue list

`documents` → `patients` (via patient_id) for patient name → and
`profiles` (via uploader_id) for uploader name.

### Storage

`documents.file_path` = object key inside the storage bucket. Use
Supabase Storage `createSignedUrl(file_path)` for View Original.

**No migration needed — read-only phase, all columns exist.**

---

## Files affected

**New:**
- `lib/features/reception/presentation/reception_shell.dart`
- `lib/features/reception/presentation/screens/reception_queue_screen.dart`
- `lib/features/reception/presentation/screens/document_validation_screen.dart`
- `lib/features/reception/presentation/widgets/submission_card.dart`
- `lib/features/reception/data/reception_repository.dart`
- `lib/features/reception/domain/submission.dart`
- `lib/features/reception/domain/submission_detail.dart`
- `lib/features/reception/domain/submission_status.dart`
- `test/phase_r1_reception_queue_test.dart`
- `test/phase_r1_document_validation_test.dart`

**Modified:**
- `lib/core/routing/app_router.dart`
- `files/MASTER_CONTEXT.md` (note R1-R5 in progress, #12 under revision)

---

## Tests

### `phase_r1_reception_queue_test.dart`

Widget:
1. Receptionist login → lands on reception queue (not patient dashboard)
2. Three tabs render: Submitted / Approved / Rejected
3. Each tab shows count badge
4. Submission cards render w/ patient name, file, time
5. Tap card → navigates to Document Validation
6. Search filters list by patient name
7. Search filters by file name
8. Empty state → "No documents" per empty tab
9. Non-receptionist role → cannot reach reception queue (route guard)

### `phase_r1_document_validation_test.dart`

Widget:
10. Patient details card renders all fields
11. Unknown patient → shows "Unknown Patient" + "—" fields
12. OCR text card shows extracted text
13. Empty OCR → "No OCR text extraction available"
14. AI Validation Report card → always shows "No OCR Score" (static placeholder, web hasn't built scoring)
15. AI card shows "Confidence score not available for this upload."
16. Metadata card shows file name, type, uploaded at/by
17. Reject + Approve buttons DISABLED this phase
18. View Original Document → triggers URL open (mock)
19. Back to Queue → returns to queue

### Regression (must pass)
- All existing phase9 + auth + registration tests
- Patient flow unaffected
- Staff (department/specialist) unaffected

---

## Verification

```bash
flutter analyze
flutter test test/phase_r1_reception_queue_test.dart
flutter test test/phase_r1_document_validation_test.dart
flutter test test/phase9_registration_otp_test.dart      # regression
flutter test test/phase9_mfa_verify_test.dart            # regression
flutter test                                              # full suite

# Constraint #1
flutter build apk --release
apktool d build/app/outputs/flutter-apk/app-release.apk -o /tmp/decompiled
grep -r "AIzaSy" /tmp/decompiled       # 0 matches
grep -r "GEMINI" /tmp/decompiled       # 0 matches
grep -r "service_role" /tmp/decompiled # 0 matches
```

**Manual test:**
1. Login as receptionist test account
2. Land on Reception Queue (bottom nav visible)
3. See Submitted / Approved / Rejected tabs w/ counts
4. Tap a submission → Document Validation opens
5. Verify all 5 cards render w/ real data from shared DB
6. Verify Reject/Approve buttons disabled
7. Tap View Original → document opens
8. Verify patient login still works (regression)
9. Verify department/specialist staff login still works (regression)

---

## Screenshots (4)

- `reception_queue_submitted_tab.png` → queue w/ submitted tab active,
  cards visible, counts
- `reception_queue_tabs.png` → showing all 3 tabs + search
- `document_validation_full.png` → full validation screen w/ all cards
- `document_validation_disabled_actions.png` → bottom action bar w/
  disabled Reject/Approve buttons

---

## Constraint check

| Constraint | Status | Notes |
|---|---|---|
| #1 Gemini key server-side | UNCHANGED | Re-verified |
| #10 Admin blocked | UNCHANGED | Admin still rejected at login |
| #12 Staff read-only | UNDER REVISION | R1 adds receptionist read views; #12 rewritten in R5 to reflect paper's write-capable receptionist. Do NOT delete #12 yet. |
| #13 Registration OTP | UNCHANGED |
| #14 Session inactivity | UNCHANGED | Applies to receptionist too (10 min staff) |
| #15 Staff TOTP | UNCHANGED | Receptionist TOTP prompt still fires if enrolled |
| All others | UNCHANGED |

---

## Defense framing (partial — full story after R5)

*"The receptionist workstation on mobile mirrors the web platform per
our documented one-to-one design. Phase 1 delivers the queue view and
document validation screen: receptionists see patient submissions
organized by status, open any submission to review extracted OCR text,
AI confidence scoring, and patient details. Write actions — routing and
rejection — build on this foundation in subsequent phases."*

---

## Watch items at Gate B/D

1. Data models match web team's shared schema exactly (field names,
   status enum strings) — confirm w/ web team before build
2. Route guard → only receptionist reaches reception screens
3. Existing staff (department/specialist) read-only views unaffected
4. Session timeout + TOTP still apply to receptionist
5. "Unknown Patient" edge case handled gracefully (null patient_id)
6. Disabled action buttons clearly communicate "coming soon" not broken
7. Signed URL for original document → expires appropriately, RLS-scoped

---

## Next phases (preview)

- **R2** → Approve & Route: triage modal, department dropdown
  (laboratory/imaging/ultrasound/ecg — matches patient_queue.department
  CHECK), vitals (BP/weight/temp), triage notes → INSERT patient_queue
  (status='waiting', triage_notes as JSON string matching existing
  triage_notes_formatter shape) + UPDATE documents SET status='approved'.
  NO new RLS — receptionist already has access. triage_notes JSON shape:
  {"queue_number": "...", "vitals": {"blood_pressure": "...",
  "weight_kg": N, "temperature_c": N}}
- **R3** → Reject w/ reason presets: buttons (Illegible text / Unrelated
  files / Other), textbox, 20-char min → UPDATE documents SET
  status='rejected', rejection_reason='...' (single column, exists in
  schema). NO new RLS.
- **R4** → Reception Dashboard: queue counts, pending submissions,
  recent triage activity, operational guide.
- **R5** → Constraint #12 rewrite, full integration tests, walkthrough,
  defense narrative.
