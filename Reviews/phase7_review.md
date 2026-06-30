# Phase 7 Walkthrough Review (v2) — Role-Aware Login & Routing

> **Gate D — Completion Review (v2).** Reviewer: Claude (per `MASTER_CONTEXT.md`
> section 5).
> Subject: Revised Phase 7 Walkthrough (`1781572808007_walkthrough.md`).
> This file supersedes the prior Gate D review for Phase 7.

## Verdict: CONDITIONAL PASS

Accepting on the strength of the test log; two items still need to land before
this is fully closed. The full test log is now in place and the 12 tests all
pass with named, role-isolated scenarios. That's strong evidence and resolves
the critical blocker from the previous review. Two items from the prior review
are still pending — they are marked conditional rather than fully PASS until
they are delivered, but they are not blocking forward progress: Phase 8 planning
can begin in parallel.

---

## What the test log actually proves

Reading the 12 test names, this is a well-constructed suite:

- **Tests +0 to +3** cover the patient flow — unauthenticated -> login,
  consented/onboarded -> dashboard, consent gate, onboarding gate. The
  four-state patient routing is fully exercised.
- **Tests +4 to +6** cover each of the three staff roles routing to their
  correct home and explicitly verifying the consent/onboarding bypass.
- **Test +7** covers the admin-block — the constraint #10 security claim.
  Confirmed test exists and passes.
- **Tests +8 to +11** cover the four cross-role isolation cases specifically
  called out in the prior review: patient -> staff routes denied, staff ->
  patient routes denied, receptionist -> other staff routes denied,
  department_staff -> other departments denied.

All 12 pass. Setup and teardown complete cleanly. Supabase init confirmed in
setup. **This is the verification standard we hold to.** Credit to the agent for
delivering it.

---

## Still outstanding — two items

### Item 1: Registration evidence (constraint #11)

The previous review asked for three things. The grep on `register_screen.dart`
returned no results, which is consistent with the explanation that the actual
`signUp` call lives in `auth_provider.dart` (Flutter convention). The
walkthrough still does not include:

- The code snippet from `auth_provider.dart`'s `signUp` method showing the
  literal `'role': 'patient'`
- A SQL / Table Editor confirmation that a freshly registered user has
  `profiles.role = 'patient'`

These two pieces are still required to close constraint #11. The test suite
likely exercises this (test +1 implies a patient was created somehow), but
explicit code + database evidence is the verification chain for this specific
security constraint.

**Required:** paste the code snippet and the database confirmation.

### Item 2: Manual verification screenshots

The four manual verifications from the plan (admin-block dialog, registration
DB check, session restore, logout state purge) were committed to in the plan
but are not in the walkthrough. The automated tests cover the *logic* — but the
manual verifications cover the *user experience* of these flows on the actual
emulator. A panelist asking *"can you show me what happens when an admin tries
to log in?"* needs a screenshot or live demo, not a test log.

**Required:** add a Manual Verification section with at minimum the
**admin-block dialog screenshot** (this is the defense-critical one). The other
three (registration DB row, session restore note, logout state purge) can be
brief one-line confirmations: *"Verified — opened app on /staff/reception,
force-closed, reopened, landed on /staff/reception."*

---

## Why CONDITIONAL PASS rather than holding

Two reasons. First, the test log delivers the core security verification — the
admin block and cross-role isolation are demonstrably tested and passing.
That's the meat of Phase 7. Second, blocking Phase 8 planning behind
documentation finish-up would waste time the team does not have with defense in
3-4 weeks. The build itself is sound.

The two outstanding items are documentation, not implementation. Get them done
before final defense materials are assembled; they are not blocking Phase 8.

---

## Updated tracker for `MASTER_CONTEXT.md`

- Phase 0 — PASS
- Phase 1 — PASS
- Phase 2 — PASS
- Phase 3 — PASS
- Phase 4 — PASS
- Phase 5 — PASS
- Phase 6 — PASS
- **Phase 7 — PASS (conditional, pending: registration evidence + admin-block screenshot)**
- Phase 8 — not started
- Phase 9 — not started

---

## Status & next gate

- **Gate D for Phase 7: CONDITIONAL PASS.** The two outstanding items move to a
  "before defense" punch list, not a gate blocker.
- **Next: Gate A -> Gate B for Phase 8 (Staff mode — read-mostly).** Draft the
  Phase 8 plan using the template in `MASTER_CONTEXT.md` section 6.1.

---

## What Phase 8 needs to include

Phase 8 is **the largest scope of the staff additions** — three home screens
get filled with real data. The plan must cover, per the staff addendum guide:

1. **Reception home:** today's `patient_queue` (all departments), document
   approval/rejection UI, mark-arrived action.
2. **Department home:** department-scoped queue (filtered by
   `profiles.department`), read-only department records.
3. **Specialist home:** patient search + cross-department records detail.
4. **RLS + client-side defense-in-depth.** The plan should explicitly state
   that RLS is the canonical security boundary and the client-side role checks
   are UX, not security.
5. **Realtime subscriptions per role.** Reception sees all queue changes live;
   department staff sees their department live; specialist may not need
   Realtime (read-only).
6. **Cross-role data leakage test extended** — verify a department_staff in
   laboratory genuinely cannot pull imaging records even through manipulated
   queries.

Submit Phase 8's plan for Gate B before any Phase 8 build work begins. The
strict-Gate-B enforcement from Phase 6 still stands.

When the v3 walkthrough for Phase 7 arrives with the two outstanding items,
the reviewer will write `phase7_review_final.md` and flip the conditional PASS
to clean PASS.
