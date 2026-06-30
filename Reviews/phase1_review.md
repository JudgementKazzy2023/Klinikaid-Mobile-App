# Phase 1 Review — Connectivity & Data Layer

> **Gate D — Completion Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 1 Completion Report (`walkthrough.md`, combined Phase 0 & 1 version).
> This file is authoritative review feedback for the Antigravity agent.

## Verdict: CHANGES REQUIRED

The build itself is good. But Phase 1 had two explicit **entry conditions** carried over
from `phase0_review.md` that the report does not address, and the headline RLS test —
as described — does not prove what it claims. All of this is fixable. It must be fixed
before Phase 1 can close.

---

## What was done well

- **Repository layer complete** — all 7 repositories built (`profiles`, `patients`,
  `patient_queue`, `documents`, `department_records`, `chatbot_logs`, `rag_documents`).
- **`supabase_flutter` v2 adaptation handled correctly** — nesting `localStorage` under
  `authOptions: FlutterAuthClientOptions` is the right v2 API detail.
- **RLS denial mapping is correct** — mapping `PostgrestException` code `42501` to a
  typed `DatabaseFailure` is exactly the right pattern for handling RLS denials.
- **Phase 0 `bigint` spot-check addressed** — `patient_queue.dart` and `chatbot_log.dart`
  are noted as safely parsing `bigint` ids.
- **Trigger confirmed** — the smoke test shows `handle_new_user` fires and auto-creates
  a `public.profiles` row on signup. This genuinely de-risks Phase 2.

---

## Problem 1 — The two Phase 1 entry conditions were skipped

`phase0_review.md` stated explicitly that the Phase 1 plan must open with two items.
Neither appears in the report.

### 1a. The 4-query schema check never ran
The report confirms only `profiles` and `patients` exist (via the smoke test) — 2 of 8
tables. There is still no confirmation that `patient_queue`, `documents`,
`department_records`, `system_logs`, `chatbot_logs`, and `rag_documents` exist, nor that
the `vector` extension is enabled. The repository layer references all of these tables —
if any is missing, those repos fail at runtime in later phases.

**Action:** run these four queries in the Supabase SQL Editor for project
`vxnkpcqyrxdqxpvutkmm` and paste the results:

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

### 1b. The shared-project confirmation is still open
The report again says "your live Supabase project." It is still not confirmed that
`vxnkpcqyrxdqxpvutkmm` is the **same project the web team builds against**. This is the
#1 standing risk in `MASTER_CONTEXT.md` section 9.

**Action:** obtain written confirmation from the web team that `vxnkpcqyrxdqxpvutkmm`
is the shared project.

---

## Problem 2 — The RLS smoke test has a flaw that weakens the claim

Step 4 of the smoke test reports that reading profile
`00000000-0000-0000-0000-000000000000` was "blocked by RLS" and returned
`DatabaseFailure`.

The flaw: that all-zeros profile almost certainly **does not exist**. A query for a
non-existent row returns an empty result — it does **not** return an RLS denial. RLS
denial surfaces as Postgres error code `42501`; a simply-missing row returns `[]` with
no error. So step 4, as written, cannot distinguish "RLS blocked me" from "that row was
never there." This is the same pattern flagged in `phase0_review.md`: an absence of data
being treated as proof of RLS.

A real patient-isolation test requires **two real patient accounts**:
- Sign in as Patient A.
- Attempt to read Patient B's **existing** `profiles`, `patients`, and `documents` rows.
- Confirm each attempt is denied / returns no data because of RLS — not because the row
  is absent.

**Action:** replace the all-zeros-UUID test with a two-real-patients test, re-run, and
paste the outcome.

Additional check: the report says the denial came from "RLS policies on the database
catalog." RLS is enforced on the `public` tables, not the system catalog — this is
likely loose wording, but confirm the test asserts specifically on error code `42501`,
not on any generic failure.

---

## Problem 3 — Process note: Gate B was skipped

Per `MASTER_CONTEXT.md` section 5, every phase runs Plan -> **Gate B (plan review)** ->
Build -> Gate D (completion review). Phase 1 went straight to a completion report with
no plan review. It worked out here because the scope was small — but the purpose of
Gate B is to catch issues like Problem 1 **before** the build, not after.

**Action for Phase 2 onward:** do not skip the plan. Phase 2 (auth, RA 10173 consent,
and the `profiles`/`patients` onboarding gap) contains real design decisions that must
be reviewed at Gate B before any code is written.

---

## What to do to close Phase 1

1. Run the 4-query schema check (Problem 1a); paste the results. Confirm all 8 tables,
   the `on_auth_user_created` trigger, the `vector` extension, and RLS enabled per table.
2. Obtain the web team's written confirmation that `vxnkpcqyrxdqxpvutkmm` is the shared
   project (Problem 1b).
3. Fix the RLS smoke test to use two real patient accounts and confirm Patient A cannot
   read Patient B's existing rows (Problem 2). Re-run; paste the outcome.
4. Confirm the smoke test asserts specifically on error code `42501` for RLS denial
   (Problem 2).

When all four are provided, Phase 1 flips to PASS.

---

## Status & next gate

- **Gate D for Phase 1: CHANGES REQUIRED.** Phase 0 remains PASS.
- Address the four items above to close Phase 1.
- **Next: Gate A -> Gate B for Phase 2 (Auth & patient onboarding).** Phase 2 must go
  through Gate B (plan review) properly — draft the plan using the template in
  `MASTER_CONTEXT.md` section 6.1 and submit it for review before building.

## Guidance for the Antigravity agent

1. **An absent row is not an RLS denial.** Testing isolation by reading a non-existent
   record proves nothing. A real RLS test reads another real user's real rows and
   confirms the denial. RLS denial = Postgres error code `42501`; a missing row = an
   empty result with no error.
2. **Honor the phase gates.** Every phase has a plan reviewed at Gate B before building.
   Do not jump straight to a completion report. The plan review exists to catch missing
   entry conditions before code is written.
3. **Entry conditions from a prior review are mandatory, not optional.** When a review
   states that the next phase's plan must open with specific items, those items must
   appear and be satisfied.
