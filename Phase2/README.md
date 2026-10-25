# Phase 2: patient submission records

The accepted contract and coordination record for patient document submission, archived from draft PR #3. The implementation lives in the shared backend, not here.

| Document | What it is | Status |
|---|---|---|
| `stage1_submit_template_spec.md` | Stage 1 (templates) contract and decision table | Implemented in Setsuna-guwah/KlinikAid#215: migration 41 applied, `patient-document-submission` deployed |
| `stage2_upload_submission_spec.md` | Stage 2 (uploads) contract | Implemented in Setsuna-guwah/KlinikAid#223: migration 42 applied, `/upload` and `/upload/status` deployed |
| `phase2_ownership_matrix.md` | Who owns which part (mobile, web, shared backend) | Accepted on #36 |
| `phase2_interim_containment.md` | Why mobile submissions were contained, and the exit criteria | Containment lifted by #62. `PatientSubmissionContainment` stays as a kill switch |
| `phase2_spec_draft.md` | The original Phase 2 draft | Historical; superseded by the Stage 1 and Stage 2 specs |
| `patient_test_detection_drift.md` | Notes on drift in test detection between web and mobile | Reference |
| `../docs/patient-submission-contract-question.md` | The original contract question | Historical |

The Deno handler drafts in #3 (`Phase2/drafts/submit-template/`) are superseded by KlinikAid#215 and are deliberately not archived.

Tracking: #9, #16, #36.
