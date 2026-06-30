# Phase 8 Plan Review — Staff Mode (Read-Mostly)

> **Gate B — Plan Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 8 Implementation Plan (`1781574020338_implementation_plan.md`).
> This file is authoritative plan review feedback for the Antigravity agent.

## Verdict: CHANGES REQUIRED — five items

The plan has the right shape — three role-specific providers + screens, a shared
repository, Realtime subscriptions, and the consent-storage migration folded in
as a clean side task. But five things must be tightened before this is ready for
build. None require a rewrite; they need additions.

A few things worth calling out as good work before flagging the issues:

- **The `StaffQueueRepository` as a shared layer** is the right architectural
  choice. It centralizes the SQL/RPC and lets the three role providers each
  apply their own scope on top.
- **Consent-storage migration folded into Phase 8** — closes one of the standing
  risks from `MASTER_CONTEXT.md` section 9 (Phase 4 `accepted_privacy_at`
  alignment). Good use of overlap.
- **The open question on rejection-reason UX** was raised proactively rather
  than guessed at. The proposed chip + custom-field UX is reasonable; approved.
- **Department-scoped Realtime filter** (`department=eq.<dept>`) is specified —
  this is the right approach for Realtime + RLS defense-in-depth.

Now the issues.

---

## CHANGES REQUIRED — Issue 1 (structural): plan is silent on the canonical security boundary

`MASTER_CONTEXT.md` Section 4, constraint #9 states: *"RLS is the security
boundary."* And the Phase 7 review confirmed this principle in the
defense-in-depth pattern: client-side checks are UX; the database is the source
of truth.

The Phase 8 plan does not state this. The `StaffQueueRepository` methods return
data, but the plan does not explicitly acknowledge that **RLS in Supabase
filters those queries server-side** and the repository simply trusts what
returns. Without this stated, a reader could think the client-side `department`
parameter in `getQueueForToday({String? department})` is *enforcing* the scope —
which it is not. The database is.

**Required action:** add a section to the plan titled "Security architecture"
stating:

1. RLS in `schema.sql` is the canonical security boundary.
2. Client-side filters (e.g. `.eq('department', dept)` in queries) are UX/perf
   filters, not security.
3. Client-side role checks are UX, not security.
4. The cross-role data-leakage test (Issue 5 below) verifies this — a
   `department_staff` in laboratory who tries to bypass the client filter and
   query for imaging records gets zero rows back from the database, not because
   the client refused but because RLS denied.

This is the language the agent will need for the defense; it must live in the
plan so the build reflects it.

---

## CHANGES REQUIRED — Issue 2: the consent-storage migration needs a precise read-priority rule

The plan says:
> *"If their consent was recorded in metadata, the app will continue to
> recognize them as consented during migration."*

This is the right intent but the rule is ambiguous. Two questions need answers:

1. **What is the read priority?** When a patient logs in, does the app check
   `profiles.accepted_privacy_at` first and fall back to the user metadata
   `privacy_consent_at` if null, or the other way around?
2. **Is there a back-fill?** If a user's consent exists in metadata but
   `profiles.accepted_privacy_at` is still null, does the app *also* write the
   metadata's timestamp into `profiles.accepted_privacy_at` on the next login —
   so future reads only need to check `profiles`?

The cleanest rule (recommended):
- **On every patient session**, if `profiles.accepted_privacy_at` IS NULL **and**
  the user metadata has `privacy_consent_at`, copy the metadata timestamp into
  `profiles.accepted_privacy_at` (one-time back-fill).
- **From then on**, `profiles.accepted_privacy_at` is the only consent source.
- After back-fill is verified, remove the metadata-read branch entirely (Phase
  9 cleanup).

**Required action:** specify the read priority and whether a back-fill occurs.
Without this, existing test users from Phases 2-6 may get bounced back through
the consent gate on next login, even though they accepted previously.

---

## CHANGES REQUIRED — Issue 3: state-change actions need the same verification chain as constraint #11

Phase 7 set the verification standard for security claims: code snippet +
automated test + database confirmation. Phase 8 introduces **four new state-change
actions** from mobile:

1. Receptionist marks queue entry arrived (`patient_queue.status` → `in_progress`)
2. Receptionist approves a document (`documents.status` → `approved`)
3. Receptionist rejects a document with reason (`documents.status` → `rejected`,
   `rejection_reason` set)
4. Department staff transitions queue (`patient_queue.status` →
   `in_progress` / `completed`)

Each of these needs the verification chain. The plan's automated test section
mentions *"status switching, document updates"* but doesn't specify what to
prove or which database rows to read back.

**Required action:** for each of the four state-change actions, the plan must
specify:

- Which RLS policy permits the action (cite the policy name from `schema.sql`).
- Which test in `phase8_staff_reception_test.dart` /
  `phase8_staff_department_test.dart` exercises it.
- What database confirmation will be presented at Gate D (e.g., *"SELECT status,
  rejection_reason FROM documents WHERE id = ... shows status='rejected',
  rejection_reason='Blurry Image'"*).

This is non-negotiable — staff state changes touch tables the patient also
reads, so the proof matters.

---

## CHANGES REQUIRED — Issue 4: department_staff filter must use `profiles.department`, not client input

The plan says `getQueueForToday({String? department})`. This is fine as a
repository signature, but the **department value must come from
`profiles.department` at the auth layer**, not from a UI input that the staff
member could change.

Without this guard, a department_staff in laboratory could (in theory) call the
repository with `department: 'imaging'` and get imaging queue rows. RLS would
deny — but the client-side filter would have sent the wrong department to the
server. This is the gap defense-in-depth closes.

**Required action:** the plan must state that:

- The department_provider reads `profiles.department` from the auth state at
  initialization.
- The repository call uses that value, not any UI-derived value.
- No setter or UI control on the department screen allows changing the
  department parameter.

Combined with Phase 7's route guard (department_staff cannot navigate to
`/staff/department/imaging` if they're in laboratory), this is the second
defense layer. RLS is the third.

---

## CHANGES REQUIRED — Issue 5: the cross-role data-leakage test must be extended

The plan mentions: *"Verifies department queue isolation and record views (e.g.
imaging cannot view laboratory)."* This is the right test category but the plan
needs to be more explicit about what counts as proof.

**The defense-critical test:** simulate a department_staff in laboratory who
**bypasses the client-side filter** (e.g., directly calls
`StaffQueueRepository.getQueueForToday(department: 'imaging')` from a unit
test). The expected result: **zero rows returned**, because RLS denies the
query at the database. This proves that even if the client is compromised, the
database refuses.

Same pattern for documents and department_records: a laboratory user querying
imaging's `department_records` directly via Supabase client returns zero rows.

**Required action:** add to `phase8_staff_department_test.dart`:

- Test: "Department staff in laboratory cannot read imaging queue rows even
  with explicit imaging filter (RLS denies)."
- Test: "Department staff in laboratory cannot read imaging department_records
  rows even with explicit patient_id."

These are the tests a panelist will care about. *"What stops a malicious staff
member from seeing other departments?"* gets the answer: *"RLS in the database
— and here's the test that proves it."*

---

## Two observations (not blockers)

### Observation 1 — file path typo in plan

The path for `department_home_screen.dart` in the plan reads
`file:///c:/Users/Ralph%20Mobile%20app/lib/...` — missing the `Downloads/Klinikaid`
segment. Almost certainly a copy-paste artifact; the actual file path will be
correct in the build. Just noting it.

### Observation 2 — specialist screen lacks Realtime, intentionally

The plan doesn't mention Realtime for the specialist provider. This is correct
(per the staff addendum guide: *"specialist may not need Realtime — read-only"*),
but it would be worth one sentence in the plan saying *"Specialist screen does
NOT subscribe to Realtime since this role is read-only and historical-data
focused. Refresh on screen open is sufficient."* Otherwise a reader might
think it was forgotten.

---

## What the revised plan needs

Submit a v2 of the plan addressing:

1. **Security architecture section** stating RLS is canonical, client checks
   are UX/defense-in-depth.
2. **Consent-storage migration read priority** and back-fill behavior spelled
   out.
3. **Verification chain for each of the four state-change actions** — RLS
   policy citation, test reference, database confirmation method.
4. **Department filter sourced from `profiles.department`**, not UI input.
5. **Cross-role data-leakage tests** that simulate client bypass and verify
   RLS denial.
6. (Minor) one sentence acknowledging specialist screen's intentional lack of
   Realtime.

Once these are in the revised plan, Gate B will be APPROVED and Phase 8 moves
to Gate C (Build).

---

## Answer to the agent's open question

The proposed UX for document rejection — slide-up dialog with pre-defined
rejection-reason chips ("Blurry Image", "Incorrect Document Type", "Missing
Signature") plus a custom text field — is **approved**. Two small refinements:

- The custom text field should have a 200-character limit (matches typical
  Supabase text field constraints and prevents abuse).
- If a chip is tapped, that chip's label becomes the `rejection_reason`
  written to the database — exact text, no transformation. The patient sees
  the same string in their Document Status callout, so consistency matters.

---

## Status & next gate

- **Gate B for Phase 8: CHANGES REQUIRED.** Revise the plan and resubmit.
- **No code work begins until Gate B is APPROVED.** This is the strict
  Gate-B enforcement committed to in Phase 6 and reaffirmed in Phase 7.

Send the v2 plan when ready and we will close out Gate B.
