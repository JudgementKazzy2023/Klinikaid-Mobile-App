# Shipped Patient Test-Detection: Compatibility Drift

Date: 2026-10-20. Status: tracked for separate review; no implementation approved.
This concerns a shipped feature, not only the blocked Phase 2 endpoint.

## Baselines and evidence

- Mobile main d749c50 / documentation PR head f919be4; submission code unchanged.
- Web reviewed through 940a2f6; changes below are merged-source observations,
  not proof of endpoint behavior or migration deployment.
- Original byte-exact port does not establish ongoing parity after web changes.

## PR #99: catalog and receiving workflow

https://github.com/Setsuna-guwah/KlinikAid/pull/99 (f16575a)

Web adds per-test recording mappings and narrative lab support for requests
not covered by the four structured panels. Labels for the existing single-value
renal/lipid panels become Creatinine and Cholesterol (total), while stored
panel keys remain unchanged. This is potential catalog/workflow drift; the PR
does not by itself prove detection IDs or aliases changed.

Separate audit needed: compare mobile lib/features/documents/clinic_test_catalog.dart
against web src/lib/constants.ts for IDs, labels, aliases, departments and
recording mappings. Check that mobile department entry can fulfill each requested
test. Record exact differences before proposing a port. Do not invent clinical
ranges, alter stored panel keys, or change is_flagged under this tracking item.

## PR #117: selection and acknowledgement

https://github.com/Setsuna-guwah/KlinikAid/pull/117 (ada580d)

Confirmed source mismatch: mobile submit_document_screen.dart passes
_selectedTestIds at line 148 and allows removing all selections (lines 721/749);
its submit path has no nonempty-selection guard. Web now refuses zero selection
when tests were detected and requires explicit submit-anyway acknowledgement
when none were detected. Quality confirmation alone is not this acknowledgement.

No agreed mobile/Edge Function acknowledgement field exists. Do not invent one
or treat the earlier proposed JSON as sufficient. Resolve the UI behavior and
server acknowledgement/validation contract with the backend owner before a fix.
Keep detected_tests frozen and selected_tests authoritative for patient choices.

## Separate review gate

- Compare exact catalogs and receiving workflows; approve differences explicitly.
- Agree zero-selection versus zero-detection behavior and acknowledgement contract.
- Plan mocked tests for deselect-all, no detections, valid selection, metadata
  preservation and reception interpretation. No production submissions here.
- Track this independently of Phase 2 delivery. No fix, deployment, or change to
  the previously shipped behavior is included in this documentation update.
