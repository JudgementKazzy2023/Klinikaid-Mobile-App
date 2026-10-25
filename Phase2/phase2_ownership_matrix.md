# Ownership Matrix — Patient Document Submission (Phase 2)

**Status:** Proposed by web team, pending explicit mobile acceptance.
**Date:** 2026-10-20
**Function:** `patient-document-submission` (tentative name)

---

## Split

| Area | Owner | Scope |
|---|---|---|
| Contract definition | **Web / shared backend** (`@Setsuna-guwah`) | Request/response shapes, validation rules, error codes, versioning |
| Backend implementation | **Web / shared backend** | Edge Function source, server-side validation, identity derivation, audit emission |
| Schema compatibility | **Web / shared backend** | Any table/column/policy changes the function requires |
| Versioning | **Web / shared backend** | Contract version, backward-compatibility policy |
| Deployment | **Web / shared backend** | Deploy to staging and prod |
| Rollback | **Web / shared backend** | Rollback plan and execution |
| Maintenance | **Web / shared backend** | Ongoing fixes to the function |
| Mobile adapter | **Mobile** | Client-side service calling the function, request construction, response handling |
| Submission screens | **Mobile** | Template form, upload flow, error/retry UX |
| Offline queue & retries | **Mobile** | Draft persistence, retry policy, stable request ID generation |
| Compatibility tests | **Mobile** | Mocked contract tests, Gate D device verification |
| App release | **Mobile** | APK build, release, rollout |

---

## Explicit constraint

**Mobile must not independently deploy `patient-document-submission`.**

This differs from mobile's previous Edge Functions (`create-patient-record`,
`extract-lab-values`), which mobile owned and deployed. This one is shared
infrastructure serving both clients, so its lifecycle sits with the backend
owner.

This is a proposed function-specific restriction, not an accepted transfer of
all mobile Edge Function ownership. Prior deployment of create-patient-record
and extract-lab-values does not automatically authorize this new function.
Nor does this proposal revoke existing authority for those functions; their
existing approval requirements remain. No new standing deployment authority is
granted by this document.

---

## Acceptance required

This matrix is **proposed, not accepted.** Mobile acceptance should confirm:

1. Mobile agrees it does not deploy this function.
2. Web/shared backend accepts contract, implementation, deployment, rollback,
   and maintenance.
3. A named point of contact on each side for contract changes.
4. How contract changes are communicated before they land on prod. The observed
   incompatibility is that live restrictions and current mobile direct writes
   do not match; the history of release coordination has not been independently
   established here.

## Mobile acceptance and pushback register

All items below remain pending; preparing these documents does not accept them.

| Decision | Mobile position for review | Required acceptance |
|---|---|---|
| No independent deployment of this function | Accept in principle only with an accountable backend owner, review channel and release process; do not create a second implementation on the shared project | Ralph/mobile and @Setsuna-guwah |
| Named ownership | @Setsuna-guwah proposed backend owner; Ralph Andre Garcia proposed mobile contact | Both explicitly confirm in PR #3 |
| Backend delivery and support | Request a reachable test environment, contract version, target milestones, incident contact and approved backup/release delegate. Do not promise a multi-week schedule without agreement | Backend owner, mobile reviewer |
| Contributions | Mobile may propose backend source/tests through review; contribution is not deployment permission | Backend owner |
| Compatibility gate | Require mobile evidence before shared policy/storage/auth changes that affect supported mobile releases; define notification and backward-compatibility/deprecation period | Both owners |
| Production and rollback | Backend owner approves backend release/rollback; mobile owner separately approves APK release. Rollback must not restore insecure patient policies | Both owners |
| Test/cleanup ownership | Name who provisions disposable fixtures, approves any live tests, reconciles ambiguous submissions and performs scoped cleanup | Backend owner with mobile coordination |
| Existing functions | No implicit ownership transfer for create-patient-record or extract-lab-values; assess separately if shared dependencies change | Both owners if scope expands |

**Blocking:** ownership acceptance, endpoint/version contract and environment
availability remain unresolved. Do not mark the Phase 2 spec FINALIZED.

---

## Dependency note

Mobile cannot begin adapter implementation until:
- The contract is defined and shared, and
- The function is deployed to a reachable environment (staging at minimum).

Building an adapter against an undeployed or unspecified endpoint produces
untestable code. Mobile's Phase 2 work is **blocked on backend delivery**, and
the schedule should reflect that dependency rather than running in parallel.
