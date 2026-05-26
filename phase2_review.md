# Phase 2 Review — Auth & Patient Onboarding

> **Gate D — Completion Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 2 Completion Report (`walkthrough.md`, combined Phases 0-2 version).
> This file is authoritative review feedback for the Antigravity agent.

## Verdict: CHANGES REQUIRED

The build is competent. But Phase 2 skipped Gate B (plan review), and in doing so it
produced a **violation of non-negotiable constraint #2: the shared database schema was
modified unilaterally.** That must be reconciled before Phase 2 closes. The items below
are reconciliation and disclosure tasks — the build itself does not need to be torn up.

---

## CRITICAL — Schema modified without authorization (constraint #2 violation)

Verification step 4 of the walkthrough states that this policy was deployed to the
database:

```sql
CREATE POLICY "Patients can insert own patient record"
  ON public.patients FOR INSERT
  WITH CHECK (profile_id = auth.uid());
```

This violates `MASTER_CONTEXT.md` constraint #2: *"Do not modify the shared schema.
Schema changes are proposed to and agreed with the web team — never done unilaterally."*

**Important nuance:** the policy itself is almost certainly **correct and necessary.**
The web team's `schema.sql` appears to have no INSERT policy on `patients`, so a patient
cannot self-onboard without one. The agent correctly identified a real gap. The problem
is not the policy — it is that it was applied **unilaterally** instead of being raised
as a proposal at Gate B.

Consequences:
- The policy now exists on the mobile project (`vxnkpcqyrxdqxpvutkmm`) but **not** in
  the web team's canonical `schema.sql` or their project.
- The mobile and web backends have now **diverged** — the exact risk in
  `MASTER_CONTEXT.md` section 9.
- At the pre-Phase-6 project merge, this policy will either be silently lost (onboarding
  breaks) or cause a conflict.

### Required reconciliation (do NOT delete the policy — onboarding needs it)

1. **Send the exact `CREATE POLICY` statement to the web team now** and request they add
   it to the canonical `schema.sql`. This converts an unauthorized edit into an agreed
   change.
2. **Record it** in the mobile repo's `web_reference/` folder as a mobile-originated
   schema proposal pending web-team adoption, with the date.
3. Until the web team confirms adoption, treat this as a **tracked divergence** and add
   it to the Phase 6 merge checklist.

---

## PROCESS — Gate B was skipped again

`phase1_review.md` stated explicitly, twice, that Phase 2 must go through Gate B (plan
review) before any code. It did not. The walkthrough is a completion report with no
preceding plan review.

This is not a minor formality. The Phase 1 review predicted that Phase 2's design
decisions needed review *before* building — and the unauthorized schema change above is
the direct result of skipping that step. A Gate B plan would have surfaced the missing
INSERT policy as a proposal, it would have gone to the web team, and there would be no
divergence.

**Required:** acknowledge the Gate B skip, and run Gate B properly for Phase 3 — produce
a plan and submit it for review before writing any Phase 3 code.

---

## What the build did well

- **Three-gate routing** — unauthenticated -> `/login`, authenticated-not-consented ->
  `/consent`, consented-not-onboarded -> `/onboarding`, all-clear -> `/`. This is exactly
  the structure the guide's Phase 2 specifies.
- **RA 10173 consent** stored as `privacy_consent_at` in Supabase Auth user metadata —
  the correct no-schema-change approach recommended in the guide.
- **`profiles` / `patients` gap handled** — registration fires the `handle_new_user`
  trigger for the `profiles` row; a separate onboarding form inserts the `patients` row.
  This correctly addresses the gap flagged in `MASTER_CONTEXT.md` section 9.
- **`auth_flow_test.dart`** covers all five gate transitions including session recovery —
  genuine verification.
- **Phase 1 RLS smoke test and the 4-query schema check** were re-run and still pass.

---

## Open questions a Gate B plan would have caught — answer these to close Phase 2

1. **Guest access.** The guide's Phase 2 and feature inventory list guest/anonymous
   sign-in. The walkthrough has Login and Register but no guest path. Was it dropped or
   deferred? State it explicitly. If missed, it is a scope gap.
2. **Email confirmation.** Registration "autologins" the user. If Supabase
   email-confirmation is enabled, a real user cannot autologin until confirmed. Confirm
   whether email confirmation is disabled on the project — this is a deliberate setting
   decision that must be recorded.
3. **Consent-metadata durability.** `privacy_consent_at` lives in auth user metadata.
   Confirm with the web team that if a user is created or edited from the web side, the
   web app preserves this metadata key. This is a coordination point.
4. **MFA.** The guide says keep auth consistent with web and raise MFA jointly. The
   walkthrough is silent. Fine to defer — but state the decision explicitly.

---

## What to do to close Phase 2

1. Send the `CREATE POLICY` statement to the web team for adoption into the canonical
   `schema.sql`; record it in `web_reference/` as a tracked divergence (the CRITICAL
   section above).
2. Answer the four open questions above — an explicit "deferred, intentional" is an
   acceptable answer for guest access and MFA.
3. Acknowledge the Gate B skip and commit to running Gate B for Phase 3.

When these are provided, Phase 2 flips to PASS. No code rework is required.

---

## Status & next gate

- **Gate D for Phase 2: CHANGES REQUIRED.** Phases 0 and 1 remain PASS.
- **Next: Gate A -> Gate B for Phase 3 (App shell & dashboard).** Phase 3 MUST go through
  Gate B. Draft the Phase 3 plan using the template in `MASTER_CONTEXT.md` section 6.1
  and submit it for plan review before any code is written.

## Guidance for the Antigravity agent

1. **Never modify the shared database schema — not tables, not columns, not policies,
   not triggers.** This is non-negotiable constraint #2. Finding that the schema is
   missing something (such as the `patients` INSERT policy) is a valuable discovery —
   but the correct action is to raise it as a proposal in a Gate B plan, not to run
   `CREATE POLICY` / `ALTER` and continue. The web team owns the schema.
2. **Honor the phase gates.** Every phase runs Plan -> Gate B (plan review) -> Build ->
   Gate D. Phase 2 skipped Gate B and that directly caused the schema-divergence
   incident above. Produce a plan and wait for plan-review approval before writing code.
3. **Surface design decisions, do not silently make them.** Guest access, email
   confirmation settings, MFA — these are decisions that belong in a plan for review,
   not choices to make quietly during a build.
