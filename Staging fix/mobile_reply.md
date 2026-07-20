# Reply to Mobile — RBAC flip + your 5 points

Ran the checks on staging-copy. All five answered below from evidence, not theory. One real fix needed on your side (point 1's root) — spec attached separately (`mobile_provisioning_fix_spec.md`).

---

**1. role_id on direct signups — FIXED on staging-copy, but you have a real provisioning bug underneath it.**

Two separate things were tangled here:

- **role_id itself:** the `handle_new_user` trigger DOES cover direct SDK signups (it's `AFTER INSERT ON auth.users`, fires for web + mobile alike), and migration_17 patched it to set `role_id`. BUT the trigger swallows exceptions (`WHEN OTHERS THEN RETURN new`), so a failed role_id lookup was silently leaving `role_id` NULL. We hardened it (migration_18 on staging-copy): explicit patient-role fallback, loud `PROFILE_PROVISIONING_FAILED` log + raise if unresolvable, and backfilled all existing NULLs. Staging-copy now has zero NULL role_id rows. So your "null role_id = locked out post-flip" concern was correct, and it's closed.

- **The bigger issue it exposed:** your test account (`ralagarcia014`) had NULL role_id AND no `patients` row. The missing patients row is the actual cause of the infinite-loading you saw — patient dashboard fetches the patients record, gets nothing, hangs. Root cause: mobile registration inserts the `patients` row from the anon/authenticated client, and there is no patient self-insert RLS policy on `patients` (there never was, pre-flip too), so the insert is denied and the account orphans. This is the fix in the attached spec. Not caused by the RBAC flip — pre-existing — but it blocks your patient testing, so it's the priority.

**2. Edge Functions authorizing on role — inventory done. Two of yours read role text.**

Pulled all deployed function sources. What authorizes on `profiles.role` text (and must convert before role text is ever retired):
- `extract-lab-values` — gates on `role === 'admin' || (role === 'department_staff' && dept === 'laboratory')`. Role-text dependent.
- `request-password-reset` — calls `get_role_for_email` (patient-only reset). Role-text dependent via that RPC.

Safe / no role-text dependency: `chat` (deployed as `hyper-function`), `assess-document-quality`, `send-verification-code`, `verify-registration-code`, `update-user-email` — these use JWT + service-role, no role-text gate.

So: no immediate breakage from the flip (role text still exists via dual-write). But `extract-lab-values` + `request-password-reset` join the "convert before retiring role text" list. Noted on our side too.

**3. Specialist isolation — preserved. Confirmed.**

migration_17 does not touch `specialist_patients` or `specialist_records` at all. They keep owner-only `specialist_id = auth.uid()` policies, admin-excluded (Model A). Not converted to permission-based. Isolation intact.

**4. Phased flip window / mixed-state — no DB-level mixed state. It's atomic.**

migration_17 is a single `begin; … commit;` transaction. All 13 tables' policies flip together on commit, or roll back whole on any failure. There is no committed half-flipped state a two-table flow could catch. Your "keep users off during the flip" is reasonable operational caution but not strictly required for DB policy consistency — there's no window where one table is permission-gated and another still role-gated.

Prod note: on prod, migration_17 lands after your two migrations (20260701, 20260706) — correct order, no cross-dependency (17 only rewrites existing staff/clinical/RBAC/storage tables; it assumes its target tables already exist, which they do on prod).

**5. is_flagged recompute trigger bundle — declining to bundle it. Separate migration, post-RBAC.**

Not because it's wrong — because it's the highest-risk change in the backlog (PL/pgSQL on core clinical tables) and welding it to the RBAC migration means a trigger bug could sink the RBAC rollout, with no way to roll back one without the other. It gets its own migration, tested independently on staging-copy first, right after RBAC lands. Happy to sequence it next — just not in the same pass.

---

**Net:** RBAC flip is proven on staging-copy (full role matrix + custom-role divergence). Points 2/3/4 are clean. Point 1's role_id is fixed; its underlying provisioning bug (point 1 bigger-issue) is the one thing needing a mobile-side fix — spec attached. Once that lands and you can load a patient dashboard, we do the real RBAC sign-off, then phased prod.
