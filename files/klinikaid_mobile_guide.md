# KlinikAid Mobile — Development Guide

> **Companion to `MASTER_CONTEXT.md`.** That file governs *how* the project runs and
> defines the **backend contract** (the shared Supabase schema from the web repo). This
> file describes *what* gets built, phase by phase.
>
> **Read `MASTER_CONTEXT.md` first** — especially section 2 (the web repo IS the backend
> contract) and section 4 (non-negotiable constraints). They apply to every phase here.

---

## Table of contents

- [Project overview](#project-overview)
- [Architecture](#architecture)
- [The shared data model](#the-shared-data-model)
- [Feature inventory](#feature-inventory)
- [Phase 0 — Setup & backend alignment](#phase-0--setup--backend-alignment)
- [Phase 1 — Connectivity & data layer](#phase-1--connectivity--data-layer)
- [Phase 2 — Auth & patient onboarding](#phase-2--auth--patient-onboarding)
- [Phase 3 — App shell & dashboard](#phase-3--app-shell--dashboard)
- [Phase 4 — Edge OCR & document submission](#phase-4--edge-ocr--document-submission)
- [Phase 5 — RAG chatbot via Edge Function](#phase-5--rag-chatbot-via-edge-function)
- [Phase 6 — Records, queue & status](#phase-6--records-queue--status)
- [Phase 7 — Testing, hardening & release](#phase-7--testing-hardening--release)
- [Appendix A — Folder structure](#appendix-a--folder-structure)
- [Appendix B — Capstone paper vs. implemented schema](#appendix-b--capstone-paper-vs-implemented-schema)

---

## Project overview

KlinikAid digitizes a paper-based medical laboratory. This guide covers **only the
patient mobile app** (Android). The patient is one of five system roles defined in the
shared schema; the other four (`receptionist`, `department_staff`, `medical_specialist`,
`admin`) use the web portal, which is out of scope here.

What the patient app does, mapped to the real schema:

- **Ask** — a RAG-grounded chatbot (over `rag_documents`) answers routine clinic
  questions; conversations log to `chatbot_logs`.
- **Submit** — patients photograph referral/diagnostic documents; ML Kit OCR runs
  on-device; the app inserts a row into `documents`.
- **Track** — patients follow each `documents` row through its real status: `pending` →
  `approved` / `rejected`. They also view their `patient_queue` entries.
- **View** — patients see their own `department_records` (lab/imaging results),
  read-only.

What it does **not** do: diagnose, give medical advice, show analytics, process
payments. These exclusions come from the capstone paper's stated limitations.

---

## Architecture

```
                        +--------------------------------+
                        |      PATIENT MOBILE APP        |
                        |          (Flutter)             |
                        |                                |
                        |  - ML Kit OCR  (on-device)     |
                        |  - Local cache (Drift/Isar)    |
                        |  - Supabase client (anon key)  |
                        +-------------+------------------+
                                      | HTTPS / TLS
        +-----------------------------+----------------------------+
        |                             |                            |
        v                             v                            v
+------------------+   +-----------------------------+   +----------------------+
|  Supabase Auth   |   |   Supabase Postgres         |   | Supabase Edge Function|
|  (shared with    |   |   (shared with the web app) |   |       "chat"          |
|   the web app)   |   |   - 8 tables, role-based RLS|   |  holds GEMINI_API_KEY |
+------------------+   |   - rag_documents (pgvector)|   |  embed -> retrieve -> |
                       |   Supabase Storage          |   |  generate             |
                       +-----------------------------+   +----------+-----------+
                                                                     |
                                                                     v
                                                         +----------------------+
                                                         |   Google Gemini API   |
                                                         |  embeddings + chat    |
                                                         +----------------------+
```

Key architectural rules:

- The phone talks to **Supabase directly** for normal data. This is safe **only because
  role-based RLS is on**. RLS is the security boundary, shared with the web app.
- The phone **never** talks to Gemini directly. All LLM calls go through the `chat` Edge
  Function, which holds the key. The web app calls Gemini from its Next.js server; the
  mobile app has no server, so the Edge Function is its equivalent. **Coordinate with
  the web team so there is one agreed RAG implementation.**
- OCR is **on-device** (ML Kit). Gemini does chat + embeddings only.
- `department_records` flow to the patient **without touching Gemini** — no AI ever
  interprets a patient's medical values.

---

## The shared data model

These are the tables from the web repo's `src/lib/db/schema.sql`. **The mobile app must
not change them.** Dart model classes must mirror `src/types/index.ts` field-for-field.

Tables the mobile app reads/writes:

- **`profiles`** — login identity (extends `auth.users`): `id`, `full_name`, `role`,
  `department`, timestamps. A patient's row has `role = 'patient'`, `department = null`.
- **`patients`** — clinical record: `id`, `profile_id` (FK to `profiles.id`),
  `first_name`, `last_name`, `date_of_birth`, `gender`, `contact_number`, `email`,
  `address`, timestamps.
- **`patient_queue`** — triage entries: `id` (bigint), `patient_id`, `status`
  (`waiting`/`in_progress`/`completed`/`cancelled`), `department`, `triage_notes`,
  `priority_level`, `estimated_wait_minutes`, timestamps.
- **`documents`** — submissions: `id`, `patient_id` (nullable), `uploader_id` (NOT NULL
  = `auth.uid()`), `file_name`, `file_path`, `file_type`, `status`
  (`pending`/`approved`/`rejected`), `ocr_text`, `extracted_metadata` (jsonb),
  `rejection_reason`, timestamps.
- **`department_records`** — lab/imaging results: `id`, `patient_id`, `recorder_id`,
  `department`, `test_type`, `test_results` (jsonb), `reference_range_status`, `notes`,
  timestamps.
- **`chatbot_logs`** — chat history: `id` (bigint), `user_id`, `session_id`,
  `user_message`, `bot_response`, `tokens_used`, `feedback`
  (`helpful`/`unhelpful`/null), `created_at`.
- **`rag_documents`** — RAG knowledge base: `id`, `title`, `content`, `embedding`
  (`vector(768)`), `metadata` (jsonb), `created_at`. World-readable.
- **`system_logs`** — audit trail: the app may INSERT events; it does not read them.

What the patient role can do (enforced by RLS — do not work around it):

| Table | Patient can |
|---|---|
| `profiles` | SELECT + UPDATE own row (cannot change `role`) |
| `patients` | SELECT + UPDATE own row (where `profile_id = auth.uid()`) |
| `patient_queue` | SELECT own entries |
| `documents` | SELECT own; INSERT own; UPDATE own *while still `pending`* |
| `department_records` | SELECT own only |
| `chatbot_logs` | SELECT + INSERT own |
| `rag_documents` | SELECT (world-readable) |
| `system_logs` | INSERT only |

> **Things that do NOT exist in the schema** — do not build features that depend on
> them: a 5-stage document pipeline (status is 3-state), a `lab_results` table (use
> `department_records`), a `form_templates` table, an `announcements` table. See
> Appendix B.

---

## Feature inventory

Screens the app delivers, mapped to real tables:

| Screen | Purpose | Backing table(s) | Phase |
|---|---|---|---|
| Login / Register | Secure entry; same `auth.users` as the web app | `auth.users`, `profiles`, `patients` | 2 |
| RA 10173 Privacy & Terms | Consent gate after registration | consent stored in user metadata (see Phase 2) | 2 |
| Patient Dashboard | Hub summarizing the patient's real data | `documents`, `patient_queue`, `department_records` | 3 |
| AI Chatbot | RAG-grounded FAQ assistant | `rag_documents`, `chatbot_logs` | 5 |
| Document Submission | Capture, on-device OCR, insert submission | `documents`, Supabase Storage | 4 |
| Document Status | Tracks `pending`/`approved`/`rejected` | `documents` | 6 |
| My Queue | Patient's triage queue entries | `patient_queue` | 6 |
| My Records (Results) | Read-only lab/imaging results | `department_records` | 6 |
| Profile | View/edit own profile + patient details | `profiles`, `patients` | 3 |

---

## Phase 0 — Setup & backend alignment

**Goal.** Stand up the Flutter project, get access to the **shared** Supabase project,
and create Dart models that mirror the web repo's types — so later phases never fight
the backend.

### Tasks

1. **Get shared Supabase access.** Obtain the shared project's URL and `anon` key from
   the web team. The mobile app uses the **same project** — do not create a new one.
   Never obtain or embed the `service_role` key in the app.
2. **Confirm the schema is applied.** Verify `schema.sql` has been run on the shared
   project (all 8 tables, RLS, the `handle_new_user` trigger, `pgvector`).
3. **Get a Gemini API key** for server-side use (Edge Function only, Phase 5).
4. **Initialize the Flutter project.** Minimum Android SDK **API 26 (Android 8.0)** —
   the floor for ML Kit and the paper.
5. **Set up Git** with a `.gitignore` excluding `*.env`, `local.properties`, any config
   file holding keys, and build artifacts. First commit = clean skeleton.
6. **Config injection.** Supabase URL + `anon` key passed via `--dart-define` or a
   git-ignored config file — never hard-coded in committed source.
7. **Install dependencies:** `supabase_flutter`, `google_mlkit_text_recognition`,
   `drift` or `isar`, `camera`/`image_picker`, `pdfx` (PDF viewing), `go_router`.
8. **Create Dart data models** mirroring the web repo's `src/types/index.ts`:
   `Profile`, `Patient`, `PatientQueue`, `Document`, `DepartmentRecord`, `ChatbotLog`,
   `RagDocument`. Same field names, same enum string values. These are the contract.
9. **Install the Supabase CLI** for managing the `chat` Edge Function later.

### Exit criteria

- [ ] Mobile app points at the **shared** Supabase project (web team confirmed).
- [ ] `schema.sql` confirmed applied to that project.
- [ ] Gemini key stored outside the repo.
- [ ] Flutter project builds and runs on an Android 8.0+ device/emulator.
- [ ] `git status` shows no secret files; `.gitignore` verified.
- [ ] Dart models exist and mirror `src/types/index.ts` exactly.

### Reviewer focus
Same Supabase project as web, not a new one. No secrets in the repo. Dart models match
the web types field-for-field (constraint #3). Min SDK is API 26.

---

## Phase 1 — Connectivity & data layer

**Goal.** Prove the app can talk to the shared backend and that RLS correctly scopes a
patient to their own data — before building any UI.

### Tasks

1. **Initialize the Supabase client** in the app with the shared URL + `anon` key.
2. **Build a typed data-access layer.** Thin repository classes per table the app uses
   (`ProfilesRepo`, `PatientsRepo`, `DocumentsRepo`, `DepartmentRecordsRepo`,
   `PatientQueueRepo`, `ChatbotLogsRepo`, `RagDocumentsRepo`). Each returns the Dart
   models from Phase 0.
3. **Centralize error handling** — map Supabase/Postgres errors (including RLS denials)
   to clean app-level results.
4. **Write a connectivity smoke test.** Using a known test patient account, confirm the
   app can read that patient's own `documents` and `department_records`, and confirm it
   **cannot** read another patient's rows. This verifies RLS from the mobile client.
5. **Set up environment switching** if you have separate dev/prod Supabase projects.

### Exit criteria

- [ ] App connects to the shared Supabase project.
- [ ] Repository layer returns correctly typed Dart models.
- [ ] Smoke test: a patient reads their own rows; cross-patient reads return empty.
- [ ] Errors (including RLS denials) are handled gracefully, not crashes.

### Reviewer focus
RLS verified from the mobile client, not assumed (constraint #9). Repos return the
Phase 0 models. No `service_role` usage anywhere.

---

## Phase 2 — Auth & patient onboarding

**Goal.** Working, secure entry that correctly produces **both** a `profiles` row and a
`patients` row, plus RA 10173 consent.

### Tasks

1. **Configure Supabase Auth** for email/password — the same `auth.users` the web app
   uses. (If MFA is wanted, raise it with the web team first; the schema/`.env` show no
   MFA setup yet — keep auth consistent across both apps.)
2. **Build the Login screen** — email + password, error states, link to register.
3. **Build the Register screen.** On `signUp`, pass `full_name` (and `role: 'patient'`)
   in the auth metadata so the web repo's `handle_new_user` trigger creates the
   `profiles` row automatically. Do **not** insert into `profiles` manually — the
   trigger owns that.
4. **Create the `patients` row.** This is the critical onboarding step: the trigger
   makes a `profiles` row but **not** a `patients` row. After first sign-in, if the user
   has no `patients` row (`profile_id = auth.uid()`), show a one-time "complete your
   patient profile" form collecting `first_name`, `last_name`, `date_of_birth`,
   `gender`, `contact_number`, `email`, `address`, then INSERT into `patients` with
   `profile_id = auth.uid()`. Until this row exists, patient-scoped queries return empty.
5. **Build the RA 10173 Privacy & Terms screen + consent gate.** The schema has no
   consent column. Store consent in the Supabase Auth **user metadata**
   (e.g. `privacy_consent_at`) — this needs no schema change. (Alternatively, propose a
   `profiles.privacy_consent_at` column to the web team; do not add it unilaterally.)
   Block the dashboard until consent is recorded.
6. **Session handling** — persist sessions, auto-route logged-in users, handle sign-out
   and token refresh.
7. **Log auth events** to `system_logs` where appropriate (the trigger already logs
   `USER_REGISTERED`).

### Exit criteria

- [ ] Register creates an `auth.users` + (via trigger) a `profiles` row with
      `role = 'patient'`.
- [ ] After onboarding, the user has a `patients` row linked by `profile_id`.
- [ ] Login works; sessions persist across restarts.
- [ ] A new patient cannot reach the dashboard until RA 10173 consent is recorded.
- [ ] Consent is stored without modifying the shared schema.

### Reviewer focus
The `patients` row is actually created (the most common onboarding bug — see Master
Context section 9). The trigger is not duplicated by manual `profiles` inserts. Consent
storage does not touch the schema (constraint #2).

---

## Phase 3 — App shell & dashboard

**Goal.** Navigation, a dashboard that summarizes the patient's **real** data, a profile
screen, and a local cache for graceful offline behavior.

### Tasks

1. **Build navigation** (`go_router`) — bottom nav linking Dashboard, Submit, Records,
   Chatbot, Profile.
2. **Build the Patient Dashboard** — summary cards from real tables: count of `pending`
   `documents`, current `patient_queue` status if any, most recent `department_records`
   entry. No fabricated "announcements" (no such table).
3. **Build the Profile screen** — display the joined `profiles` + `patients` data; allow
   editing the `patients` fields the RLS UPDATE policy permits.
4. **Add the local cache** (Drift/Isar) — cache the dashboard summary, the documents
   list, and a queue for offline submissions.
5. **Offline handling** — show cached data with a clear "offline" indicator; queue
   submission attempts; sync on reconnect. Chatbot and live data show an offline message.
   This matches the paper's stated offline limitation, handled gracefully.
6. **Shared UI components** — loading/empty/error states, reusable app bar.
7. **Theme** — clean, accessible, large tap targets, plain language (clinic users
   self-rated low tech comfort).

### Exit criteria

- [ ] Navigation works across all main areas.
- [ ] Dashboard shows real counts/status from `documents`, `patient_queue`,
      `department_records`.
- [ ] Profile screen reads `profiles` + `patients` and edits permitted fields.
- [ ] Local cache works; offline shows cached data + indicator, no crash.
- [ ] Shared loading/empty/error components exist and are used.

### Reviewer focus
Dashboard uses only real tables — no invented data. Profile edits respect the `patients`
UPDATE policy. Offline degrades gracefully.

---

## Phase 4 — Edge OCR & document submission

**Goal.** The signature mobile feature: capture a document, extract text **on-device**
with ML Kit, pre-screen fields, and INSERT a `documents` row.

### Tasks

1. **Build the capture flow** — capture a photo (`camera`) or pick from gallery; preview
   with retake.
2. **Integrate Google ML Kit text recognition** — recognize text entirely on-device. No
   image leaves the phone for OCR.
3. **Pre-screen the extracted text.** Check for expected fields (e.g. names, dates) and
   flag what is missing to the patient **before** upload. The app only flags — it never
   auto-rejects (constraint #7). Store findings in `extracted_metadata` (jsonb).
4. **Upload the file** to Supabase Storage (coordinate the bucket name + path
   convention with the web team so both apps agree). Keep payloads small — prefer the
   extracted text over large images (constraint #6).
5. **INSERT the `documents` row** with: `uploader_id = auth.uid()` (NOT NULL,
   required by RLS), `patient_id` = the user's `patients.id`, `file_name`, `file_path`,
   `file_type`, `status = 'pending'`, `ocr_text` = the extracted text,
   `extracted_metadata` = the pre-screen findings.
6. **Offline queuing** — if offline, store the submission in the local queue (Phase 3)
   and sync on reconnect.

### Exit criteria

- [ ] Patient can capture or pick a document image.
- [ ] ML Kit extracts text on-device — verified no image is sent for OCR.
- [ ] Pre-screen flags missing fields before upload; patient can retake or proceed.
- [ ] Submission INSERTs a `documents` row with `status = 'pending'` and a valid
      `uploader_id`; file uploaded to Storage.
- [ ] `ocr_text` and `extracted_metadata` are populated.
- [ ] Offline submissions queue and later sync.

### Reviewer focus
OCR genuinely on-device (constraint #6). The INSERT satisfies the `documents` RLS insert
policy (`uploader_id = auth.uid()`). Storage bucket/path agreed with the web team.
App pre-screens only (constraint #7).

---

## Phase 5 — RAG chatbot via Edge Function

**Goal.** A clinic FAQ chatbot grounded in `rag_documents`, with the Gemini key safely
server-side, logging to `chatbot_logs`.

### Tasks

1. **Coordinate with the web team first.** The web app will also have a chatbot. Agree
   on **one** RAG approach so there are not two divergent implementations. The mobile
   app's path is a Supabase **Edge Function** (mobile has no server of its own).
2. **Write the `chat` Edge Function** (Deno/TypeScript). Steps in order:
   a. **Embed** the user's question with a Gemini embedding model that outputs **768
      dimensions** (must match `rag_documents.embedding vector(768)`).
   b. **Retrieve** the nearest `rag_documents` rows by cosine distance (the schema
      already has an HNSW `vector_cosine_ops` index). Either query `rag_documents`
      directly or via a SQL match function — agree with the web team.
   c. **Generate** — send retrieved `content` + the question to Gemini chat with a
      strict system prompt.
3. **Store the Gemini key as an Edge Function secret:**
   `supabase secrets set GEMINI_API_KEY=...`. It never leaves the function.
4. **Write the system prompt carefully** — answer **only** from the provided clinic
   content; if unknown, say so and suggest contacting the clinic; **never** give medical
   advice, interpret lab values, or diagnose (constraint #4). The reviewer reads this
   prompt.
5. **Populate `rag_documents`.** A one-off ingestion script (run with the `service_role`
   key, server-side) that chunks clinic policy text — hours, services, prices,
   document-submission rules, FAQs — embeds each chunk (768-dim), and INSERTs
   `title`/`content`/`embedding`/`metadata`. Coordinate with the web team so the
   knowledge base is shared, not duplicated.
6. **Log every exchange to `chatbot_logs`** — `user_id = auth.uid()`, a `session_id`,
   `user_message`, `bot_response`, `tokens_used`. The RLS policy already allows a user
   to insert their own logs. Optionally support the `feedback` field
   (`helpful`/`unhelpful`).
7. **Build the chatbot screen** — chat UI calling the `chat` Edge Function; typing/error/
   offline states; optionally show prior history from `chatbot_logs`.

### Exit criteria

- [ ] `chat` Edge Function deployed; does embed -> retrieve -> generate.
- [ ] Embedding dimension is 768 (matches `rag_documents`).
- [ ] Gemini key is an Edge Function secret — confirmed absent from app and repo.
- [ ] `rag_documents` populated; chatbot answers clinic FAQs accurately.
- [ ] Out-of-scope questions get "I don't know" rather than a hallucination.
- [ ] Medical-advice questions are redirected to clinic staff; no diagnosis given.
- [ ] Every exchange is written to `chatbot_logs`.

### Reviewer focus
Read the system prompt closely — it enforces constraint #4 and RAG grounding. 768-dim
embeddings. Gemini key server-side only (constraint #1). One agreed RAG approach with
the web team. Hallucination-bait and medical-bait test prompts pass.

---

## Phase 6 — Records, queue & status

**Goal.** Complete the patient's read-side: lab/imaging records, queue status, and
document approval status — all from real tables, with live updates.

### Tasks

1. **My Records (Results) screen.** List the patient's `department_records`; tap to see
   `test_type`, `test_results` (jsonb, rendered read-only), `reference_range_status`,
   and `notes`. RLS guarantees own-records-only. Strictly read-only — no charts, no
   analytics, no interpretation (constraint #5). If a record has an associated file in
   Storage, open it in the `pdfx` viewer.
2. **Document Status screen.** List the patient's `documents` with their real status
   badge: `pending` / `approved` / `rejected`. For `rejected`, show `rejection_reason`.
   Use **Supabase Realtime** so status flips live when staff act on the web side. Do
   **not** display a fake 5-stage pipeline — the schema has 3 states.
3. **My Queue screen.** Show the patient's `patient_queue` entries: `status`,
   `department`, `priority_level`, `estimated_wait_minutes`. Realtime updates as staff
   move the queue.
4. **Cross-screen flows** — from a submitted document into its status; from the
   dashboard into records/queue.

### Exit criteria

- [ ] Records screen lists and opens the patient's own `department_records` only.
- [ ] No charts/analytics/interpretation appear for the patient.
- [ ] Document Status shows the real 3-state status; `rejection_reason` shown when
      rejected; updates live via Realtime.
- [ ] My Queue shows the patient's `patient_queue` entries and updates live.

### Reviewer focus
Records read-only and analytics-free (constraint #5). Status UI reflects the real
3-state enum, not the paper's 5-stage invention (Master Context section 9). RLS
re-verified on real data. Realtime actually fires.

---

## Phase 7 — Testing, hardening & release

**Goal.** Verify quality against the capstone's evaluation model, close security gaps,
produce a release build.

### Tasks

1. **Functional testing** — walk every screen and flow; fix bugs.
2. **ISO 25010 evaluation** — the paper evaluates software quality with ISO 25010. Run
   it across functional suitability, usability, reliability, performance efficiency, and
   security. Keep the results for the write-up.
3. **Security pass:**
   - Decompile the release APK; confirm no `GEMINI_API_KEY` and no `service_role` key.
   - Re-verify RLS by attempting cross-patient access from the app.
   - Confirm all traffic is HTTPS/TLS (Supabase enforces this).
4. **Performance check** — test on a minimum-spec device (paper's floor: quad-core
   1.5 GHz, 4 GB RAM, Android 8.0). Confirm OCR and the app perform acceptably.
5. **Accessibility & usability check** — large tap targets, readable text, plain
   language.
6. **Integration check with the web app** — confirm a patient registered on mobile is
   visible to staff on the web portal, and a document submitted on mobile appears in the
   web reception view (shared backend should make this automatic — verify it).
7. **Build the signed release APK** for the defense demo.
8. **Rehearse the defense Q&A** — especially: paper-vs-schema mismatches (5-stage
   pipeline, `form_templates`, `announcements`), and Supabase managed-cloud vs. the
   paper's "self-hosted server" (see `MASTER_CONTEXT.md` section 9).

### Exit criteria

- [ ] All core flows pass functional testing.
- [ ] ISO 25010 evaluation completed and documented.
- [ ] Release APK contains no secrets — verified by decompiling.
- [ ] RLS re-verified; TLS confirmed.
- [ ] App runs acceptably on a minimum-spec device.
- [ ] Mobile/web integration verified on the shared backend.
- [ ] Signed release APK produced.

### Reviewer focus
The decompiled-APK secret check is mandatory and actually done. ISO 25010 coverage is
complete. Mobile/web integration on the shared backend works. Defense answers ready.

---

## Appendix A — Folder structure

A feature-first Flutter layout. Adjust to team preference; keep features isolated.

```
lib/
  main.dart
  app/
    theme.dart
    router.dart
  core/
    supabase/            # shared Supabase client init
    models/              # Phase 0 - Dart models mirroring web src/types/index.ts
    repositories/        # Phase 1 - typed data-access layer per table
    cache/               # Drift/Isar local cache
    widgets/             # shared loading/empty/error widgets
    utils/
  features/
    auth/                # Phase 2 - login, register, patient onboarding, consent
    dashboard/           # Phase 3 - hub + profile
    documents/           # Phase 4 + 6 - submission, OCR, status tracking
    chatbot/             # Phase 5 - chat UI
    records/             # Phase 6 - department_records viewer
    queue/               # Phase 6 - patient_queue view
supabase/
  functions/
    chat/                # Phase 5 - RAG Edge Function (coordinate with web team)
  scripts/
    ingest_knowledge.ts  # Phase 5 - rag_documents ingestion
```

> Note: the schema (`schema.sql`) lives in and is owned by the **web repo**. The mobile
> repo does not carry its own copy of migrations — it consumes the shared backend.

---

## Appendix B — Capstone paper vs. implemented schema

The capstone paper describes some features the **implemented schema does not have**.
Build to the schema; flag these for the paper revision and the defense.

| Paper says | Schema reality | Mobile app does |
|---|---|---|
| 5-stage document pipeline (Submitted -> AI Verified -> Staff Review -> Approved -> Result Available) | `documents.status` has 3 values: `pending`, `approved`, `rejected` | Show the real 3-state status |
| "Lab Results" as its own thing | No `lab_results` table; results are in `department_records` | Read `department_records` |
| Clinic Form Templates module | No `form_templates` table | Out of scope until the web team adds it |
| Dashboard "announcements" | No `announcements` table | Dashboard summarizes real data only |
| OpenRouter for the LLM | Web repo uses Gemini (`@google/generative-ai`) | Use Gemini (already the standard) |
| RAG DB "self-hosted on the clinic server" | `rag_documents` lives in managed Supabase | Use Supabase; have the data-residency answer ready |
| Multi-factor authentication | No MFA setup in schema/`.env` | Keep auth consistent with web; raise MFA jointly if wanted |

**Documentation task** (not code): update the capstone paper's Tables 5-6, the System
Architecture section, and the module descriptions so the written paper matches the
implemented schema. Either correct the paper text, or have the team formally agree to
extend the shared schema *before* the build depends on the new tables.
