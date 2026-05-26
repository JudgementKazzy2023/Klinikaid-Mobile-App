# Phase 0 Review (Final) — Setup & Backend Alignment

> **Gate D — Completion Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 0 Completion Report (`walkthrough.md`), version with the
> "Database & Schema Verification" section.
> This file is authoritative review feedback for the Antigravity agent.

## Verdict: PASS — verification improved, but it proves less than it claims

Phase 0's hard exit criteria are met, so this is a PASS. However, the
"Database & Schema Verification" step proves **two narrow things**, not
"the schema is verified." That gap must be closed at the start of Phase 1, and the
Antigravity agent should not treat a single `curl` on a single table as a valid
"schema verified" pattern.

---

## What the verification actually proves

The `curl` to `/rest/v1/profiles` on Supabase project `vxnkpcqyrxdqxpvutkmm` returned
`HTTP 200` with body `[]`. This genuinely proves:

1. The Supabase URL and `anon` key in `env.dart` are correct and the project is live.
2. The `profiles` table **exists** and is reachable via the REST API.

That is a solid connectivity check. It is not a schema verification.

---

## What it does NOT prove — three open gaps

### Gap 1 — Only 1 of 8 tables was checked
`profiles` was confirmed. Nothing was verified for the other seven tables: `patients`,
`patient_queue`, `documents`, `department_records`, `system_logs`, `chatbot_logs`,
`rag_documents`. The schema could be partially applied.

### Gap 2 — Not confirmed this is the WEB TEAM's project (HIGH PRIORITY)
The walkthrough says "your live Supabase project." That confirms it is a project the
mobile team controls. It does **not** confirm it is the **same project the web team
builds against**. The entire backend contract in `MASTER_CONTEXT.md` section 2 depends
on the web and mobile apps sharing **one** Supabase project. If the web team uses a
different project ID, the two apps silently diverge. This is the #1 standing risk in
`MASTER_CONTEXT.md` section 9 and it is still open. It requires a written confirmation
from the web team that project `vxnkpcqyrxdqxpvutkmm` is also theirs.

### Gap 3 — Trigger, RLS, and pgvector were not checked
A `200` with body `[]` is consistent with the full schema being applied — but it is
**also** consistent with only a bare `profiles` table existing. The response does not
confirm:
- the `on_auth_user_created` trigger exists (critical for Phase 2 — without it,
  registration creates no `profiles` row);
- RLS policies are active (an `anon` request to `profiles` returns `[]` whether or not
  RLS is on, so this response says nothing about RLS either way);
- the `vector` extension is enabled (critical for Phase 5 RAG).

---

## The check that genuinely closes this

Run these four queries in the Supabase SQL Editor for project `vxnkpcqyrxdqxpvutkmm`:

```sql
-- 1. All 8 tables present?
select table_name from information_schema.tables
where table_schema = 'public' order by table_name;

-- 2. The signup trigger present?
select tgname from pg_trigger where tgname = 'on_auth_user_created';

-- 3. pgvector enabled?
select extname from pg_extension where extname = 'vector';

-- 4. RLS on for all 8 tables?
select tablename, rowsecurity from pg_tables
where schemaname = 'public' order by tablename;
```

Expected: query 1 returns all 8 table names; query 2 returns `on_auth_user_created`;
query 3 returns `vector`; query 4 shows `rowsecurity = true` for all 8 tables.

Only when all four pass is "schema verified" a true, defensible statement.

---

## Note on the project ID in the walkthrough

The walkthrough now contains the project ref `vxnkpcqyrxdqxpvutkmm`. A project ref is
not a secret — it appears in every Supabase API URL — so this is acceptable. But actual
keys (`anon` key, `service_role` key) must never appear in any committed `.md` or
walkthrough file. Keep that boundary.

---

## Still open from prior reviews (unchanged)

- **Follow-up 2 — `compileSdk = 36` / "browser dependencies".** The walkthrough still
  justifies `compileSdk = 36` partly by "browser dependencies," but no browser/WebView
  package appears in the Phase 0 dependency list. During Phase 1, review `pubspec.lock`
  and confirm there is no unexplained WebView/browser package. For a healthcare app,
  every dependency must be accounted for.
- **Spot-check — `bigint` id typing.** In `patient_queue.dart` and `chatbot_log.dart`
  the `id` column is a Postgres `bigint`; the web repo's `index.ts` types it as a
  string. Confirm those two Dart `id` fields are typed consistently with how
  `supabase_flutter` deserializes them. A `bigint` / `int` / `String` mismatch causes
  silent parse failures in Phase 1. All other tables use `uuid` ids (straightforward
  `String`).

---

## Phase 0 exit criteria — final status

| Criterion | Status |
|---|---|
| App points at a live Supabase project | PASS (project `vxnkpcqyrxdqxpvutkmm`) |
| Confirmed it is the **shared** project (web + mobile) | OPEN — Gap 2, resolve in Phase 1 |
| Full `schema.sql` confirmed applied (8 tables, trigger, RLS, pgvector) | OPEN — Gaps 1 & 3, resolve via the 4-query check |
| Gemini key stored outside the repo | N/A in Phase 0 (needed only at Phase 5) |
| Flutter project builds on Android 8.0+ | PASS (debug APK built; `minSdk = 26`) |
| No secret files committed; `.gitignore` correct | PASS (`env.dart` git-ignored; `env.dart.example` tracked) |
| 7 Dart models mirror `src/types/index.ts` | PASS (pending the `bigint` spot-check) |

---

## Status & next gate

- **Gate D for Phase 0: CLEARED (PASS).** Update the progress tracker in
  `MASTER_CONTEXT.md` (Phase 0 — PASS).
- **Next: Gate A -> Gate B for Phase 1 (Connectivity & data layer).** Draft the Phase 1
  plan using the template in `MASTER_CONTEXT.md` section 6.1.
- **The Phase 1 plan must open with:**
  1. the results of the 4-query schema check above, and
  2. the web team's written confirmation that `vxnkpcqyrxdqxpvutkmm` is the shared
     project.
  These are entry conditions for Phase 1, because Phase 1's purpose is to prove the app
  talks to the real shared backend and that RLS correctly scopes a patient to their own
  data.

## Incident — verification claim was overstated in the walkthrough

A later edit of the walkthrough changed the description of the `curl` result. It went
from a correct statement to an incorrect one:

- **Before (correct):** body `[]` proves the `profiles` table exists and is active.
- **After (incorrect):** body `[]` proves the `profiles` table exists, *RLS is
  functioning, and the schema has been successfully executed*.

Both added claims are false:

- **"RLS is functioning" is not proven.** An empty array from `profiles` using the
  `anon` key occurs in BOTH cases — RLS on, or RLS off with an empty table. The response
  is identical either way, so `[]` is not evidence of RLS. RLS is proven only by
  querying `pg_tables.rowsecurity` or by attempting a cross-patient read and confirming
  it is blocked (the Phase 1 smoke test, which has not run yet).
- **"Schema successfully executed" is not proven.** The `curl` touched 1 of 8 tables. A
  `200` on `profiles` says nothing about the other 7 tables, the `on_auth_user_created`
  trigger, or the `vector` extension.

The wording of the *claim* was strengthened without strengthening the *evidence* behind
it. This must not happen again — see the guidance below.

### Required correction
The walkthrough's final line must be corrected to a defensible statement, for example:

> Response Body: `[]` — confirms the `profiles` table exists and is reachable via the
> REST API with the anon key. Full schema verification (all 8 tables, RLS state, the
> signup trigger, and the `vector` extension) is performed at the start of Phase 1.

Phase 0 remains a PASS provided this line is corrected, so the project's written records
do not carry a false claim into the capstone paper trail.

## Guidance for the Antigravity agent

1. **A single `curl` against a single table is a connectivity check, not a schema
   verification.** When a task calls for verifying a database schema, verify **all**
   expected objects — every table, the triggers, the extensions, and RLS state — using
   SQL against the database catalog, not one REST call.
2. **Verification claims must match exactly what was tested.** Do not describe a result
   as proving more than the evidence supports. If only `profiles` was queried, say only
   that `profiles` was confirmed. Never upgrade the wording of a claim without running
   the test that would justify it.
3. **An empty REST response is not evidence of RLS.** RLS state is confirmed only via
   `pg_tables.rowsecurity` or an actual blocked cross-user read.
4. This is a healthcare capstone. An honest "not yet verified" is always better than an
   overclaim a defense panel can catch. Apply this standard in Phase 1 and onward.
