# Phase 7 Plan Review — Role-Aware Login & Routing

> **Gate B — Plan Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 7 Implementation Plan (`1781572012055_implementation_plan.md`).
> This file is authoritative plan review feedback for the Antigravity agent.

## Verdict: CHANGES REQUIRED — one structural concern, plus four smaller items

The plan is mostly right. The agent correctly understood the role-based routing
concept, the admin-block requirement, the registration hard-coding, and the
four-way home routing. Three things worth calling out as good work before flagging
the issues:

- **The "Gate Bypassing for Staff" decision is correct.** Staff do not have
  `patients` rows, so the RA 10173 consent gate and the patient onboarding form
  should NOT fire for them. This is the right call and shows the agent actually
  thought about the routing logic across roles, not just patches.
- **Bidirectional route guards** are specified: patients cannot reach
  `/staff/...`, staff cannot reach patient routes, and staff cannot reach the
  wrong staff route. That's the right level of defense-in-depth.
- **The placeholder strategy** for the three staff screens (Phase 8 will fill
  them) keeps Phase 7 narrowly scoped to routing only. Good discipline.

---

## CHANGES REQUIRED — Issue 1 (structural): the route map for `patient` is wrong

The plan says: *"If `profile?.role == UserRole.patient`, enforce `hasConsented`
and `isOnboarded` checks. Redirect from staff routes (`/staff/...`) to `/`."*

But earlier in the same plan: *"`/` (for patient)"* — meaning `/` is also the
patient's home.

This collides with what `MASTER_CONTEXT.md` Section 7 specifies:

> *`patient` → `/patient` (existing dashboard from Phase 3)*

Two problems with using bare `/` for the patient home:

1. **Symmetry.** Staff routes are namespaced under `/staff/...`. If patient is
   namespaced under `/patient/...`, the route map reads as one cohesive system.
   If patient is `/` and staff is `/staff/...`, the asymmetry will leak into the
   codebase (different redirect logic, different shell route handling, different
   deep-link patterns).
2. **Session-restore ambiguity.** On session restore, the redirect logic needs
   to decide where to send the user. If patient is `/` and an unauthenticated
   user also lands on `/`, the redirect logic has to distinguish "is this user
   authenticated as a patient" vs "is this an unauthenticated visit to the root"
   — which adds a branch you don't need if everyone lives under a role-namespace.

**Required action:** confirm the patient home route is `/patient` (as specified
in `MASTER_CONTEXT.md` Section 7), and adjust the redirect spec accordingly. If
the agent strongly believes bare `/` is preferable, the plan needs to explicitly
state that and justify why it overrides the master context.

---

## CHANGES REQUIRED — Issue 2: the registration "verify and enforce" task is underspecified

The plan says: *"Verify and enforce that the register screen signUp call
hard-codes `role` to `'patient'` and exposes no role selectors in the UI."*

The Gate D review for this work needs concrete evidence — but the plan does not
say what proof the agent will produce. *Constraint #11 in `MASTER_CONTEXT.md`
is non-negotiable*: registration creates ONLY `role='patient'`. A "verified,
trust me" claim at Gate D does not meet the verification standard set in Phase 5.

**Required action:** add a sub-task to Phase 7 that produces the concrete
evidence at Gate D:

- Paste the actual code snippet from `register_screen.dart` showing the
  `auth.signUp(data: {...})` call with `'role': 'patient'` literal.
- Show the absence of any role-selector widget by grep:
  `grep -i "role" lib/features/auth/presentation/screens/register_screen.dart`
  and inspect the output.
- Test step: actually register a fresh test user from the app, then `SELECT`
  their `profiles.role` from Supabase Table Editor. The value must be
  `'patient'`.

---

## CHANGES REQUIRED — Issue 3: the admin-block path needs to be specified more carefully

The plan says: *"force sign out, redirect to `/login`, and show blocked state."*

This is correct in spirit but there are race conditions to think through:

- **Order of operations matters.** If you redirect to `/login` BEFORE the
  sign-out completes, the redirect may be intercepted by the still-authenticated
  state. The correct order:
  1. Detect `role == admin` from the fetched profile
  2. Call `auth.signOut()` and AWAIT completion
  3. Clear local auth state
  4. THEN redirect to `/login`
- **Session restore on app launch.** This is a separate code path from
  interactive login. If a user closed the app while logged in as an admin
  (somehow — they should not have been able to log in in the first place, but
  defense in depth), the session-restore handler also has to apply the
  admin block. Same logic, different entry point.
- **What about the brief window between sign-in success and the profile fetch?**
  Between `signInWithPassword()` returning success and the subsequent
  `select * from profiles where id = ...`, the user technically has an
  authenticated session. This is fine because Supabase RLS still applies — they
  can only read their own profile — but the app must NOT route them to any
  home screen during this window. Add an explicit loading state.

**Required action:** the plan should specify the order of operations and
explicitly call out the session-restore path as a second admin-block check,
not just the interactive login path.

---

## CHANGES REQUIRED — Issue 4: error-message specificity for admin block

The plan says the error message is *"Admin accounts must sign in via the web
portal."*

That is the right message. But there is a security consideration: **error
messages should not leak that the account exists**. If someone is doing
credential discovery against your app, the difference between "wrong password"
and "this account exists but is admin" tells them an admin email is real.
Better practice:

- **Interactive login attempt with correct password but admin role:** show the
  "must sign in via web portal" message. This is fine because the user already
  proved knowledge of the password.
- **Interactive login attempt with WRONG password to an admin account:** must
  show only the generic "Invalid login credentials" — same as for any other
  failed login. The admin-block check happens AFTER password verification
  succeeds.

**Required action:** confirm the admin block happens AFTER successful
authentication, not during. The flow should be: sign-in succeeds -> fetch
profile -> check role -> if admin, sign-out + show admin message. Not:
try-to-sign-in -> pre-check role.

---

## CHANGES REQUIRED — Issue 5: the test plan is light on the cross-role isolation case

The verification plan lists eight automated test cases. The seventh is:
*"Verify route guards prevent staff from accessing other roles' staff routes."*
This is correct but underspecified — the most defense-relevant case is also the
most subtle.

**Concrete test cases to add:**

- A `department_staff` user with `profiles.department = 'laboratory'` attempts
  to navigate to `/staff/department/imaging`. Must be redirected back to
  `/staff/department/laboratory`.
- A `receptionist` attempts `/staff/department/laboratory`. Must be redirected
  to `/staff/reception`.
- A `medical_specialist` attempts `/staff/reception`. Must be redirected to
  `/staff/specialist`.
- All three of the above tested via direct navigator/router calls (simulating
  deep-link bypass), not just via UI buttons (which would not be exposed
  anyway).

**Required action:** add these explicit cross-role isolation tests to
`test/phase7_role_routing_test.dart`.

---

## Two observations (not blockers)

- The "Beautiful placeholder" language for the three staff screens — fine for
  Phase 7 since they're placeholders. Just make sure "beautiful" means
  *"correctly themed in the cream + forest-green design system"*, not *"the
  agent invented a creative design"*. The Phase 8 build will replace these
  screens entirely.
- The plan does not mention updating `MASTER_CONTEXT.md`'s progress tracker on
  Phase 7 PASS. Standard governance — please include a documentation update
  sub-task that flips the Phase 7 checkbox after Gate D.

---

## What the revised plan needs

Submit a v2 of the plan addressing:

1. **Patient route is `/patient`**, not `/` (or justification for overriding
   master context).
2. **Registration verification sub-task** with the specific evidence the agent
   will produce at Gate D.
3. **Admin-block order of operations** spelled out, including the
   session-restore path.
4. **Generic error message** for failed admin authentication (do not leak admin
   existence).
5. **Cross-role isolation test cases** added explicitly to the test plan.

Once these five items are in the revised plan, Gate B will be a clean APPROVED
and Phase 7 can move to Gate C (Build).

---

## Status & next gate

- **Gate B for Phase 7: CHANGES REQUIRED.** Revise the plan and resubmit.
- **No code work begins until Gate B is APPROVED.** This is the strict Gate-B
  enforcement committed to in Phase 6.

Send the v2 plan when ready and we will close out Gate B.
