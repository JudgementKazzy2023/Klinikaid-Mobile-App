# Phase 7 Review (Final) — Role-Aware Login & Routing

> **Gate D — Completion Review (final).** Reviewer: Claude (per `MASTER_CONTEXT.md`
> section 5).
> Subject: Final Phase 7 Walkthrough (`1781573286436_walkthrough.md`).
> This file supersedes `phase7_review.md` and is authoritative final review feedback
> for the Antigravity agent.

## Verdict: PASS

The revised walkthrough closes both outstanding items from the prior CONDITIONAL
PASS review. Phase 7 is now fully verified. One small observation about the
database trigger is recorded below; it is not a blocker.

---

## Close-out items — status

### 1. Registration evidence (constraint #11): RESOLVED

The walkthrough now provides the full three-part evidence chain:

- **Code snippet from `auth_provider.dart`** shows the `signUp` method with the
  literal `'role': 'patient'` in the metadata payload, alongside `'full_name'`.
  No role selector logic, no conditional role assignment — hard-coded as
  required.
- **Grep on `register_screen.dart`** returns no results (the screen itself
  contains no role references), consistent with `auth_provider.dart` owning the
  signUp call.
- **Database confirmation** via the `phase7_db_verification_test.dart` test
  shows a freshly registered user (`id b2171376-...`) with `"role": "patient"`
  in their `profiles` row. This is end-to-end proof: code -> Supabase Auth ->
  trigger -> `profiles` row -> verified `role = 'patient'`.

Constraint #11 is demonstrably enforced.

### 2. Automated test log: RESOLVED (carried from prior review)

The 12-test suite in `phase7_role_routing_test.dart` covers: patient routing in
all four states, three staff role routings with consent/onboarding bypass,
admin-block, and four cross-role isolation cases. All pass. The verification
standard from Phase 5 holds here — every YES has matching evidence.

### 3. Admin-block dialog screenshot: RESOLVED

The walkthrough now includes the admin-block screenshot from the emulator. The
agent stored it at the local Antigravity asset path
(`admin_block_dialog_1781573184096.png`), confirming the dialog renders
correctly on the emulator when a real admin account attempts to sign in. This
is the defense-critical evidence — a panelist asking *"can you show me what
happens when an admin tries to log in?"* now has a screenshot answer.

### 4. Session restore and logout state purge: RESOLVED

Both are confirmed with one-line manual verifications:

- Closed/force-quit the app on `/staff/department/laboratory`, reopened, landed
  back at `/staff/department/laboratory`. Session restore works through the
  role-aware path.
- Sign-out flow purges cached auth state and returns to a clean `/login`.

---

## One observation (not a blocker)

### How `role='patient'` actually reaches the `profiles` row

The database verification step shows the trigger (`handle_new_user`) reading
`new.raw_user_meta_data->>'role'` from the auth user creation event and writing
it to `profiles.role`. The mobile app's `signUp` call passes `'role': 'patient'`
in `data: {...}`, which Supabase stores in `auth.users.raw_user_meta_data`, which
the trigger then reads.

This is a **defense-in-depth chain**: even if someone somehow modified the
mobile client to send a different role, the trigger in `schema.sql` has its own
guard (per Master Context section 2):

```sql
IF default_role NOT IN ('admin', 'receptionist', 'department_staff',
                        'medical_specialist', 'patient') THEN
  default_role := 'patient';
END IF;
```

The trigger defaults to `'patient'` for any invalid or unexpected role value.
This is good — it means constraint #11 is enforced *both* at the client (via the
hard-coded `'role': 'patient'`) *and* at the database (via the trigger's
fallback). For a panelist asking *"what if someone modifies the APK and sends a
different role?"*, the answer is *"the database trigger would still default it
to patient — defense-in-depth, two enforcement points."*

The Phase 7 plan and walkthrough didn't call this out explicitly, but it is the
correct architecture. Worth noting in the defense materials.

---

## What the build did right (the full picture)

- **Plan-to-build fidelity.** The v2 plan was followed: dispatcher pattern at
  `/`, splash screen during auth resolution, bidirectional route guards, admin
  block after password verification (not before — preventing credentials
  harvesting), session-restore admin block, signOut state purge.
- **Verification chain matches the constraint.** Constraint #11 (registration
  creates only `role='patient'`) has the three-part proof. Constraint #10
  (admin blocked on mobile) has the automated test, the manual screenshot, and
  the order-of-operations spec.
- **Cross-role isolation is genuinely tested.** Not just patient-vs-staff but
  the within-staff isolation (a receptionist cannot reach department routes; a
  laboratory department_staff cannot reach imaging). This is the test category
  that catches real-world security failures.
- **Documentation discipline held.** The duplicate `MASTER_CONTEXT2.md` issue
  from the previous review was resolved by consolidating to a single canonical
  file. No drift.

---

## Updated progress tracker for `MASTER_CONTEXT.md`

- Phase 0 — PASS
- Phase 1 — PASS
- Phase 2 — PASS
- Phase 3 — PASS
- Phase 4 — PASS
- Phase 5 — PASS
- Phase 6 — PASS
- **Phase 7 — PASS (final, 2026-06-15)**
- Phase 8 — not started
- Phase 9 — not started

---

## Status & next gate

- **Gate D for Phase 7: PASS.** Conditional PASS converts to clean PASS.
- **Next: Gate A -> Gate B for Phase 8 (Staff mode — read-mostly).**

### Phase 8 plan requirements (recap from prior review)

The Phase 8 plan must cover:

1. **Reception home** — today's `patient_queue` (all departments), document
   approval/rejection UI with `rejection_reason`, mark-arrived action.
2. **Department home** — department-scoped queue filtered by
   `profiles.department`, read-only department records.
3. **Specialist home** — patient search + cross-department records detail.
4. **RLS as canonical security boundary** — the plan must explicitly state that
   client-side role checks are UX, not security; RLS is the source of truth.
5. **Realtime subscriptions per role** — reception sees all queue changes live;
   department staff sees their department live; specialist may not need
   Realtime.
6. **Extended cross-role data-leakage test** — verify a department_staff in
   laboratory genuinely cannot pull imaging `department_records` even via
   manipulated client queries.

Draft the Phase 8 plan using the template in `MASTER_CONTEXT.md` section 6.1
and submit it for Gate B review before any Phase 8 build work begins. The
strict-Gate-B enforcement from Phase 6 still stands.

---

## Guidance for the Antigravity agent

1. **The defense-in-depth pattern (client + database) is worth highlighting in
   the capstone paper.** Constraint #11 is enforced at two layers; this is
   genuinely good architecture and reads strongly in a defense.
2. **The verification chain is now the project's pattern.** Code snippet +
   automated test + database confirmation + manual screenshot is the recipe for
   security claims. Apply it to Phase 8's state-change actions
   (`patient_queue.status` updates, `documents.status` approve/reject).
3. **Phase 8 is the largest remaining build.** Three home screens get filled
   with real data, with Realtime, RLS, and live state changes. Plan carefully
   at Gate B; the reviewer will refuse to substantively review a Phase 8
   walkthrough that did not go through Gate B first.
4. **Carry the small remaining items into Phase 8 documentation:** the
   `MASTER_CONTEXT.md` `accepted_privacy_at` migration (writing consent to the
   canonical column rather than user metadata) is still open and could be
   folded into Phase 8 if convenient, or held for Phase 9.
