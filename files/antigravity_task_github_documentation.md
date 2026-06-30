# Antigravity Task — Documenting KlinikAid Mobile for Private GitHub Repo

> **Task type:** documentation only — no code changes, no business logic touched.
> **Goal:** produce a polished documentation set for a **private** GitHub repository
> that combines a portfolio-grade README, technical setup docs, and the capstone
> development story.

---

## Context for this task

The KlinikAid Mobile App is the patient-and-staff-facing Android client (Flutter)
for a clinic management system shared with a separate web team. All nine
development phases (0-9) are complete and PASSed. The build, security pass,
and ISO 25010 evaluation are documented across internal review files.

This task creates the **user-facing documentation** that will live in the
GitHub repository. It does NOT include the internal phase-review files —
those stay out of the repo per the project lead's decision.

---

## What to produce

A documentation set inside the repository's root and a `docs/` folder:

```
KlinikAid-Mobile/
├── README.md                          ← top-level, polished, portfolio-grade
├── LICENSE                            ← MIT or similar (confirm with project lead)
├── CONTRIBUTING.md                    ← brief, since the repo is private
├── .gitignore                         ← ensure env.dart, *.jks, .env are excluded
└── docs/
    ├── 01-overview.md                 ← what this app is, who it's for
    ├── 02-architecture.md             ← how the pieces fit together
    ├── 03-setup.md                    ← dev environment setup, run instructions
    ├── 04-development-story.md        ← the capstone journey
    ├── 05-features.md                 ← per-role feature inventory
    ├── 06-security.md                 ← RLS, role boundaries, on-device OCR
    └── 07-deployment.md               ← release build and distribution
```

Detail per file below. The agent should follow this structure exactly unless
flagging a substantive concern.

---

## File specifications

### `README.md` (root)

The README is the first thing anyone sees. It needs to communicate value in
the first 30 seconds. Structure:

1. **Project title and one-sentence description.** Example:
   *"KlinikAid Mobile — a patient-and-staff-facing Android app for Bloodcare
   Medical Laboratory, built in Flutter with a Supabase backend."*

2. **A status badge row.** Build status, Flutter version, Android minSdk,
   license. Use shields.io.

3. **Screenshots row.** Three screenshots side-by-side: Login, Dashboard,
   Chatbot. Reference files in `docs/assets/screenshots/`. These already exist
   from Phase 7 and Phase 8; copy them in.

4. **Quick start (5 lines max).** Just: clone, install, configure env, run.
   The full setup goes in `docs/03-setup.md`.

5. **What this app does.** Two paragraphs.

6. **Tech stack.** A small table (Flutter, Dart, Supabase, Gemini API, Google
   ML Kit OCR, Drift SQLite, GoRouter, Provider).

7. **Roles supported.** A brief table:
   | Role | Mobile access |
   |---|---|
   | Patient | Full feature set: chatbot, OCR submissions, records, queue |
   | Receptionist | Queue + document review |
   | Department Staff | Department-scoped queue + records |
   | Medical Specialist | Patient search + cross-department timeline |
   | Admin | **Blocked on mobile — web portal only** (security boundary) |

8. **Documentation index.** Links to all files in `docs/`.

9. **Acknowledgments.** Capstone team, FEU Diliman, web team
   (Setsuna-guwah/KlinikAid), client (Bloodcare Medical Laboratory).

10. **License.**

Keep the README under 200 lines. If something needs more space, link out to a
file in `docs/`.

### `LICENSE`

Create an MIT License file with the capstone year and team name. Confirm the
license choice with the project lead before committing.

### `CONTRIBUTING.md`

Brief — under 30 lines. Since the repo is private:

- How to set up the dev environment (link to `docs/03-setup.md`)
- Branching strategy (recommend simple feature branches → main)
- Commit message convention (recommend `type(scope): description` — already
  in user's workflow preferences)
- Code style: run `flutter analyze` clean before committing
- Test policy: new features need accompanying tests in `test/`

### `.gitignore`

Must include at minimum:

```
# Flutter / Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
.flutter-versions
pubspec.lock  # debatable; include if using puro

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
lib/core/config/env.dart            # contains Supabase URL + anon key
supabase/.env                       # contains GEMINI_API_KEY
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

If `env.dart` is currently committed anywhere in the repo's history, that
needs to be remediated separately — flag it but do not attempt history
rewriting in this task.

### `docs/01-overview.md`

What KlinikAid is, in user-facing language:

- The clinic problem being solved (paper-based intake at a small Philippine
  medical laboratory).
- What the mobile app delivers (patient self-service, scoped staff portals).
- What the web app delivers (referenced, not detailed — that's the web team's
  domain).
- The shared-backend architecture (one Supabase project, two clients, shared
  schema and RLS).
- Out-of-scope items (no medical diagnosis, no analytics on patient side, no
  admin role on mobile).

About 150-250 lines. No code blocks.

### `docs/02-architecture.md`

How the pieces fit together. Include:

1. **System diagram (text-based or ASCII).** Show: Android device, Supabase
   project, Gemini Edge Function, Google ML Kit (on-device), web portal
   (referenced).

2. **Folder structure tree.** Show the `lib/` layout — features, core, app —
   with one-line descriptions per folder.

3. **State management.** Brief: Provider pattern; per-feature providers; auth
   state is the root.

4. **Routing.** GoRouter with role-aware redirection; dispatcher at `/`.

5. **Local caching.** Drift (SQLite) for offline-first patient data.

6. **Network layer.** `supabase_flutter` SDK; no manual HTTP for backend
   operations.

7. **The Edge Function.** What it does (Gemini RAG over `rag_documents`), why
   it exists (keep the Gemini key server-side per Constraint #1).

About 200-300 lines.

### `docs/03-setup.md`

Step-by-step developer onboarding. This is the most important practical
document — a new team member should be able to run the app in 30 minutes
using only this file.

1. **Prerequisites.** Specific versions:
   - Flutter (channel stable, version from `pubspec.yaml`)
   - Dart (matched to Flutter)
   - Android Studio (current)
   - JDK 17
   - puro (if used)

2. **Clone the repo.**

3. **Configure environment.**
   - Copy `lib/core/config/env.dart.example` to `lib/core/config/env.dart`
   - Set `supabaseUrl` and `supabaseAnonKey` from the project's Supabase
     dashboard
   - Note: GEMINI_API_KEY is NEVER set in the app; it lives only on the
     Supabase Edge Function

4. **Install dependencies.** `flutter pub get`.

5. **Set up the emulator.**
   - Android Studio → Device Manager → create AVD (Pixel 6, API 34
     recommended for development)
   - Uncheck "Launch in tool window" in Settings → Tools → Emulator (so the
     emulator opens as a separate window)

6. **Run the app.**
   - `flutter run -d <device_id>`
   - Get device_id from `flutter devices`

7. **Run tests.**
   - `flutter test` (all 38 tests)
   - Individual test files: `flutter test test/<filename>`

8. **Common issues and fixes.** Include the real issues encountered during
   development:
   - "Emulator window not visible" → check "Running Devices" panel
   - "Lost connection to device" → app still works; reconnect with
     `flutter run`
   - "DNS resolution failure" → Supabase project is paused; resume from
     dashboard
   - "FunctionException 404" → Edge Function not deployed to current project
   - "Tests fail with 403 StorageException" → check Supabase Storage RLS
     policies are applied

About 250-400 lines.

### `docs/04-development-story.md`

The capstone narrative. This is the portfolio piece — what makes the project
interesting to read. Structure:

1. **The problem.** Bloodcare Medical Laboratory's paper-based intake.

2. **The team.** Four-member capstone team; mobile was one developer; web
   was three developers on a separate repo.

3. **The four-gate phase protocol.** Brief: Plan → Gate B review → Build →
   Gate D review. Why this discipline mattered.

4. **The nine phases.** One paragraph each. Cover:
   - Phase 0: Setup and backend alignment
   - Phase 1: Connectivity and data layer
   - Phase 2: Auth, RA 10173 consent, patient onboarding (mention the
     `profiles` vs `patients` schema gap)
   - Phase 3: App shell and patient dashboard
   - Phase 4: Edge OCR with Google ML Kit (on-device privacy)
   - Phase 5: RAG chatbot via Supabase Edge Function (Gemini)
   - Phase 6: Records, queue, status with Realtime
   - Phase 7: Role-aware login with admin-block
   - Phase 8: Staff mode (Receptionist, Department, Specialist — read-mostly)
   - Phase 9: Testing, hardening, release

5. **Architectural decisions worth recording.**
   - Why Flutter
   - Why Supabase (one backend, two clients)
   - Why on-device OCR (RA 10173 compliance via privacy-first architecture)
   - Why admin is blocked on mobile (security boundary)
   - Why staff scope is read-mostly (heavy data entry stays on web)

6. **ISO 25010 evaluation results.** Summarize the four load scenarios with
   honest framing (especially Scenario 1's graceful-degradation finding).
   Reference the real-device performance numbers (Android 8.0 / 4GB).

7. **Defense-in-depth pattern.** The constraint #11 (registration hard-codes
   `role='patient'` AND the database trigger defaults unknown roles to
   patient) — this is the strongest architecture story.

8. **What we'd do differently.** Be honest. Examples:
   - Sooner coordination with the web team on shared-project ownership.
   - Earlier alignment of mobile and web design systems (we migrated themes
     mid-project at Phase 6/7).
   - More aggressive test coverage of offline paths.

About 600-900 lines. This is the longest doc — it tells the story.

### `docs/05-features.md`

Per-role feature inventory. Use tables. For each role, list every screen,
every action permitted, and explicitly call out what is NOT permitted.

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
- Self-register (`role='patient'` hard-coded)
- Accept RA 10173 privacy consent
- Submit clinical onboarding details
- Submit documents via camera or gallery (OCR runs on-device)
- Ask the chatbot administrative questions
- View own records, queue, document statuses
- Update own profile

### NOT permitted
- View other patients' data (RLS-enforced)
- Set their own role to anything other than patient
- Self-promote to a staff role
```

Same pattern for Receptionist, Department Staff, Medical Specialist. About
300-400 lines total.

### `docs/06-security.md`

Security architecture as a defensible document. This becomes a defense-prep
artifact too. Cover:

1. **Constraint inventory.** All 12 constraints from `MASTER_CONTEXT.md`
   Section 4, in plain language with explanation of how each is enforced.

2. **RLS as canonical boundary.** Explain: client-side checks are UX, the
   database is the source of truth.

3. **Defense-in-depth examples.**
   - Registration role hard-coding (client + database trigger fallback)
   - Admin block (login screen + session-restore path)
   - Department isolation (route guard + client filter + RLS)
   - Cross-tenant patient data (RLS-only)

4. **What's tested.** Reference the test files (no need to paste output, just
   list which tests prove which constraint).

5. **APK security pass.** Brief description of the decompile + grep process
   and why no Gemini key is shippable.

6. **RA 10173 compliance.** Privacy consent flow, on-device OCR,
   `accepted_privacy_at` storage.

About 300-400 lines.

### `docs/07-deployment.md`

How to build and distribute the release APK:

1. **Pre-build checks.** `flutter analyze` clean; `flutter test` all green.

2. **Build the release APK.** `flutter build apk --release`. Output path
   note.

3. **Signing.** Debug keystore for academic deployment; production keystore
   path for clinic deployment. Reference, do not commit the keys.

4. **Versioning.** `pubspec.yaml` version stamp.

5. **Distribution.** Sideload via USB; or upload to a private folder for
   capstone defense.

6. **APK security pass.** Brief recap of the decompile process.

About 100-200 lines.

---

## Important constraints for this task

1. **No secrets in any documentation.** No real Supabase project URLs in
   text (use placeholders like `<your-project-id>.supabase.co`). No
   `GEMINI_API_KEY` even partially shown. No JWT examples even truncated.

2. **No references to internal review files.** The `phase[N]_review.md`,
   `MASTER_CONTEXT.md`, `klinikaid_mobile_guide*.md`, and walkthroughs are
   internal capstone artifacts. **They stay out of the GitHub repo.** Do not
   link to them, do not paste from them. If specific content from those
   files is needed, restate it in user-facing language.

3. **Real clinic name is acceptable.** The repo is private. Bloodcare Medical
   Laboratory can be named. But:
   - No real patient names anywhere (use "Patient A" / placeholder names).
   - No real staff emails or accounts.

4. **Screenshot copies, not links.** Copy the screenshot files into
   `docs/assets/screenshots/` and reference them with relative paths. The
   existing screenshots from the punch list are: `admin_block_dialog.png`,
   `consent_back_fill.png`, `receptionist_dashboard.png`,
   `department_dashboard.png`, `specialist_dashboard.png`. Add the Login,
   Dashboard, and Chatbot screenshots from the theme migration too.

5. **No fabricated content.** If the agent doesn't know something specific
   (e.g., the team members' GitHub handles), use a placeholder like
   `[Team Member Name]` and flag it in a comment block at the top of the
   file for the project lead to fill in.

---

## Verification when this is done

- [ ] All 10 files exist at the paths above (root + LICENSE + CONTRIBUTING +
      .gitignore + 7 files in docs/).
- [ ] The `docs/assets/screenshots/` folder contains all referenced images.
- [ ] `grep -ri "AIzaSy" .` returns no matches.
- [ ] `grep -ri "service_role" .` returns no matches in committed files.
- [ ] `grep -r "vxnkpcqyrxdqxpvutkmm\|onzeyejlfydvvbkejvwf" docs/` returns
      no matches (use placeholder project IDs instead).
- [ ] `grep -r "phase[0-9]_review\|MASTER_CONTEXT" docs/ README.md` returns
      no matches (internal-only references should be absent).
- [ ] `flutter analyze` is still clean after any changes (in case the agent
      modified anything by accident).
- [ ] No test files were modified.

---

## When complete

Report back with:

- A walkthrough.md following the standard format
- Confirmation that the verification checklist above passes
- A list of any `[Placeholder]` markers the project lead needs to fill in
  (team names, GitHub handles, license year, etc.)
- The total line counts per file so the project lead can sanity-check
  proportions

After review, the project lead will commit the changes to a new branch on
the private GitHub repo and open a pull request.
