# Mobile-Originated Schema Proposals

This file tracks schema modifications and policies introduced during mobile app development that need to be adopted by the web team to maintain canonical backend parity.

---

## 1. Patients Table Insert Policy

* **Date Proposed**: 2026-05-24
* **Origin**: Phase 2 (Auth & Patient Onboarding)
* **Status**: **PENDING WEB-TEAM ADOPTION** (Implemented on mobile project `vxnkpcqyrxdqxpvutkmm` for testing/onboarding)

### SQL Statement
```sql
CREATE POLICY "Patients can insert own patient record"
  ON public.patients FOR INSERT
  WITH CHECK (profile_id = auth.uid());
```

### Rationale
* The mobile patient onboarding flow requires new users (role = `patient`) to insert their clinical registration data directly into `public.patients` (linked via `profile_id` referencing their authenticated user ID).
* The web team's canonical `schema.sql` only granted `ALL` permissions on the `patients` table to admins and receptionists. Consequently, the onboarding insert failed with PostgreSQL error code `42501` (Access Denied / RLS Blocked).
* This policy safely permits authenticated patients to insert *only* their own patient record matching their unique user ID (`auth.uid()`).

---

## Phase 6 Merge Checklist Items
- [ ] Verify that the web team has incorporated the `"Patients can insert own patient record"` policy into the canonical schema.
- [ ] Confirm the policy is deployed in the shared production/staging database environment prior to the final project merge.
