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
| This deliverable | Patient-facing **mobile app only** (Android) |
| Out of scope | Web staff/admin portal (separate team — the `KlinikAid` web repo) |
| Client | Bloodcare Medical Laboratory (Burgos, Rodriguez, Rizal, PH) |
| Academic context | BS Information Technology capstone, FEU Diliman |
| Primary coding tool | Antigravity (agentic IDE, Gemini-powered) |
| Reviewer | Claude (chat) — reviews each phase's plan and completion |

### One-paragraph project description
KlinikAid digitizes patient intake and inquiry handling for a small medical laboratory
that currently runs on paper. The **mobile app** is the patient's entry point. It lets
patients (a) ask routine questions through a RAG-grounded AI chatbot, (b) submit
referral/diagnostic documents validated **on-device** with OCR before upload, (c) track
those submissions, and (d) view their own finalized lab/diagnostic records. The app
gives **no** medical diagnosis, advice, or analytics — all clinical decisions stay with
clinic staff.

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

| Table | Purpose | Mobile app use |
|---|---|---|
| `profiles` **[MOBILE]** | Login identity; extends `auth.users`. Has `role`, `department`. | Read/update own row |
| `patients` **[MOBILE]** | Clinical patient record. Linked to a profile via `profile_id`. | Read/update own row |
| `patient_queue` **[MOBILE]** | Triage queue entries. | Read own entries |
| `documents` **[MOBILE]** | Patient document submissions for approval. | Read/insert/update own |
| `department_records` **[MOBILE]** | Lab/imaging results (this is where lab results live). | Read own only |
| `system_logs` | Audit trail. | Insert only (via app events) |
| `chatbot_logs` **[MOBILE]** | Chatbot conversation history. | Read/insert own |
| `rag_documents` **[MOBILE]** | RAG knowledge base (`vector(768)` embeddings). | Read only |

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

### Web repo state (as of the shared zip)
The web app has Supabase client/server/middleware wiring, auth helpers
(`requireRole`, `requireDepartment`), constants, types, and the complete `schema.sql`.
Feature pages are **not built yet** (only `/`, `/403`, `layout`). Implication: the
**schema is stable and safe to build against**, but the chatbot/OCR server endpoints do
not exist yet — the mobile app will need its own server-side path (a Supabase Edge
Function) for anything requiring the Gemini key.

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
   specialist feature) is not built into the mobile app at all.
6. **On-device OCR.** Document text is extracted on the phone with ML Kit. Raw images
   are minimized in transit.
7. **Human-in-the-loop.** The app's OCR only pre-screens and flags. Staff set
   `documents.status`. The app never auto-approves/rejects.
8. **Scope discipline.** If a feature is not in `klinikaid_mobile_guide.md` — or depends
   on a table that does not exist in `schema.sql` — it is out of scope until the guide
   (and, if needed, the shared schema) is formally updated.
9. **RLS is the security boundary.** The app trusts RLS to isolate patient data. Never
   work around it with the `service_role` key in the client.

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

## 7. The 7 phases at a glance

Full detail in `klinikaid_mobile_guide.md`. This is the progress index.

| Phase | Name | Exit condition (short form) |
|---|---|---|
| 0 | Setup & backend alignment | Flutter project + shared Supabase access; no secrets committed; Dart models mirror web types |
| 1 | Connectivity & data layer | App connects to the shared Supabase; can read RLS-protected data as a patient |
| 2 | Auth & patient onboarding | Login/register work; new patient gets a `patients` row; consent handled |
| 3 | App shell & dashboard | Navigation works; dashboard summarizes the patient's real data; offline cache |
| 4 | Edge OCR & document submission | ML Kit OCR on-device; inserts a `documents` row correctly |
| 5 | RAG chatbot via Edge Function | Edge Function does embed→retrieve→generate over `rag_documents`; logs to `chatbot_logs` |
| 6 | Records, queue & status | `department_records`, `patient_queue`, `documents` status all viewable; live updates |
| 7 | Testing, hardening & release | ISO 25010 evaluation; security pass; release APK |

**Progress tracker:**

- [x] Phase 0 — PASS date: 2026-05-24
- [x] Phase 1 — PASS date: 2026-05-24
- [x] Phase 2 — PASS date: 2026-05-24 (Conditional on web team RLS policy adoption)
- [ ] Phase 3 — PASS date: ____
- [ ] Phase 4 — PASS date: ____
- [ ] Phase 5 — PASS date: ____
- [ ] Phase 6 — PASS date: ____
- [ ] Phase 7 — PASS date: ____

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

- **Schema divergence between apps.** The single biggest risk. Mobile and web share one
  database; if the mobile app expects a column the web team renames, both break. Mobile
  conforms; coordinate any change.
- **Paper vs. reality mismatches.** The capstone paper describes features the schema
  does not implement: a 5-stage document pipeline, `form_templates`, dashboard
  `announcements`. The defense will surface this. Prepared answer: the build follows the
  *implemented* schema; the paper text should be updated to match, or the team formally
  agrees to extend the schema before the build relies on it.
- **Gemini key exposure.** The most likely security mistake. The key lives only in a
  Supabase Edge Function secret. Re-verify every phase touching the chatbot.
- **`profiles` vs `patients` gap.** A new signup has a `profiles` row but no `patients`
  row. If the app assumes a `patients` row exists, patient-scoped queries return empty.
  Phase 2 must explicitly create the `patients` row.
- **No Edge Functions exist yet.** The web app calls Gemini from its Next.js server. The
  mobile app has no server, so it needs its own Edge Function. Coordinate with the web
  team so there is one agreed RAG implementation, not two divergent ones.
- **RA 10173 consent has no schema column.** Consent currently has nowhere to be stored.
  Options: store it in `auth.users` user metadata, or propose a `profiles` column to the
  web team. Decide in Phase 2 — do not silently skip consent.
- **Supabase managed cloud vs. paper's "self-hosted server."** Prepared answer: free
  tier, Singapore region, encrypted in transit and at rest; self-hostable via Docker if
  the clinic later requires on-premise.
