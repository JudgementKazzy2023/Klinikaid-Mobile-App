# Web team: patient document submission contract needed

Date: 2026-10-18

Status (updated 2026-10-20): web guidance received; documentation drafts ready
for review. Ownership acceptance, contract finalization and implementation/release
approval remain pending. The original questions below are historical context.

## Review documents

- [Phase 2 spec draft](../Phase2/phase2_spec_draft.md)
- [Proposed ownership matrix](../Phase2/phase2_ownership_matrix.md)
- [Interim containment plan](../Phase2/phase2_interim_containment.md)
- [Separate shipped test-detection drift tracker](../Phase2/patient_test_detection_drift.md)

Read-only Storage confirmation on 2026-10-20 found the PR #116 pending-only
INSERT/DELETE restriction live with Storage RLS enabled. Current mobile upload
paths fail before the independently restricted document insert. See the spec
for evidence and limits; no production submission test was run.

## The question

Patient document INSERT/UPDATE RLS policies have been removed on the shared
backend. Mobile still submits documents directly using the patient session.
Those inserts are now denied for normal patients without documents.manage.

What server contract should mobile use for patient document submission, and
what validation must that server enforce for patient identity, uploader,
initial status, and deduplication?

The mobile team can build a new Edge Function following the authenticated
server-operation pattern used by create-patient-record. Please confirm that
approach, or identify an existing supported endpoint and its contract. We will
not assume create-patient-record itself handles document submissions.

## Current evidence

- Read-only Phase 1 checks confirmed documents RLS is enabled, patient-specific
  INSERT/UPDATE policies are absent, and remaining write-capable policies
  require documents.manage.
- This matches web PR #76:
  https://github.com/Setsuna-guwah/KlinikAid/pull/76
- Web moved its upload-confirmation and template submission inserts into
  privileged server actions. That does not automatically expose a supported
  mobile endpoint.
- Corrected call-site map: templates directly insert through
  lib/features/patient/templates/data/templates_repository.dart; online uploads
  and offline replay call DocumentsRepository.insertDocument through
  lib/features/documents/presentation/providers/document_submission_provider.dart.
  There are three active insert paths. An unused pending UPDATE helper exists;
  no patient-side remote document DELETE caller was found in the audited source.
- The deployed Edge Function inventory did not show a dedicated document
  submission function. No submission was invoked during these checks.

## Requested contract confirmation

Please answer in this PR before we write the Phase 2 spec:

1. **Endpoint and authentication:** new Edge Function or existing endpoint;
   accepted authentication; applicable consent, verification, active-account,
   and temporary-password gates.
2. **Identity and status:** how the server derives patient_id and uploader_id
   from the authenticated user; the required initial status; which submitted
   fields must be ignored or rejected rather than trusted.
3. **Upload and template validation:** accepted request fields, required
   document/template identifiers, storage ownership checks, allowed metadata,
   and the source of authoritative OCR/quality/test-selection values. Specify
   how document_type, ocr_text, detected_tests, and selected_tests are handled.
4. **Deduplication:** the authoritative duplicate definition, comparison scope,
   existing helper to reuse if any, and expected duplicate response. Keep
   business duplicate detection distinct from retry idempotency.
5. **Response contract:** success JSON, document identifier/status, validation
   errors, authorization errors, duplicate responses, and required audit events.

## Holds and boundaries

- No Phase 2 spec until the core contract is confirmed by the web team.
- Retry/idempotency and file cleanup can be explored separately, but final
  behavior depends on the contract, especially ambiguous timeout outcomes.
- Do not reopen patient write policies or place service-role credentials in
  the mobile client.
- No application code, DB migrations, deployments, or audit-record changes are
  included in this PR. No patient records or credentials are included.
- Phases 2-4 remain on hold pending review and contract confirmation.

## Web team response

- Chosen endpoint/approach:
- Authentication and account gates:
- Request JSON and server-derived fields:
- Upload/template/metadata validation:
- Dedup rules and response:
- Success/error JSON and audit requirements:
- Contract owner and deployment coordination:
