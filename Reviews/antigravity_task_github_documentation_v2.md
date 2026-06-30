# Antigravity Task — KlinikAid Mobile GitHub Documentation Set (Private Repo)

> **Task type:** documentation only — no code changes, no business logic touched.
> **Goal:** produce a polished, defense-grade documentation set for a
> **private** GitHub repository combining a portfolio-grade README, technical
> setup docs, and the capstone development story.
> **Repo visibility:** PRIVATE — only the capstone team and reviewers can
> access. Bloodcare Medical Laboratory may be named in plain language.
> **Estimated effort:** 1-2 days of focused writing. No emulator work needed.

> **Important — this brief supersedes a previous brief from 2026-06-21.** The
> project state has materially evolved since then. This brief reflects the
> defense-day state of the codebase as of 2026-06-23, including all eight
> post-Phase-9 scope tightenings and the formatter-helper architectural
> pattern.

---

## Context for this task

The KlinikAid Mobile App (Android, Flutter) is the patient-and-staff-facing
mobile client for a clinic management system shared with a separate web
team. Development progressed through nine gated phases, plus a series of
final-hardening scope tightenings discovered during integration testing.
All work is complete and verified end-to-end.

This task produces the **user-facing documentation** that will live in the
private GitHub repository. It does NOT include internal capstone artifacts
like phase-review files, plan reviews, walkthroughs, or briefs — those stay
in the team's local working directory.

---

## What to produce

A documentation set inside the repository:

```
KlinikAid-Mobile/
├── README.md                          ← top-level, polished, portfolio-grade
├── LICENSE                            ← MIT (confirm with project lead)
├── CONTRIBUTING.md                    ← brief, since the repo is private
├── .gitignore                         ← env.dart, *.jks, .env excluded
└── docs/
    ├── 01-overview.md                 ← what this app is, who it's for
    ├── 02-architecture.md             ← how the pieces fit together
    ├── 03-setup.md                    ← dev environment + run instructions
    ├── 04-development-story.md        ← the capstone journey (longest doc)
    ├── 05-features.md                 ← per-role feature inventory
    ├── 06-security.md                 ← RLS, role boundaries, on-device OCR
    └── 07-deployment.md               ← release build and distribution
    └── assets/screenshots/            ← copied from defense materials folder
```

10 files at the paths above, plus the screenshots assets folder.

---

## CRITICAL — Credential & Project-ID Handling Rules (NON-NEGOTIABLE)

These rules apply throughout the build, not just verified at the end. The
agent enforces them while writing, not as a post-build cleanup:

1. **Never paste or include real Supabase project IDs** anywhere. The
   project IDs `vxnkpcqyrxdqxpvutkmm` (old paused) and `onzeyejlfydvvbkejvwf`
   (current shared) must NOT appear in any file. **Always** use the
   placeholder format: `<your-supabase-project-id>.supabase.co`.

2. **For `env.dart` examples**, write only the placeholder version:
   ```dart
   class Env {
     static const String supabaseUrl = 'https://<your-supabase-project-id>.supabase.co';
     static const String supabaseAnonKey = '<your-supabase-anon-key>';
   }
   ```
   Never the real values, not even truncated, not even as a comment.

3. **For Edge Function setup**, use:
   `supabase secrets set GEMINI_API_KEY=<your-gemini-api-key>`.
   Never a partial real key. Never `AIzaSy...` even as illustrative example.

4. **JWT tokens and other secrets in screenshots** — redact or blur any
   `eyJ`-prefix tokens visible in screenshot captures.

5. **Mentioning historical migrations** — the project migrated Supabase
   projects mid-build. Reference this as *"the original development project"*
   and *"the shared production project"* without naming real IDs.

The agent runs the verification greps at the END of the build to confirm
no leakage. But the discipline is "never write the real value" from the
first draft.

---

## File specifications

### `README.md` (root)

Polished, under 200 lines. Structure:

1. **Title + one-sentence description.**
   *"KlinikAid Mobile — a patient-and-staff-facing Android app for Bloodcare
   Medical Laboratory, built in Flutter with a Supabase backend."*

2. **Status badge row.** shields.io badges for: Flutter version, Android
   minSdk, license. Use placeholder shield URLs if exact versions are not
   known.

3. **Screenshots row.** Three side-by-side screenshots: Login, Patient
   Dashboard, Chatbot. Reference files in `docs/assets/screenshots/`.

4. **Quick start (5 lines max).** Clone, install, configure env, run. Full
   setup is in `docs/03-setup.md`.

5. **What this app does.** Two paragraphs.

6. **Tech stack table.** Flutter, Dart, Supabase (Postgres+Auth+Storage+
   pgvector+Edge Functions), Gemini API via Edge Function, Google ML Kit
   on-device OCR, Drift (SQLite) local cache.

7. **Roles supported.** Brief table:

   | Role | Mobile access |
   |---|---|
   | Patient | Full feature set: chatbot, OCR submissions, records, queue |
   | Receptionist | Documents lookup only (3 tabs: Pending/Approved/Rejected) |
   | Department Staff | Department-scoped queue + records, read-only |
   | Medical Specialist | Patient search + cross-department timeline, read-only |
   | Admin / Owner | **Blocked on mobile — web portal only** (security boundary) |

8. **Documentation index.** Links to all 7 files in `docs/`.

9. **Acknowledgments.** Capstone team (Healthioneers — placeholder
   `[Team Member Name]` entries for project lead to fill in), FEU Diliman,
   web team partnership, Bloodcare Medical Laboratory client.

10. **License.**

### `LICENSE`

MIT License. Year: 2026. Holder: `[Healthioneers Capstone Team]`. Project
lead confirms the institution accepts MIT before merge — flag this as a
`[Placeholder]` item.

### `CONTRIBUTING.md`

Under 30 lines, private-repo appropriate:

- Setup: link to `docs/03-setup.md`
- Branching: simple feature branches → main
- Commit messages: `type(scope): description` convention
- Code style: `flutter analyze` clean before commit
- Test policy: new features include accompanying tests in `test/`

### `.gitignore`

```
# Flutter / Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/

# IDE
.idea/
.vscode/
*.iml

# Android signing keys
*.jks
*.keystore
key.properties
android/app/upload-keystore.jks

# Secrets — NEVER commit
lib/core/config/env.dart            # Supabase URL + anon key
supabase/.env                       # GEMINI_API_KEY
*.env
.env.local
.env.production

# OS
.DS_Store
Thumbs.db

# Test outputs
coverage/

# APK release artifacts (optional)
build/app/outputs/flutter-apk/
```

**Project lead's decision:** include `pubspec.lock` for reproducible
builds (do NOT add it to gitignore).

### `docs/01-overview.md` — what this app is

150-250 lines, user-facing language, no code blocks. Covers:

- The clinical problem (paper-based intake at Bloodcare Medical Laboratory)
- What the mobile app delivers (patient self-service; scoped read-only
  staff portals)
- What the web app delivers (referenced, not detailed — web team's domain)
- Shared-backend architecture (one Supabase project, two clients, shared
  schema, shared RLS policies)
- Out-of-scope items (no medical diagnosis, no admin role on mobile,
  receptionist queue management on web only, staff actions are web-only)

### `docs/02-architecture.md` — how the pieces fit together

200-300 lines. Covers:

1. **System diagram** (text-based or ASCII). Components: Android device,
   Supabase project (Auth, Postgres+RLS, Storage, Realtime, Edge Functions,
   pgvector), Gemini API (called only via Edge Function), Google ML Kit
   (on-device), web portal (referenced, not detailed).

2. **Folder structure tree.** `lib/` layout with one-line descriptions per
   folder. Features include: auth, dashboard, ocr, chatbot, records, queue,
   staff (with sub-folders for reception, department, specialist).

3. **State management.** Provider pattern; per-feature providers; auth
   state is the root.

4. **Routing.** GoRouter with role-aware redirection; dispatcher at `/`
   reads `profiles.role` and routes to one of: `/patient`, `/staff/reception`,
   `/staff/department/{department}`, `/staff/specialist`.

5. **Local caching.** Drift (SQLite) for offline-first patient data with
   identity-mismatch guarding (orphans cached items if a different patient
   signs in).

6. **Network layer.** `supabase_flutter` SDK for all backend operations.
   No raw HTTP for Supabase.

7. **The Edge Function.** What it does (Gemini RAG over `rag_documents`
   with pgvector embeddings, returns grounded answers + refuses out-of-
   context and medical-advice queries). Why it exists (keeps the Gemini
   key server-side per Constraint #1 — no key in the APK).

8. **The architectural reuse pattern (formatter helpers).** This is a
   distinctive architectural decision worth documenting. Three pure-Dart
   helpers normalize how shared backend data renders across multiple
   mobile surfaces:
   - `triage_notes_formatter.dart` (extracts the human-readable note from
     web's JSON-wrapped triage notes; applied at 4 sites)
   - `record_grouper.dart` (consolidates multi-parameter `department_records`
     rows into a single grouped card; applied at 4 surfaces)
   - `queue_status_formatter.dart` (maps status enum to per-audience
     display labels; applied at 4 surfaces)
   - `grouped_record_detail_modal.dart` (shared presentation widget;
     consumed by both patient records and specialist Patient History)

   Section closes with: *"This pattern is intentional. Single domain
   helper + applied at every rendering site + unit tests against the
   helper + widget regression guards = no drift across surfaces and easy
   future changes."*

### `docs/03-setup.md` — developer onboarding

250-400 lines. The most practical document. A new team member should be
able to run the app in 30 minutes using only this file.

Sections:

1. **Prerequisites:**
   - Flutter (channel stable, version from `pubspec.yaml`)
   - Dart (matched to Flutter)
   - Android Studio (current stable)
   - JDK 17
   - puro (if used)
   - Note: project is Android-only minSdk=26; no iOS setup needed

2. **Clone the repo.** Standard `git clone` command using placeholder
   repo URL.

3. **Configure environment.**
   - Copy `lib/core/config/env.dart.example` to `lib/core/config/env.dart`
   - Set `supabaseUrl` and `supabaseAnonKey` from the project's Supabase
     dashboard (placeholders only in this doc)
   - Note: GEMINI_API_KEY is NEVER set in the app; it lives only as a
     Supabase Edge Function secret

4. **Install dependencies:** `flutter pub get`

5. **Set up the emulator:**
   - Android Studio → Device Manager → create AVD (Pixel 6, API 34
     recommended)
   - Uncheck "Launch in tool window" in Settings → Tools → Emulator
     (emulator opens as separate window)

6. **Run the app:** `flutter run -d <device_id>`. Use `flutter devices`
   to list available targets.

7. **Run tests:** `flutter test` (full suite, 90+ tests). Individual
   files: `flutter test test/<filename>`.

8. **Common issues and fixes (real ones from development):**
   - "Emulator window not visible" → check Running Devices panel
   - "Lost connection to device" → app still works; reconnect with
     `flutter run`
   - "DNS resolution failure" → Supabase project may be paused; resume
     from dashboard
   - "FunctionException 404" → Edge Function not deployed to current
     project
   - "Tests fail with 403 StorageException" → check Supabase Storage RLS
     policies are applied

### `docs/04-development-story.md` — the capstone journey

600-1000 lines. The longest doc and the most portfolio-valuable. Structure:

1. **The problem.** Bloodcare Medical Laboratory's paper-based intake;
   the team's mandate to digitize.

2. **The team.** Healthioneers — four-member capstone team. One mobile
   developer (`[Team Member Name]` placeholder); three web developers on
   a separate repo.

3. **The four-gate phase protocol.** Plan → Gate B review → Build →
   Gate D review. Why this discipline mattered for a sole-developer
   mobile project.

4. **The nine phases.** One paragraph each. Cover:

   - **Phase 0:** Setup and backend alignment
   - **Phase 1:** Connectivity and data layer
   - **Phase 2:** Auth, RA 10173 consent, patient onboarding (note the
     `profiles` vs `patients` schema gap)
   - **Phase 3:** App shell and patient dashboard
   - **Phase 4:** Edge OCR with Google ML Kit (on-device privacy)
   - **Phase 5:** RAG chatbot via Supabase Edge Function (Gemini)
   - **Phase 6:** Records, queue, status with Realtime
   - **Phase 7:** Role-aware login with admin-block (Constraint #10)
   - **Phase 8:** Staff mode (Receptionist, Department, Specialist —
     initially read-mostly)
   - **Phase 9:** Testing, hardening, release (ISO 25010 evaluation)

5. **Post-Phase-9 final hardening.** A new section unique to this project's
   honesty about how integration testing improves real software. Cover
   the EIGHT scope tightenings:

   - **Fix 1: Department staff read-only conversion.** Removed "Start
     Service" and "Complete" buttons. RLS continued to permit the actions
     (web portal still uses them); mobile UI no longer exposed them.

   - **Fix 2: Triage notes JSON formatter.** Web team stored queue
     metadata as JSON in `patient_queue.triage_notes`. Mobile was
     rendering the raw JSON to users. Built a presentation-layer formatter
     that extracts the human-readable `notes` field. Applied at four
     rendering sites. Also fixed a quiet data-hygiene issue: patient-
     facing screens were leaking internal queue metadata.

   - **Fix 3: Receptionist Documents three-tab view.** Replaced the
     single "Pending Documents" tab with three nested sub-tabs (Pending /
     Approved / Rejected). Approved and Rejected use a 30-day window;
     Rejected cards show the rejection reason. Receptionist now has
     full document lifecycle visibility.

   - **Fix 4: Receptionist queue tab hidden.** Joint architectural
     decision with the web team — queue management is web-portal-owned.
     The mobile receptionist becomes a documents-lookup tool with no
     queue surface. Queue code, state, and Realtime subscription
     preserved in the provider for potential future re-enabling.

   - **Fix 5: Records grouping.** The schema stores test parameters as
     separate rows (Findings, Impression for one X-ray = two rows).
     Mobile was showing two cards; web shows one. Built a domain helper
     that groups by `(patient_id, department, recorded_at within
     5-minute bucket)`. Single-parameter records still render as before
     (backward compat). Multi-parameter records consolidate into one
     card with worst-case-wins status badge and stacked detail sections.

   - **Fix 6: Binary queue status display.** The patient queue UI
     showed "0 min estimated wait" alongside a "NOW CALLING" title —
     contradictory, since the schema has no wait-time projection. Built
     a status formatter that maps `patient_queue.status` to per-audience
     labels: patients see "IN QUEUE / Waiting in Queue" (clock icon) or
     "NOW CALLING / Now Being Called" (speaker icon); staff see
     "WAITING" or "IN PROGRESS" badges. No false precision.

   - **Fix 7: Medical specialist three bugs.** Search broke on multi-
     term queries with spaces — fixed with split-by-whitespace term-AND
     matching, case-insensitive, order-independent. Patient History
     timeline duplicated multi-parameter records — fixed by reusing the
     records grouper. Long clinical text overflowed the card — fixed
     with Flexible+softWrap. Bonus: extracted the detail modal into a
     shared widget reused by both patient and specialist surfaces.

   - **Fix 8: OCR Retake redirect.** Retake button on the OCR preview
     screen redirected to the camera; now redirects to the OCR landing
     page so the patient can choose Camera or Gallery.

6. **Architectural decisions worth recording.**
   - Why Flutter (single codebase, first-class Supabase Dart SDK,
     on-device ML Kit, Dart type alignment with web's TypeScript, single-
     dev productivity)
   - Why Supabase (one backend, two clients, shared schema, shared RLS)
   - Why on-device OCR (RA 10173 compliance via privacy-first architecture)
   - Why admin is blocked on mobile (security boundary; staff-grade
     actions belong on the web)
   - Why staff scope is fully read-only (consistent mobile-as-viewing-
     tool philosophy; web-as-action-platform)
   - Why three formatter helpers as an architectural pattern (single
     source of truth, no drift across surfaces, easy future changes)

7. **ISO 25010 evaluation results.** Summarize the four load scenarios
   with honest framing (especially Scenario 1's reframing from initial
   finding to graceful-degradation evidence). Reference the real-device
   performance numbers (Android 8.0 / 4GB).

8. **Defense-in-depth pattern.** Constraint #11 (registration hard-codes
   `role='patient'` AND the database trigger defaults unknown roles to
   patient) and Constraint #10 (admin block on mobile login). Both
   constraints have client-side enforcement AND database-side enforcement
   — defense in depth means either layer alone would not be sufficient.

9. **Architectural reuse story.** The records feature exposes both a
   domain helper (`groupRecords()`) and a shared presentation widget
   (`GroupedRecordDetailModal`). Four mobile surfaces consume them:
   patient records, patient queue derivation, department staff Recent
   Records, and specialist Patient History. Single source of truth for
   how clinical results are grouped, sorted, badged, and displayed.

10. **What we'd do differently.** Be honest:
    - Sooner coordination with the web team on shared-project ownership
      (caused mid-project Supabase project migration)
    - Earlier alignment of mobile and web design systems (we migrated
      themes mid-project at Phase 6/7)
    - More aggressive test coverage of offline paths (Phase 9 surfaced
      gaps)
    - Earlier user-testing of the receptionist queue UI (avoided the
      final-week scope tightening)

### `docs/05-features.md` — per-role feature inventory

300-400 lines. Table format. For each role, list every screen, every
action permitted, every action NOT permitted.

Example structure for Patient:

```markdown
## Patient

### Screens
- Login / Register / Consent / Onboarding (Phase 2)
- Dashboard (Phase 3)
- Submit Document with OCR (Phase 4)
- Chatbot (Phase 5)
- Records, Queue, Document Status (Phase 6)

### Permitted actions
- Self-register (`role='patient'` hard-coded per Constraint #11)
- Accept RA 10173 privacy consent
- Submit clinical onboarding details
- Submit documents via camera or gallery (OCR runs on-device)
- Ask the chatbot administrative questions
- View own records, queue, document statuses
- Update own profile

### NOT permitted
- View other patients' data (RLS-enforced)
- Set their own role to anything other than patient
- Self-promote to a staff role (Constraint #11 enforced client AND DB)
```

Same pattern for Receptionist (Documents-only — three tabs, no queue),
Department Staff (Department Queue + Recent Records, read-only),
Medical Specialist (Patient search + Patient History timeline).

For each staff role, the "NOT permitted" column is large — listing all
the state-change actions that moved to web. This visually communicates
the read-only architecture.

### `docs/06-security.md` — security architecture

300-400 lines. Becomes a defense-prep artifact too.

1. **Constraint inventory.** All 12 constraints in plain language with
   how each is enforced.

2. **RLS as canonical boundary.** Explain: client-side checks are UX;
   the database is the source of truth.

3. **Defense-in-depth examples.**
   - Registration role hard-coding (client side hard-codes `'role':
     'patient'`; database `handle_new_user` trigger defaults unknown roles
     to patient as a safety net)
   - Admin block (login screen rejects `role='admin'` AND session-restore
     path rejects re-entry)
   - Department isolation (GoRouter route guard + provider client filter
     + RLS policy in Postgres — all three layers active)
   - Cross-patient data isolation (RLS-only — strongest layer for the
     highest-stakes data)

4. **What's tested.** Reference the test files (no need to paste output,
   just list which tests prove which constraint). The Phase 8 RLS
   verification chain is the strongest evidence — including the
   write-bypass probe.

5. **APK security pass.** Process: `flutter build apk --release` →
   `apktool d` to decompile → grep for `AIzaSy`, `GEMINI`, `service_role`,
   project IDs. All return zero matches. Proves Gemini key is contained
   server-side per Constraint #1.

6. **RA 10173 compliance.** Privacy consent flow stored in
   `profiles.accepted_privacy_at`. On-device OCR via ML Kit. No
   patient data leaves the device during OCR.

### `docs/07-deployment.md` — release build and distribution

100-200 lines. Cover:

1. **Pre-build checks.** `flutter analyze` clean; `flutter test` all
   green (current count: 90+ tests).

2. **Build the release APK.** `flutter build apk --release`. Output path
   note.

3. **Signing.** Debug keystore for academic deployment; production keystore
   path for clinic deployment (reference only, do NOT commit keys).

4. **Versioning.** `pubspec.yaml` version stamp.

5. **Distribution.** Sideload via USB for capstone defense; or upload to
   a private team folder for reviewers.

6. **APK security pass.** Recap the decompile process from `docs/06-
   security.md`.

---

## Verification — explicit grep checklist

After the build, the agent runs each command and pastes the actual
output in the walkthrough. Each item has explicit pass criteria.

```bash
# 1. No Gemini API key prefix anywhere
grep -r "AIzaSy" README.md CONTRIBUTING.md LICENSE docs/ .gitignore
# Expected: zero matches

# 2. No "GEMINI" string anywhere in docs/ or README
grep -r "GEMINI" docs/ README.md
# Expected: zero matches except in setup.md where it's the placeholder
#           `<your-gemini-api-key>` — confirm any matches use the placeholder

# 3. No service_role string anywhere
grep -r "service_role" README.md CONTRIBUTING.md LICENSE docs/
# Expected: zero matches

# 4. No real Supabase project IDs
grep -r "vxnkpcqyrxdqxpvutkmm" README.md CONTRIBUTING.md LICENSE docs/
grep -r "onzeyejlfydvvbkejvwf" README.md CONTRIBUTING.md LICENSE docs/
# Expected: zero matches each

# 5. No JWT tokens (eyJ prefix)
grep -r "eyJ" README.md CONTRIBUTING.md LICENSE docs/
# Expected: zero matches

# 6. No internal phase-review or capstone artifact references
grep -ri "phase[0-9]_review\|MASTER_CONTEXT\|klinikaid_mobile_guide\|antigravity_task" README.md docs/
# Expected: zero matches

# 7. Placeholder format used consistently
grep -r "<your-supabase" docs/ README.md
# Expected: matches present (proves placeholders ARE being used)

# 8. Code sanity (in case the agent touched anything by accident)
flutter analyze
# Expected: "No issues found!" or unchanged from current baseline
flutter test
# Expected: "All tests passed!"
```

The agent pastes the **actual output** of all 8 checks in the walkthrough.
Items 1-6 with zero matches; item 7 with matches present; items 8a and
8b clean.

---

## Important constraints (recap)

1. **No secrets in any documentation.** Always placeholders.
2. **No internal capstone artifact references.** Phase reviews, plan
   reviews, walkthroughs, MASTER_CONTEXT, briefs — all stay out of the
   repo.
3. **Real clinic name OK.** Bloodcare Medical Laboratory may be named.
   But no real patient names anywhere — use "Patient A" or placeholder
   names. No real staff emails.
4. **Screenshot copies, not links.** Copy the screenshot files into
   `docs/assets/screenshots/` and reference them with relative paths.
   Existing screenshots from the defense punch list:
   - admin_block_dialog.png
   - consent_back_fill.png
   - dept_after_no_action_buttons.png
   - triage_after_clean_notes.png
   - records_grouping_detail_modal.png
   - reception_after_queue_hidden_documents_view.png
   - reception_after_queue_hidden_pending_subtab.png
   - queue_patient_now_calling.png

   Some screenshots from the punch list may not yet exist (queue_patient_
   waiting.png, queue_dashboard_tile.png, queue_department_card.png,
   the specialist screenshots). For each missing file, create a
   `PLACEHOLDER_<name>.txt` in `docs/assets/screenshots/` describing
   what the screenshot should show. The project lead will capture
   them on the emulator before merge.

5. **No fabricated content.** If the agent doesn't know something
   specific (team members' GitHub handles, exact license year preference,
   etc.), use `[Placeholder]` markers and flag them at the top of the
   file for project lead to fill in.

---

## When complete — walkthrough should include

1. List of 10 files created with one-line summary per file
2. The 8 bash command outputs from the verification checklist
3. A list of `[Placeholder]` markers the project lead needs to fill in
   (team member names, GitHub handles, license year, etc.)
4. A list of `PLACEHOLDER_<name>.txt` files created for screenshots not
   yet captured
5. The total line counts per file so the project lead can sanity-check
   proportions
6. Confirmation that:
   - All credential rules were followed during the build, not just
     verified at the end
   - Phase reviews and internal capstone artifacts are NOT referenced
     anywhere
   - Real Supabase project IDs are NOT present anywhere
   - Bloodcare Medical Laboratory is named in plain language (private
     repo)
   - No real patient names appear anywhere

---

## After review

Once the walkthrough is reviewed and approved by the project lead, the
changes get committed to a new branch on the private GitHub repo and
opened as a pull request. The project lead then fills in the
`[Placeholder]` markers, captures the missing screenshots, and merges
to `main` for capstone defense access.

This documentation set becomes a permanent defense artifact —
reviewable by the panel during defense, archivable as portfolio
material post-graduation.
