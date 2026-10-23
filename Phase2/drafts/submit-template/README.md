> **Superseded (2026-10-23):** the reviewed implementation of this draft is web PR
> [Setsuna-guwah/KlinikAid#215](https://github.com/Setsuna-guwah/KlinikAid/pull/215)
> (`supabase/functions/patient-document-submission` + `migration_41.sql`), wired
> to a real transaction and importing the web template modules directly. The
> files here are kept as the review history; change #215, not these.

# submit-template: owner-review draft, not deployable

**Published source revision:** mobile PR #3 commit `3db90ac`. This is a source
draft with production persistence unwired, not an absence of implementation.
It is not approved for deployment; execution hold remains.
The local uncommitted revision incorporates the owner's PR reply checked against
`3db90ac` / web `06ccce1`. Catalog, template checks and submit action are unchanged
from `940a2f6`; the validation.ts difference concerns blood pressure only.

Owner: **@Setsuna-guwah**, including deployment, rollback, and maintenance.
No database changes, function deployment, mobile adapter, commit or push are
part of this contribution. Existing mobile containment stays enabled.

## Decisions 1-3: authoritative web findings

The source draft uses **pinned web revision 940a2f6**, not the mobile Dart catalog.
The reference files here are review snapshots of that pinned web revision,
with only two alias imports in templateChecks.ts changed to relative imports.
They are NOT a newly approved independent schema authority.

1. **Catalog:** `src/lib/documentTemplates.ts` defines six templates; the web
   action and `src/lib/documents/templateChecks.ts` import it. There is no
   catalog-table lookup in this flow. Decision 1 option (c), an owner-approved
   shared module/export usable by Next.js and Deno, is the agreed direction.
   Backend acceptance of the extracted version and both runtime consumers
   remains a separate gate. Do not maintain these snapshots as a third catalog.
2. **Bounds:** PR #102 (`0d61ea8`) adds text <=200 UTF-16 code units and
   textarea <=2000. All answers are trimmed before required/bounds checks.
   Missing optional answers normalize to "". Dates must be real YYYY-MM-DD
   calendar dates, >=1900-01-01 and <=today +2 calendar years (web's Date.UTC
   rollover behavior on leap day), using Asia/Manila today. Referral and
   consent dates additionally cannot be future. Other dates are NOT
   future-only: past dates inside the range are accepted.
   PR #113 (`58d3098`) changes demographic validation, not these template
   answer limits: name minimum 3->2 (max100), DOB max age120, trimmed address
   required/max255, clinical notes max2000, rejection reason20-1000.
   Those name/address/notes rules are not additional template answer fields.
   The template action copies stored demographics without revalidating names,
   contact or address. Draft follows that behavior.
3. **Age:** action calls validateAge for patient-intake only, server-side.
   It requires a valid DOB, not future, no more than120 years old, and age>=18,
   with birthday comparison against Manila today. This contradicts the spec's
   earlier registration-age statement: mobile main and web already use18+.
   This is a stale-reference correction, not a shipped registration fix.
   Valid-underage intake DOB maps to403 AGE_REQUIREMENT_NOT_MET; missing,
   malformed/future/over-120-year stored DOB maps to500 SERVER_DATA_INVALID.
   The latter asks the patient to contact the clinic, with no clinical values
   in diagnostics and no automatic retry until corrected. Failed reads are503.

### Exact field schema

All fields required unless marked optional. Text/textarea bounds above apply.

| Template | Name | Fields |
|---|---|---|
| referral-form | Referral Form | referring_physician:text; referring_clinic:text(optional); reason_for_referral:textarea; requested_service:select Laboratory/Imaging/Ultrasound/ECG; referral_date:date(not future) |
| lab-request | Laboratory Request | ordering_physician:text; tests_requested:textarea; fasting_required:select Yes/No(optional); request_date:date |
| med-cert | Medical Certificate Request | purpose:textarea; date_needed:date |
| procedure-consent | Consent Form | procedure:text; consent_given:select Yes/No; consent_date:date(not future) |
| patient-intake | Patient Intake Form | chief_complaint:textarea |
| results-release | Results Release Authorization | release_to:text; results_type:text; authorization_date:date |

Form-level `consent_given:"No"` is accepted and retained. Reception computes
"Needs attention" from stored answers with reviewTemplateSubmission; there is
no new persisted consent flag to invent. This is separate from the account's
profiles.accepted_privacy_at gate. No selected_tests field is accepted for
these forms; tests_requested remains free text in lab-request.

## Source reference

### Historical checkout observation

During the 2026-10-20 source audit, the local web checkout was observed at
`6e9a61d`. It was not reset or used as the reference baseline. This is historical
workspace context only, not the current published draft revision and not a
deployment observation. The published draft is `3db90ac`; the web source it
references remains `940a2f6`.

### Pinned source files

- `src/app/(dashboard)/patient/templates/actions.ts`: patient lookup by
  profile_id, server-derived document values, intake demographic injection.
- `src/lib/documentTemplates.ts`: ids, names, fields, select sets, bounds.
- `src/lib/documents/templateChecks.ts`: normalization and reception review.
- `src/lib/validation.ts`: Manila calendar and age/DOB rules.
- `src/lib/auth/temporary-password.ts`: **auth app_metadata** flag, not
  user-editable user_metadata or an invented profiles column.
- `src/lib/auth/privacy-consent.ts`: profiles.accepted_privacy_at.

## Draft implementation

`index.ts` follows extract-lab-values' serve/createClient/getUser pattern.
It validates the JWT remotely and resolves account data with server credentials.
Failed reads produce SERVER_ERROR, not misleading missing-record/consent errors.
No secrets, patient values, raw exception text, or arbitrary submitted key names
are returned/logged. No Storage calls exist.

`handler.ts` implements the original six account checks plus a distinct
authoritative patient-role check before replay, unknown-key
rejection, field validation, metadata derivation, canonical SHA-256 request
fingerprints, scoped replay/conflict/in-progress handling, and success/error
responses. Identity assertion requires returned patient.profile_id==user.id;
document.patient_id is patient.id. It does not incorrectly require the two
UUID values to be different.

Revised transport contract: non-string field values are
FIELD_INVALID (web currently coerces these to empty); unknown top-level keys
are UNKNOWN_FIELD with field=body; malformed JSON/request_id is FIELD_INVALID.
Known field failures include the field key. All spec section8 codes are present.
Validation/unknown-key errors explicitly use400, not422. Unsupported methods
return405 METHOD_NOT_ALLOWED with Allow: POST, OPTIONS. OPTIONS is preflight;
neither path reads identity/data or writes. Active profile role=patient and a
linked patient row are independent gates; staff with linked rows are refused
with403 PATIENT_ACCOUNT_REQUIRED.
The error text is deliberately generic and contains no submitted values.
Filename date follows web's implicit runtime timezone; clinical date/age bounds
explicitly use Manila. Owner should confirm filename timezone before release.

## Mandatory open owner decisions (no defaults)

**Production persistence is deliberately not implemented.** index.ts leaves
SubmissionStore absent, so valid requests fail closed with503. This is a
reviewable handler, not a reachable submission service.

- **Retention:** withRequest/lookup must expose expired keys; onExpired is a
  required owner callback. Seven days remains a proposed target, not a backend
  guarantee. Receipts carry first_accepted_at and expires_at; the draft treats
  at/after expiry as reconciliation, retaining outcome/tombstone evidence.
  Offline draft age is separate: never-sent drafts have no receipt. Unknown
  outcomes retain the same key and normalized payload. No expiry-key reuse.
  The latest owner reply proposes status lookup and outcome states; see Stage 1
  section7. The endpoint, exact schema and named operational ownership remain
  unaccepted/unimplemented. Do not implement a fresh-key fallback.
- **Decision4 duplicates:** enforceDuplicate must coordinate with creation
  across web and mobile atomically. Category definition, cross-method scope,
  index/transaction mechanism and whether to expose existing document_id remain
  unanswered. A read-before-insert implementation is not acceptable.
- **Audit implementation:** revised contract requires a single transaction
  for document, attributed DOCUMENT_SUBMITTED event and receipt. Audit failure
  rolls back; no outbox. Implementation and real crash/rollback verification
  remain blocked. Unknown outcomes cannot release a key for blind reinsertion.
- **Shared authority:** confirm how reference modules become shared/versioned
  web+Edge dependencies rather than maintained copies.

Mobile's existing category comparison already has no exemption for `other`.
That is client UX only, not atomic enforcement. Legacy conflicts still need a
read-only report and approved resolution before backend enforcement.

withRequest must provide durable cross-instance exclusion on
(user_id, operation, request_id). Separate user/operation keys do not collide.
The canonical fingerprint includes normalized template id/answers, not server
timestamps or current demographics. An original completed receipt is returned
without a second event. Account gates still run on every replay.

## Verification boundary

Run `deno test --deny-net --deny-env --deny-read --deny-write handler_test.ts`
from this directory. Tests import only local pure modules, use synthetic
patients and an explicitly test-only store, and require no credentials.
They exercise the handler contract, not a database integration.

Real cross-web/mobile atomic duplicates, durable concurrency, expiry behavior,
and audit failure recovery **cannot be certified** until the owner supplies
the persistence mechanism/policies. Tests for these remain explicitly ignored
or use a labeled fake to test only propagation/coordination requirements.
No production patient records are needed or permitted for these tests.

### Historical verification of 3db90ac, 2026-10-20

- Permission-denied test run: **21 passed, 0 failed, 3 explicitly ignored**.
- `deno check index.ts`: passed with pinned public dependencies; only type
  checking, not serving the function or contacting Supabase.
- Reference parity: all three snapshots verified against `git show 940a2f6`,
  allowing only the two documented local import substitutions.
- Tests cover all six templates, derived patient-row identity, account gates
  including replays, normalized replay/conflict, same-key concurrency in the
  fake store, user/operation scoping, metadata injection, date/length/age
  boundaries, malformed input, declined form consent, and fail-closed handling.
- Real storage guarantees remain unverified and deliberately unwired.
  The three ignored cases are release blockers, not waived requirements.

### Local revised-contract verification, 2026-10-20

- **27 passed, 0 failed, 3 explicitly ignored**, with network, environment,
  filesystem read and write permissions denied during handler tests.
- Entrypoint type-check and handler/entrypoint/test lint passed.
- Added explicit 405/Allow and OPTIONS checks, authoritative role versus linked
  row tests, invalid stored DOB versus underage/read-failure tests, proposed
  seven-day boundary fixtures (before/at/after), ambiguous post-commit response,
  and fake atomic-failure preservation checks.
- Production persistence, real cross-client duplicate enforcement, durable
  retention/tombstones and database rollback/crash behavior remain unverified.
  The fake store's timestamps are fixture data, not production TTL settings.
- Registration-age wording corrects stale documentation: mobile main already
  uses18+. No registration implementation changed.
- Changes remain local and uncommitted pending review. Containment stays in place.
