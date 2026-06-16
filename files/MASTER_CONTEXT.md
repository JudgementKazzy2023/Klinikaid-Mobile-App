# KlinikAid Mobile — Master Context

> **Purpose of this file.** Single source of truth that oversees the entire KlinikAid
> patient mobile app project. It governs *how* the project is built and reviewed. Paired
> with `klinikaid_mobile_guide.md`, which describes *what* is built. Read both before
> starting any phase.
>
> **Audience.**
> 1. The **AI coding agent inside Antigravity** — treat this file as standing
>    instructions. Re-read the relevant phase section before generating code.
> 2. The **human reviewer** (Claude, in chat) — this file defines the review protocol.

---

## 1. Project identity

| Field | Value |
|---|---|
| System name | KlinikAid |
| This deliverable | **Multi-role mobile app** (Android) — patient + scoped staff access |
| Roles supported on mobile | Patient (register + login), Receptionist (login only), Department Staff (login only), Medical Specialist (login only) |
| Roles NOT on mobile | **Admin / Owner** — administered exclusively via the web portal |
| Out of scope | Full web staff/admin portal (separate team — the `KlinikAid` web repo) |
| Client | Bloodcare Medical Laboratory (Burgos, Rodriguez, Rizal, PH) |
| Academic context | BS Information Technology capstone, FEU Diliman |
| Primary coding tool | Antigravity (agentic IDE, Gemini-powered) |
| Reviewer | Claude (chat) — reviews each phase's plan and completion |

### One-paragraph project description
KlinikAid digitizes patient intake and inquiry handling for a small medical laboratory
that currently runs on paper. The **mobile app** serves two user populations: (1) patients
register and self-serve via the patient flow (RAG chatbot, on-device-OCR document
submission, results viewing), and (2) clinic staff in three roles — receptionist,
department staff, medical specialist — sign in to a **scoped staff mode** that
complements the web portal's full staff workflow. The app gives **no** medical diagnosis,
advice, or analytics — all clinical decisions stay with clinic staff.

### Scoping rule for staff on mobile
The web portal is the **primary** staff interface. The mobile app provides a
**deliberately scoped, mostly-read-only** staff experience for on-the-go use cases
(checking the queue from a corridor, glancing at a patient document before walking into a
room). The mobile app does **not** attempt feature parity with the web staff portal.
Heavy data entry — creating walk-in patients, entering lab results, configuring policies
— remains on the web side. See section 7 for the per-role mobile scope.

### Admin / Owner — explicitly NOT on mobile
The Admin role manages users, RBAC, audit logs, and system configuration. **None of this
ships on mobile.** Admins use the web portal exclusively. This is a deliberate security
boundary: a stolen unlocked phone with an admin session would be far more dangerous than
the same phone with a receptionist session. The mobile app's login screen MUST reject
sign-in attempts for any account whose `profiles.role = 'admin'` with a clear message:
*"Admin accounts must sign in via the web portal."*

### Registration rule (critical)
**Only `role='patient'` accounts can be created via the mobile app's Register flow.**
Receptionist, Department Staff, and Medical Specialist accounts are created by an Admin
via the web portal. The mobile app's Register screen MUST hard-code `role='patient'` when
calling `auth.signUp()` — it never exposes a role selector. Staff users who somehow find
the Register screen and attempt to sign up are creating only a patient account; their
existing staff account on the web is unaffected.

---

## 2. THE WEB REPO IS THE BACKEND CONTRACT

This is the most important section. The mobile app is **not** a fresh build — it is a
**second client on a backend the web team already designed.** The web repository
(`KlinikAid`, Next.js + TypeScript + Supabase) contains the authoritative database
schema at `src/lib/db/schema.sql`. The mobile app **must conform to it exactly** and
**must not** alter it.

### Hard rule
The mobile team does **not** design or change the database schema. Table names, column
names, enum values, RLS policies, and the `handle_new_user` trigger are all fixed by the
web repo. If the mobile app needs a schema change, it is **proposed to the web team and
agreed jointly** — never done unilaterally. Both apps share one Supabase project.

### What the web repo already establishes (do not re-invent)

- **Supabase** is the backend (Postgres + Auth + Storage + `pgvector`). Confirmed by
  `.env.example` and `@supabase/supabase-js`.
- **Gemini** is the LLM and PDF/OCR-extraction AI. Confirmed by `@google/generative-ai`
  and `GEMINI_API_KEY` in `.env.example`. **The OpenRouter→Gemini change from the paper
  is already the project standard — there is no conflict.**
- **`pgvector` with `vector(768)`** powers RAG via the `rag_documents` table.
- **Role-based RLS** via two SECURITY DEFINER helper functions, `get_auth_user_role()`
  and `get_auth_user_dept()`. Five roles: `admin`, `receptionist`, `department_staff`,
  `medical_specialist`, `patient`.
- **A signup trigger** (`handle_new_user`) auto-creates a `profiles` row from
  `auth.users` metadata, defaulting `role` to `patient`.

### The authoritative data model (from `schema.sql`)

Eight tables. The mobile app touches the ones marked **[MOBILE]**.

| Table | Purpose | Mobile app use (per role) |
|---|---|---|
| `profiles` **[MOBILE]** | Login identity; extends `auth.users`. Has `role`, `department`. | Patient: read/update own. Staff: read own + visible profiles per RLS. |
| `patients` **[MOBILE]** | Clinical patient record. Linked to profile via `profile_id`. | Patient: read/update own. Receptionist: read all (per RLS). Department staff/Specialist: read all (per RLS). No CREATE from mobile. |
| `patient_queue` **[MOBILE]** | Triage queue entries. | Patient: read own. Receptionist: read all + update arrival status. Department staff: read scoped to their `department`. Specialist: read all. |
| `documents` **[MOBILE]** | Patient document submissions. | Patient: read/insert/update own. Receptionist: read all + approve/reject status. Department staff/Specialist: read scoped per RLS. |
| `department_records` **[MOBILE]** | Lab/imaging results. | Patient: read own. Department staff: read scoped to their department. Specialist: read all. No INSERT/UPDATE from mobile. |
| `system_logs` | Audit trail. | Insert only (via app events). Admin reads on web. |
| `chatbot_logs` **[MOBILE]** | Chatbot conversation history. | Patient: read/insert own. Staff: not used. |
| `rag_documents` **[MOBILE]** | RAG knowledge base (`vector(768)`). | Patient: read via chatbot. Staff: not used. |

### Schema facts the mobile app MUST respect

1. **`profiles` and `patients` are separate tables.** A patient logs in via a `profiles`
   row (identity) and has a clinical `patients` row linked by `patients.profile_id =
   profiles.id`. The app must create/fetch both. A freshly registered user has a
   `profiles` row (auto, from the trigger) but **no `patients` row yet** — the app must
   handle that gap (see the guide, Phase 2).
2. **There is no `lab_results` table.** Lab and imaging results are rows in
   `department_records`. The patient "Lab Results" screen reads `department_records`
   filtered to the patient.
3. **`documents.status` has exactly three values:** `pending`, `approved`, `rejected`.
   The capstone paper's 5-stage pipeline ("Submitted → AI Verified → Staff Review →
   Approved → Result Available") does **not** exist in the schema. The mobile app shows
   the real 3-state status. Do not invent a 5-stage column. (If the team wants the
   5-stage UX, that is a schema-change proposal to the web team, not a mobile-only act.)
4. **There is no `form_templates` table and no `announcements` table.** Any "form
   template" or "dashboard announcement" feature is **out of scope** unless the web team
   adds the tables. Do not build screens that depend on tables that do not exist.
5. **`documents` requires `uploader_id` (NOT NULL)** = the submitting user's
   `auth.uid()`. `patient_id` is nullable and references `patients.id`. The RLS insert
   policy requires `uploader_id = auth.uid()`.
6. **`department_records.test_results` is `jsonb`** — flexible. The app renders it
   read-only; it never interprets values.
7. **`rag_documents` is world-readable** (`USING (true)`). RAG retrieval can be done
   client-side OR server-side, but **embedding generation and the Gemini call must be
   server-side** (key safety — see constraint #1 below).
8. **RLS is role-based**, evaluated through `get_auth_user_role()`. A `patient` sees
   only their own `patients`, `documents`, `department_records`, `patient_queue`, and
   `chatbot_logs` rows. This is the security boundary for both apps.
9. **Types are already defined** in the web repo's `src/types/index.ts`. The mobile
   app's data models (Dart classes) must mirror these field-for-field so the two
   codebases agree.

### Web repo state (updated 2026-06-11)
The web team has built substantially more since the initial zip:
- Full **staff portals** for `admin`, `reception`, `specialist`, `department` roles.
- A **patient web portal** at `/patient/{dashboard,chat,submit,submissions,results}`
  — mirrors the mobile app's feature set (see CURRENT REALITY below).
- Their own `/api/chat` endpoint (Next.js server route, not a Supabase Edge Function).
- A `tailwind.config.ts` and `globals.css` defining a light cream + forest-green
  design system. Mobile theme is aligned to this as of 2026-06-11.

The shared `schema.sql` is unchanged in shape — same 8 tables — with two notable
adjustments:
- `profiles.accepted_privacy_at` is now a real column (the web team's preferred
  consent-storage location, instead of user metadata).
- `match_rag_documents` RPC is not present in the canonical schema yet (it remains
  in `web_reference/schema_proposals.md` pending adoption).

### CURRENT REALITY — Active project state

**Supabase project:** The mobile app now points at **`onzeyejlfydvvbkejvwf`**
(migrated 2026-06-10 from the original mobile project `vxnkpcqyrxdqxpvutkmm`). This
appears to be the web team's project. **Verify with the web team in writing** that
this is the shared project. The schema-applied check from Phase 0 must be re-run on
the new project before assuming it is in the expected state.

**Edge Function deployment:** The `chat` Edge Function from Phase 5 was deployed to
the original project. It is **not automatically present** on the migrated project.
Until it is redeployed (and the `GEMINI_API_KEY` secret is re-set), the chatbot will
fail with HTTP 404 `NOT_FOUND`. The `rag_documents` knowledge base must also be
re-ingested on the new project.

**Patient web portal:** The web team has built a complete patient-facing portal
that overlaps with the mobile app's feature set. Treat both as legitimate clients
of one backend: the mobile app remains the primary patient experience; the web
portal serves patients on desktop / walk-ins / staff filling on behalf.

**Visual design alignment (2026-06-11):** The mobile app's theme was migrated from
the dark indigo aesthetic (Phase 2) to the web team's light cream + forest-green
palette. See `antigravity_task_theme_migration.md` for the design tokens. Phase 2
walkthrough text describing a "premium dark-themed aesthetic" is now historical —
defenders should frame the change as "aligned visual language with the web team for
a consistent patient experience across clients."

Rules while operating in this state:

1. **Schema is still owned by the web team.** Constraint #2 stands: the mobile team
   does not edit the schema unilaterally. Proposals continue to live in
   `web_reference/schema_proposals.md`.
2. **`web_reference/schema.sql` and `web_reference/index.ts`** in the mobile repo
   are dated snapshots. Refresh whenever the web team changes the schema; note the
   refresh date and which web-repo commit it came from.
3. **`web_reference/migration_notes.md`** tracks events that change project state:
   the 2026-06-10 Supabase project migration and the 2026-06-11 theme alignment are
   recorded there.
4. **Hard checkpoint reconfirmed:** before Phase 7's mobile/web integration test,
   the team must verify the new shared project's schema and the deployment status
   of the `chat` Edge Function. Phase 7 cannot meaningfully exit without these.

---

## 3. Stack of record (mobile app)

Aligned with the web repo. The mobile app adds only client-side and Edge-Function pieces.

| Layer | Technology | Notes |
|---|---|---|
| Mobile framework | **Flutter (Dart)** | Confirm with team; Kotlin only if explicitly decided |
| Backend / database | **Supabase** (shared project with web) | Schema fixed by the web repo |
| Auth | **Supabase Auth** (email/password) | Same `auth.users` the web app uses |
| Vector store / RAG | **`rag_documents`** table (`vector(768)`) | Already in the schema |
| LLM + AI OCR assist | **Google Gemini API** | Same as web (`@google/generative-ai`) |
| LLM access path | **Supabase Edge Function** holding `GEMINI_API_KEY` | Mobile has no server of its own |
| On-device OCR | **Google ML Kit text recognition** | Mobile-only; paper requirement |
| File storage | **Supabase Storage** | Shared buckets with web; respect RLS/paths |
| Realtime | **Supabase Realtime** | For live `documents`/`patient_queue` status |
| Local cache | **Drift** or **Isar** | Offline graceful degradation |

---

## 4. Non-negotiable constraints

Any plan or code violating one of these **fails review automatically**.

1. **No secrets in the app.** `GEMINI_API_KEY` and the Supabase `service_role` key never
   appear in the Flutter app, the APK, or the repo. Only the Supabase `anon` key + URL
   ship in the client, and only because RLS protects the data.
2. **Do not modify the shared schema.** The mobile app conforms to the web repo's
   `schema.sql`. Schema changes are proposed to and agreed with the web team — never
   done unilaterally. (See section 2.)
3. **Match the web repo's data model exactly.** Dart models mirror
   `src/types/index.ts`. Same table names, column names, enum values.
4. **The app gives no medical advice.** The chatbot answers administrative/clinic
   questions only — never diagnoses, interprets `department_records` values, or
   recommends treatment. Enforced in the Edge Function system prompt.
5. **No analytics for the Patient role.** The descriptive-analytics dashboard (paper's
   specialist feature) is not built into the mobile app at all. Specialists on mobile
   see read-only departmental views, not the full analytics dashboard.
6. **On-device OCR.** Document text is extracted on the phone with ML Kit. Raw images
   are minimized in transit.
7. **Human-in-the-loop.** The app's OCR only pre-screens and flags. Staff set
   `documents.status`. The app never auto-approves/rejects.
8. **Scope discipline.** If a feature is not in `klinikaid_mobile_guide.md` — or depends
   on a table that does not exist in `schema.sql` — it is out of scope until the guide
   (and, if needed, the shared schema) is formally updated.
9. **RLS is the security boundary.** The app trusts RLS to isolate patient data. Never
   work around it with the `service_role` key in the client.
10. **Admin role is BLOCKED on mobile.** The login flow MUST reject any account whose
    `profiles.role = 'admin'`. The mobile app NEVER surfaces admin features, even
    behind feature flags. A panel demo of "what happens if an admin tries to log in"
    is part of defense readiness.
11. **Registration creates ONLY `role='patient'`.** The Register screen hard-codes
    `role='patient'` in the `auth.signUp()` call and exposes no role selector. Staff
    accounts are created exclusively by an Admin via the web portal.
12. **Mobile is read-mostly for staff.** Staff roles (receptionist, department_staff,
    medical_specialist) on mobile see scoped read views and limited state changes
    (e.g., queue arrival confirm, document status changes within their permission).
    They do NOT enter new patients, new lab values, or new policies on mobile — those
    are web-portal actions.

---

## 5. How the project is governed: the phase protocol

The project is built in **7 phases** (section 7; detailed in the guide). Each phase
moves through **four gates**. The human reviewer (Claude) signs off at gates B and D.

```
  Gate A          Gate B            Gate C           Gate D
  +------+      +--------+      +----------+      +----------+
  | Plan | ---> | Plan   | ---> |  Build   | ---> |Completion|
  |drafted|      | review |      | (agent)  |      | review   |
  +------+      +--------+      +----------+      +----------+
   you/agent     REVIEWER         Antigravity        REVIEWER
                 approves         executes           approves -> next phase
```

- **Gate A — Plan drafted.** You (with the agent) write a one-page Phase Plan using the
  template in section 6.
- **Gate B — Plan review.** Paste the Phase Plan to Claude. Reviewer responds
  **APPROVED**, **APPROVED WITH CHANGES**, or **REVISE**. Do not build until approved.
- **Gate C — Build.** The Antigravity agent implements the approved plan.
- **Gate D — Completion review.** Send Claude the Phase Completion Report plus
  code/diffs. Reviewer responds **PASS** or **CHANGES REQUIRED**. Only a PASS unlocks
  the next phase.

---

## 6. Templates (copy these when messaging the reviewer)

### 6.1 Phase Plan template (Gate B)

```
PHASE PLAN — Phase <N>: <name>

Goal of this phase (1-2 sentences):

Tasks I intend to do, in order:
  1.
  2.
  3.

Files/modules that will be created or changed:

Tables from schema.sql this phase touches (and how):

How this phase satisfies the relevant non-negotiable constraints:

Open questions or decisions I need the reviewer to weigh in on:

Anything I plan to deviate from in the guide, and why:
```

### 6.2 Phase Completion Report template (Gate D)

```
PHASE COMPLETION REPORT — Phase <N>: <name>

What was built:

Exit criteria from the guide — status of each:
  - [ ] criterion 1 — done / partial / blocked
  - [ ] criterion 2 — ...

Deviations from the approved plan, and why:

Constraint self-check (answer yes/no honestly):
  - No secrets in the app/repo?
  - Schema left unchanged (no unilateral edits)?
  - Dart models still match src/types/index.ts?
  - No medical advice introduced?
  - Scope stayed within the guide?

Known issues / tech debt carried forward:

Code I'm attaching for review:

Question for the reviewer:
```

---

## 7. The phases at a glance

The patient flow (Phases 0-6) is complete. Phases 7-9 add the scoped staff mode and
final hardening. Full detail in `klinikaid_mobile_guide.md`.

| Phase | Name | Exit condition (short form) |
|---|---|---|
| 0 | Setup & backend alignment | Flutter project + shared Supabase access; no secrets committed; Dart models mirror web types |
| 1 | Connectivity & data layer | App connects to the shared Supabase; can read RLS-protected data as a patient |
| 2 | Auth & patient onboarding | Login/register work (patient role); new patient gets a `patients` row; consent handled |
| 3 | App shell & dashboard | Patient navigation; dashboard summarizes the patient's real data; offline cache |
| 4 | Edge OCR & document submission | ML Kit OCR on-device; inserts a `documents` row correctly |
| 5 | RAG chatbot via Edge Function | Edge Function does embed→retrieve→generate; logs to `chatbot_logs` |
| 6 | Records, queue & status | `department_records`, `patient_queue`, `documents` status all viewable; live updates |
| **7** | **Role-aware login & routing** | **Login detects role; admins are blocked; patient/reception/staff/specialist route to correct home; registration hard-coded to `patient`** |
| **8** | **Staff mode (read-mostly)** | **Receptionist, Department Staff, Medical Specialist each have a scoped home screen reading the right tables under RLS; minimal state changes only** |
| 9 | Testing, hardening & release | ISO 25010 evaluation; security pass; release APK; web/mobile integration tested |

**Critical for Phase 7-8 scope:**
- The mobile app is **not** trying to reproduce the web staff portal. The web is primary.
- Each staff role on mobile gets ONE focused screen, plus read-only access to the rest of
  their data. No deep workflow construction on mobile.
- Heavy data entry (new patients, new lab values, schema config) stays on web.

**Progress tracker:**

- [x] Phase 0 — PASS date: 2026-05-24
- [x] Phase 1 — PASS date: 2026-05-24
- [x] Phase 2 — PASS date: 2026-05-24
- [x] Phase 3 — PASS date: 2026-06-02
- [x] Phase 4 — PASS date: 2026-06-02
- [x] Phase 5 — PASS date: 2026-06-05
- [x] Phase 6 — PASS date: 2026-06-08
- [x] **Phase 7 — Role-aware login & routing — PASS date: 2026-06-16**
- [ ] **Phase 8 — Staff mode (read-mostly) — PASS date: ____**
- [ ] Phase 9 — Testing, hardening & release — PASS date: ____

**Out-of-band work between Phase 6 and Phase 7:**

- 2026-06-10 — **Supabase project migration** from `vxnkpcqyrxdqxpvutkmm` to
  `onzeyejlfydvvbkejvwf`. Phase 5 unit tests added.
- 2026-06-11 — **Visual theme alignment** with the web team's design system
  (light cream + forest-green). Replaces the dark indigo theme from Phase 2.
- 2026-06-11 — **Scope expansion approved:** staff roles (receptionist, department_staff,
  medical_specialist) added to mobile per the capstone paper. Admin role explicitly
  excluded from mobile. New Phases 7-8 added; original Phase 7 (Testing/Release)
  renumbered to Phase 9.
- **Open before Phase 7 starts:** redeploy `chat` Edge Function to the new project,
  re-set `GEMINI_API_KEY` secret, re-ingest `rag_documents`, run the 4-query schema
  check on the new project.

---

## 8. How the reviewer (Claude) should behave

1. **Anchor every review to this file.** Check submissions against section 2 (backend
   contract), section 4 (constraints), and the relevant phase exit criteria.
2. **Guard the schema.** Reject any plan or code that adds, drops, or alters a column,
   table, enum, or policy in the shared backend. Flag any feature that depends on a
   table not in `schema.sql`.
3. **Be specific and actionable.** Point to the exact table, file, or constraint.
4. **Give a clear verdict.** Plan reviews end APPROVED / APPROVED WITH CHANGES / REVISE.
   Completion reviews end PASS / CHANGES REQUIRED. Never ambiguous.
5. **Prioritize constraints over polish.** Beautiful UI with a leaked key, a schema edit,
   or a model mismatch does not pass.
6. **Catch capstone risks.** Flag anything a defense panelist would question (see
   section 9).
7. **Keep the human oriented.** End each review by stating the current gate and the next.

## 9. Standing risks to keep visible

> Updated 2026-06-11 to reflect Phases 0-6 PASS, the project migration, and the
> theme alignment.

### Active risks

- **Edge Function not deployed on the new project.** After the 2026-06-10 migration
  to `onzeyejlfydvvbkejvwf`, the `chat` Edge Function from Phase 5 must be
  redeployed, the `GEMINI_API_KEY` secret re-set, and `rag_documents` re-ingested.
  Until done, the chatbot returns HTTP 404 on every message. **Block Phase 7 work
  until resolved.**
- **Phase 4 `FailureMapper` bug.** `StorageException` / `HttpException` during
  offline upload maps to `UnknownFailure` instead of `NetworkFailure`, breaking the
  offline-queue fallback. Identified 2026-06-10. **Fix before re-running Module 4
  of the 60% test script.**
- **Shared project identity not confirmed in writing.** The migration to
  `onzeyejlfydvvbkejvwf` is presumed to be the web team's shared project, but
  written confirmation has not been recorded. Get the web team to confirm in
  writing before Phase 7's integration test.
- **Consent storage location.** The web team's canonical schema added
  `profiles.accepted_privacy_at` as a real column. The mobile app currently writes
  consent to Supabase Auth user metadata (`privacy_consent_at`). One sentence
  alignment task during Phase 7: migrate mobile to write to the canonical column.
- **`match_rag_documents` RPC adoption.** Still in `web_reference/schema_proposals.md`,
  not yet in the canonical `schema.sql`. Track per-proposal adoption status.
- **Paper vs. reality mismatches.** The capstone paper describes features the
  schema does not implement: a 5-stage document pipeline, `form_templates`,
  dashboard `announcements`. Prepared answer: the build follows the *implemented*
  schema; the paper text needs updating before final submission.
- **Phase 2 walkthrough describes the old dark theme.** As of 2026-06-11 the
  mobile app uses the web's light cream + forest-green palette. Either update
  Phase 2's walkthrough to reflect the alignment, or have the answer ready:
  "we aligned visual language with the web team for a consistent patient
  experience across clients."
- **Supabase managed cloud vs. paper's "self-hosted server."** Prepared answer:
  free tier, encrypted in transit and at rest, self-hostable via Docker if the
  clinic later requires on-premise.
- **Staff scope on mobile is read-mostly, not full parity.** Added 2026-06-11. Mobile
  staff features are intentionally limited compared to the web portal. Panelist
  question expected: *"Why can't a receptionist do everything from mobile?"* Prepared
  answer: *"Mobile is for on-the-go status checks. Heavy data entry — creating walk-ins,
  entering lab results — is faster and safer on web with a full keyboard and screen.
  This is a deliberate UX scope decision, not a missing feature."*
- **Admin-block enforcement.** Added 2026-06-11. The login flow must reject
  `role='admin'` accounts. This is a security boundary, not a UX preference. Phase 7
  must demonstrate this with an actual admin account and a panel-ready denial flow.
- **Registration role hard-coding.** Added 2026-06-11. The Register screen must
  hard-code `role='patient'` in the `auth.signUp()` call and exposes no role selector. Staff
  accounts are created exclusively by an Admin via the web portal.
- **Mobile is read-mostly for staff.** Staff roles (receptionist, department_staff,
  medical_specialist) on mobile see scoped read views and limited state changes
  (e.g., queue arrival confirm, document status changes within their permission).
  They do NOT enter new patients, new lab values, or new policies on mobile — those
  are web-portal actions.

### Resolved (do not re-raise)

- ✅ **`profiles` vs `patients` onboarding gap** — explicit onboarding step
  creates the `patients` row (Phase 2).
- ✅ **No Edge Function for Gemini** — `chat` function built in Phase 5
  (pending redeployment to the new project — see active risks).
- ✅ **Gemini key in the app** — verified absent via APK decompile + secrets
  list (Phase 5 walkthrough).
- ✅ **`schema_proposals.md` sent to the web team** — confirmed in Phase 5
  walkthrough section 6.
- ✅ **Realtime + RLS isolation** — verified with two-patient test for both
  `patient_queue` and `documents` (Phase 6 walkthrough).
