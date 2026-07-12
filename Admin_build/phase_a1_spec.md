# SPEC — Phase A1: Admin Workstation (Read Foundation)

First phase of the mobile admin workstation, mirroring the web admin portal. **Read-only foundation** — dashboard, system logs (events / chatbot audit / API cost), cross-department records view, and reception queue view. All SELECT queries; no writes. Writes (staff activate/deactivate, role edit, RAG delete) are deferred to A2/A3 pending web confirmation of admin RLS policies.

**Major architectural note — admin on mobile reverses a prior constraint.** Constraints #10 and #12 have said "admins are BLOCKED on mobile entirely" across three prior revisions (R5, D4, S4). This admin arc deliberately changes that. A1 does NOT rewrite the constraint yet — that lands in A4 (admin closeout), same pattern as D4/S4. But A1 must UNBLOCK the admin role in routing (admins currently redirect away from the app). This is the one phase that loosens a security boundary, so it is scoped to reads only and guarded hard (AAL2).

## User Review Required

> [!IMPORTANT]
> **Admin was previously blocked on mobile.** A1 unblocks the admin role and routes it to an admin shell. This is intentional (panel-approved scope change) but must be done carefully: admin routes require AAL2 (step-up MFA), and A1 grants READ access only. No admin writes in this phase.

> [!IMPORTANT]
> **Service-role operations are permanently web-only.** Staff account creation (`auth.admin.createUser`) and password-reset emails require the service-role key, which must NEVER be on a mobile client. These are excluded from the ENTIRE admin arc, not just A1. Mobile will never create accounts. (Confirmed with web team: creation is a Next.js server route, not a callable Edge Function.)

> [!IMPORTANT]
> **A1 is reads only.** Every query is a SELECT. If any surface appears to need a write, it belongs in A2/A3, not here. Do not implement activate/deactivate, role edit, or RAG delete in A1.

## Confirmed Backend
- All A1 data comes from existing shared tables the mobile app already reads elsewhere: `profiles`, `patient_queue`, `department_records`, `documents`, plus the system-log / chatbot-log / RAG tables the web admin reads.
- Admin reads are governed by RLS. Admins have broad SELECT access across the shared schema (they're the oversight role). If a specific admin SELECT policy is missing on any table, that's a web-team gap to flag — but admin read access is expected to already exist since the web admin portal performs these same reads against the same DB.

## Open Questions (do NOT block A1 — reads only)
- A2/A3 write questions (admin RLS on `profiles.status`/role, RAG delete policy, RAG upload path) are being confirmed with the web team in parallel. A1 does not depend on them.

---

## Proposed Changes

### 1. Models
Reuse existing models where possible (`Profile`, `PatientQueue`, `DepartmentRecord`, `Document`). Add only what the admin-specific reads need:

#### [NEW] lib/core/models/system_log.dart
- Maps the system-event-log table (from web "System Events"): timestamp, user (name + role), event_type, description, ip_address.

#### [NEW] lib/core/models/chatbot_log.dart
- If not already present from the chatbot feature, map the chatbot-audit row: timestamp, user, session_id, user_query, bot_response, tokens, feedback. (Reuse the existing `chatbot_log` model if one exists — check first.)

#### [NEW] lib/core/models/rag_document.dart
- If not already present, map RAG knowledge doc: title, type, total_chunks, character_count, indexed_date. (Reuse existing `rag_document` model if present — check first. A1 only READS this for the RAG list; delete/upload are A2/A3.)

### 2. Repository
#### [NEW] lib/features/admin/data/admin_repository.dart
All read methods (SELECT only). RLS governs access; admin JWT resolved from session.
- `getDashboardData()` → aggregates for the dashboard cards:
  - today's patients (count `patient_queue` for today, PHT day window via existing `phtStartOfTodayUtc()` helper)
  - pending reviews (count `documents` awaiting validation)
  - active staff (count `profiles` where role is staff and active)
  - chatbot queries today (count chatbot logs for today)
  - department workload (count today's queue per department → for the bar chart)
  - recent system events (latest N system-log rows for the event-log panel)
- `getSystemEvents({filters})` → system-log rows, with optional filter by event type / user / date range / text search (mirrors web "Event Filter Board"). Ordered newest first.
- `getChatbotAudit()` → chatbot-log rows + today's aggregates (queries, tokens, est. cost).
- `getApiCostData()` → token-consumption series for the 30-day chart + weekly cost breakdown rows.
- `getAllQueueSubmissions()` → reception queue view (all `documents`/submissions across statuses: submitted / AI-verified / staff-review / approved / rejected). Admin sees ALL, unscoped by department. Read-only.
- `getDepartmentRecords(String department)` → cross-department records view; admin can read ANY department (unlike department staff, who are session-scoped to one). Takes a department arg BECAUSE admin is intentionally cross-department — this is the one place a department arg is correct, since admin oversight spans all departments. Still RLS-governed (admin policy must permit cross-dept read).
- `getRagDocuments()` → RAG knowledge-base list (read only).

### 3. Provider
#### [NEW] lib/features/admin/presentation/providers/admin_provider.dart
- Holds dashboard aggregates, system-log list + filter state, chatbot audit, API cost data, queue submissions, selected-department records, RAG list, loading/error per section.
- Methods: `loadDashboard()`, `loadSystemEvents(filters)`, `loadChatbotAudit()`, `loadApiCost()`, `loadQueue()`, `loadDepartmentRecords(dept)`, `loadRag()`.
- Fetch-on-demand per tab (don't load everything at once — lazy per screen).
- Errors surface visibly (standing lesson: no silent catch).

### 4. Routing + shell
#### [MODIFY] lib/core/routing/app_router.dart
- **Unblock the admin role.** Currently admins are redirected away / blocked. Add admin routes under a guard chain: `authenticated → role == admin → AAL2 (step-up MFA) → allow`. AAL2 is MANDATORY for admin (highest-privilege role).
- Add `/admin/*` to the staff-path set.
- Routes (A1 subset):
  - `/admin/dashboard`
  - `/admin/staff` (READ-ONLY list in A1 — no create/edit/activate; those are A2)
  - `/admin/queue` (reception queue view, read)
  - `/admin/records` (cross-department records view, read, with a department switcher)
  - `/admin/logs` (system events / chatbot audit / API cost — tabbed)
  - `/admin/rag` (RAG list, read — no delete/upload in A1)
  - `/admin/profile` (reuse existing ProfileScreen)

#### [NEW] lib/features/admin/presentation/admin_shell.dart
- Navigation shell for admin (bottom nav or drawer — match the app's existing shell pattern; web uses a sidebar with 7 items, but mobile should use the established bottom-nav/drawer convention from the other shells). Tabs: Dashboard, Staff, Queue, Records, Logs, RAG, Profile. If 7 tabs is too many for bottom nav, use a drawer or a "More" overflow — pick the pattern consistent with the app and note the choice.

### 5. Screens (all READ-ONLY in A1)
#### [NEW] lib/features/admin/presentation/screens/admin_dashboard_screen.dart
- Stat cards: Today's Patients, Pending Reviews, Active Staff, Chatbot Queries.
- Department Workload bar chart (reuse `fl_chart` from S3 — bar chart of today's queue per department: Laboratory / Imaging / Ultrasound / ECG).
- System Event Log panel: recent admin/security actions (timestamp, user, event type, description), newest first. Label timestamps UTC+8 / PHT to match web.

#### [NEW] lib/features/admin/presentation/screens/admin_staff_screen.dart
- **Read-only** personnel list: name, email, role badge, department, status (active), — NO edit/activate/create actions in A1 (A2 adds those). Search by name/email/role.
- If showing an edit affordance now would help A2, render it DISABLED with a note; otherwise omit until A2.

#### [NEW] lib/features/admin/presentation/screens/admin_queue_screen.dart
- Reception queue view: submissions across statuses (Submitted / AI-Verified / Staff Review / Approved / Rejected) with counts. Read-only (admin observes; does not triage here). Search.

#### [NEW] lib/features/admin/presentation/screens/admin_records_screen.dart
- Cross-department records view with a department switcher (Laboratory / Imaging / Ultrasound / ECG). Reuses the D1 records rendering (grouped records, flagged badges). Admin can view ANY department. Read-only.

#### [NEW] lib/features/admin/presentation/screens/admin_logs_screen.dart
- Tabbed: **System Events** (filterable table: type / user / date / search; CSV export if trivial, else defer), **Chatbot Audit** (today's queries/tokens/cost cards + log table), **API Cost Tracker** (30-day token chart via fl_chart + weekly cost breakdown table).

#### [NEW] lib/features/admin/presentation/screens/admin_rag_screen.dart
- **Read-only** list of RAG knowledge docs (title, type, chunks, char count, indexed date). NO delete/upload in A1 (A2/A3). Search.

---

## Verification Plan

> Standing test rule (carried from S2/S3): assert user-observable correctness, not just that widgets render. Admin sees the RIGHT aggregates, the RIGHT department when switched, the RIGHT filtered logs. "It builds" is not "it works."

### Automated Tests

#### [NEW] test/phase_a1_admin_routing_test.dart
1. Admin role is UNBLOCKED and routes to `/admin/dashboard` post-login.
2. Admin routes require AAL2 → AAL1 admin session redirected to `/mfa-verify`.
3. Non-admin roles (patient, receptionist, department, specialist) are BLOCKED from `/admin/*`.
4. Admin can reach all A1 tabs.

#### [NEW] test/phase_a1_admin_dashboard_test.dart
5. Dashboard cards show correct counts from mocked data (today's patients, pending, active staff, chatbot queries).
6. Department workload bar chart renders one bar per department with correct values.
7. System event log panel lists recent events newest-first.

#### [NEW] test/phase_a1_admin_logs_test.dart
8. System Events filter by type / user / date / text narrows results correctly.
9. Chatbot audit shows today's aggregates + log rows.
10. API cost chart + weekly breakdown render from mocked series.

#### [NEW] test/phase_a1_admin_read_views_test.dart
11. Staff list renders personnel (read-only — assert NO create/edit/activate controls present in A1).
12. Queue view shows submissions across statuses with counts.
13. Records view: switching department shows THAT department's records (route/state correctness — the S2 lesson).
14. RAG list renders docs read-only (assert NO delete/upload controls in A1).

### Regression
```bash
flutter analyze
flutter test test/phase_s3_analytics_screen_test.dart   # fl_chart still fine (reused for bar/cost charts)
flutter test test/phase_d1_department_records_test.dart  # records rendering reused
flutter test
```

### Manual Verification (real device)
1. Log in as admin (AAL1) → redirected to TOTP → complete → lands on admin dashboard.
2. Dashboard: cards populate, department workload bar chart renders, event log shows recent actions.
3. Logs: filter system events; view chatbot audit; view API cost chart + weekly table.
4. Records: switch department in the switcher → records update to that department.
5. Queue: see all submissions across statuses.
6. Staff: see personnel list — confirm NO create/edit/activate buttons appear (A1 is read-only).
7. RAG: see knowledge docs — confirm NO delete/upload (A1 read-only).
8. Non-admin accounts cannot reach `/admin/*`.
9. APK grep: still zero service-role / secret keys (admin adds NO secrets to the client — this is the whole point).

---

## Out of Scope (later admin phases)
- **A2** — Staff Management writes: activate/deactivate, edit role/department (RLS-governed, pending web confirmation). Account creation + password reset stay web-only permanently.
- **A3** — RAG Manager writes: delete doc (if RLS), upload (likely web-only if server-side embedding).
- **A4** — Constraint #10/#12 rewrite (admin now partially on mobile: read + RLS-management, NOT account creation) + consolidation + defense narrative.
- No writes of ANY kind in A1.
- No service-role operations, ever.

---

## Build Rules
- SPEC locked. No scope creep. A1 is reads only — if you're writing an INSERT/UPDATE/DELETE, stop.
- Admin routes: AAL2 mandatory. Admin is the highest-privilege role; the step-up guard is non-negotiable.
- No service-role key on device, ever. APK grep must stay clean. This is the entire security premise of Class-1-only admin.
- Reuse existing models/rendering (Profile, records grouping, fl_chart) — don't duplicate.
- Cross-department read is the ONE place a department arg is correct (admin spans all depts); everywhere else stays session-scoped.
- Tests assert user-observable correctness (right counts, right department, right filtered logs), not just render.
- Atomic order: models → repo (reads) → provider → routing/shell → dashboard → logs → read views (staff/queue/records/rag) → tests.
- flutter analyze clean after each group; tests alongside impl.
- 3-strike debug loop → STOP, report.
- No real Supabase ref — placeholder. RLS governs reads.
- **No image/mockup generation. Concise walkthrough.**
- Full suite green before Gate D.
