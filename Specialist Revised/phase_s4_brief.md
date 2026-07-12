# Antigravity Task — Phase S4: Specialist Workstation Consolidation + Constraint #12 Rewrite

> **Type:** finale of the specialist workstation. NOT a new feature —
> consolidation, constraint rewrite, comprehensive walkthrough, defense
> narrative.
> **Goal:** rewrite Constraint #12 to reflect the now write-capable specialist,
> document the evolution, tie S1–S3 into one coherent story.
> **Effort:** ~half day — docs only, no new code, no new tests.
> **Prerequisite:** S1 + S2 + S3 all Gate D PASS ✓.
>
> **⚠️ DO NOT generate any images/mockups/screenshots in the plan or
> walkthrough. Text descriptions only. Ralph captures real screenshots.**
>
> **⚠️ No new code. No new tests. This phase edits documentation only
> (MASTER_CONTEXT.md + a consolidation walkthrough). If you find yourself
> writing Dart, stop — that is out of scope.**
>
> **⚠️ Keep it concise. No verbose restatement, no token waste.**

---

## Context

The specialist workstation was built across three phases:

- **S1** → Specialist Dashboard + Private Patient Directory + Add Private
  Patient + Profile. Fully isolated data model (`specialist_patients`,
  `specialist_records`), RLS scoped to `specialist_id = auth.uid()`. First
  specialist WRITE (add private patient).
- **S2** → Private Record Entry (lab-structured). Reuses the D2 lab range +
  gender-aware flag engine, writing to `specialist_records`. No queue (single
  insert). Specialist WRITE (clinical results).
- **S3** → Diagnostic Analytics. Read-only longitudinal trajectory chart
  (fl_chart) per parameter + history audit table, SO-C compliant (no AI /
  no prediction). Reference band + per-point flags from stored ranges.

With S1 + S2, **the specialist became write-capable** — but only over its OWN
private, isolated roster (`specialist_patients` / `specialist_records`), never
the shared clinic tables. Constraint #12 — last rewritten in D4 to say medical
specialists remain READ-ONLY — is now stale and must be corrected.

**This is the THIRD evolution of Constraint #12** (receptionist in R5,
department staff in D4, specialist now in S4). Each evolution moved the mobile
client TOWARD the documented system design and the web platform's own behavior.
Document it honestly — it is disciplined constraint management, a defense
strength, not scope creep.

---

## What S4 delivers

### 1. Rewrite Constraint #12 in MASTER_CONTEXT.md

**Current #12 (post-D4, to be replaced):**
```
12. Mobile role capabilities follow the documented system design.
    - Receptionists have FULL write capability on mobile, mirroring the
      web platform 1:1: approve + route patients (INSERT patient_queue,
      UPDATE documents), reject documents with reason (UPDATE documents),
      and view live dashboard aggregates.
    - Department staff have FULL result-entry write capability on mobile,
      mirroring the web platform 1:1: enter clinical results (INSERT
      department_records) and complete the queue entry (UPDATE
      patient_queue → completed). Lab staff enter structured parameter
      panels with gender-aware auto-flagging; imaging/ultrasound/ECG staff
      enter free-text Findings + Impression. All writes are scoped to the
      staff member's own department by session (never a caller-supplied
      argument) and enforced again by RLS.
    - Medical specialists remain READ-ONLY on mobile (multi-term patient
      search, cross-department record timeline; no writes).
    - Admins remain BLOCKED on mobile entirely (Constraint #10).

    EVOLUTION NOTE (receptionist): Earlier iterations restricted ALL staff
    (including receptionists) to read-only on mobile as a conservative
    default. Phase R1-R5 corrected this for receptionists to match the
    paper's 1:1 web/mobile design after panel confirmation.

    EVOLUTION NOTE (department staff): The department workstation shipped
    read-only first (Phase D1: queue + records viewing), then gained
    result-entry writes (Phase D2: lab structured entry + free-text entry
    for all four departments). This staged read-then-write rollout was
    deliberate — the read foundation was proven green before any write
    path was added. Department staff writing results on mobile matches the
    documented system design and the web platform's own result-entry flow.
    This is a deliberate, staged scope realization, not scope creep.
```

**New #12 (replace the whole block with this):**
```
12. Mobile role capabilities follow the documented system design.
    - Receptionists have FULL write capability on mobile, mirroring the
      web platform 1:1: approve + route patients (INSERT patient_queue,
      UPDATE documents), reject documents with reason (UPDATE documents),
      and view live dashboard aggregates.
    - Department staff have FULL result-entry write capability on mobile,
      mirroring the web platform 1:1: enter clinical results (INSERT
      department_records) and complete the queue entry (UPDATE
      patient_queue → completed). Lab staff enter structured parameter
      panels with gender-aware auto-flagging; imaging/ultrasound/ECG staff
      enter free-text Findings + Impression. All writes are scoped to the
      staff member's own department by session (never a caller-supplied
      argument) and enforced again by RLS.
    - Medical specialists have FULL write capability on mobile over their
      OWN private, isolated patient roster, mirroring the web platform 1:1:
      create private patients (INSERT specialist_patients), enter structured
      lab results (INSERT specialist_records), and view descriptive
      longitudinal analytics. This data is stored in dedicated tables
      (specialist_patients, specialist_records) — NOT the shared clinic
      tables — and is end-to-end isolated to the owning specialist by RLS
      (specialist_id = auth.uid()). Admins, receptionists, patients, and
      OTHER specialists have no access. Specialists have NO write access to
      the shared clinic queue or department records.
    - Admins remain BLOCKED on mobile entirely (Constraint #10).

    EVOLUTION NOTE (receptionist): Earlier iterations restricted ALL staff
    (including receptionists) to read-only on mobile as a conservative
    default. Phase R1-R5 corrected this for receptionists to match the
    paper's 1:1 web/mobile design after panel confirmation.

    EVOLUTION NOTE (department staff): The department workstation shipped
    read-only first (Phase D1: queue + records viewing), then gained
    result-entry writes (Phase D2). Staged read-then-write rollout —
    deliberate scope realization, not scope creep.

    EVOLUTION NOTE (specialist): The specialist workstation was built as a
    private-practice model distinct from the shared clinic flow: a dashboard
    and private patient directory (Phase S1), structured private record entry
    reusing the department lab engine (Phase S2), and read-only descriptive
    analytics (Phase S3). The specialist gained write capability over its OWN
    isolated roster only — dedicated tables, RLS-scoped to the specialist, no
    access to shared clinic data. This mirrors the web platform's specialist
    portal 1:1 and is the third and final alignment of mobile role
    capabilities to the documented system design. Deliberate, isolated scope
    realization — not scope creep.
```

**Key diff (for the walkthrough, not the file):** medical specialists move OUT
of the read-only clause and INTO their own write-capable clause — scoped
explicitly to the isolated `specialist_patients`/`specialist_records` tables,
with an explicit statement that specialists have NO write access to shared
clinic data. Receptionist and department clauses unchanged. Admin still blocked.
Third evolution note added.

If MASTER_CONTEXT.md does not contain #12 verbatim as shown, match the actual
on-disk wording and apply the same semantic change (move specialist to
write-capable-over-isolated-tables, add the specialist evolution note). Do NOT
drop or renumber any other constraint. Confirm Constraint #13 (lab-range
duplication) is still present and untouched.

### 2. Consolidation Walkthrough (text only, concise)

Tie S1–S3 into one specialist workstation story:

- **The arc:** S1 (dashboard + private directory + add patient) → S2 (private
  lab record entry, reusing the D2 engine) → S3 (read-only analytics).
- **The private-practice model:** unlike department staff (who work the shared
  reception-fed queue), the specialist owns a private, isolated roster they
  create themselves. Dedicated tables, RLS-scoped to the specialist, invisible
  to admins and every other role. This is the "private visiting doctor" model.
- **End-to-end behavior:** specialist logs in → dashboard (own aggregates:
  total patients, flagged-7-days, active modalities, critical flagged list) →
  My Patients (private directory, derived PT- codes) → add a private patient →
  enter a lab record (structured panels, gender-aware flagging via the reused
  D2 engine, single insert, no queue) → view analytics (longitudinal chart +
  history table, SO-C compliant).
- **Isolation:** `specialist_id = auth.uid()` RLS on both tables; client never
  supplies specialist_id; a second specialist cannot see the first's data.
- **Engine reuse (Constraint #13):** S2 reuses the department lab ranges +
  gender-resolved flag calculation verbatim; the gender-resolved range is
  stored per record, so analytics bands + point flags stay audit-consistent.
- **SO-C compliance:** analytics is descriptive only — no AI inference, no
  prediction, no trend fitting; the disclaimer banner is present.
- **Verification posture:** reference the S1/S2/S3 automated suites (all green)
  and the real-device manual checks. No new tests in S4.

### 3. Defense Narrative (concise, part of the same doc)

- **Why the private-practice isolation model is a strength:** the specialist's
  data is architecturally separated (dedicated tables + RLS), demonstrating
  correct data-ownership modeling and privacy-by-design — no leakage to admins
  or other specialists.
- **Why Constraint #12 evolved three times (reception → department →
  specialist):** every change aligned mobile with the documented system design
  and the web platform, never away from it. This is rigorous constraint
  management, not scope creep. Each role's capability matches its paper-defined
  role and the web 1:1.
- **Engine reuse over duplication:** S2 reused the department lab engine rather
  than re-implementing ranges/flagging — DRY, and it keeps the two entry paths
  consistent under Constraint #13.
- **Compliance discipline:** analytics deliberately excludes AI/prediction to
  satisfy Specific Objective C, with the boundary stated in-app.

---

## What S4 does NOT do

- No new Dart code.
- No new tests (S1/S2/S3 suites + manual proof suffice — Ralph's call).
- No schema or RLS changes.
- No images/mockups in the plan or walkthrough.
- Does not touch the receptionist or department clauses' meaning beyond the
  #12 restructure. Admin stays blocked. Constraint #13 stays intact.

---

## Acceptance

- MASTER_CONTEXT.md #12 rewritten: specialist write-capable-over-isolated-tables
  clause + explicit "no shared-clinic write access" + third evolution note;
  receptionist, department, and admin clauses unchanged in meaning; Constraint
  #13 present and untouched; no other constraint dropped or renumbered.
- One concise consolidation walkthrough (text only) covering the S1→S2→S3 arc,
  the private-practice isolation model, end-to-end behavior, engine reuse, SO-C
  compliance, and verification posture.
- Concise defense narrative included.
- Report back with the final #12 text and the walkthrough for Ralph's review.
  Ralph captures any real screenshots himself. No generated images.
