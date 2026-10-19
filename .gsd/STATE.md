# Alignment state

Initial source revisions: mobile d749c50; web 940a2f6. Both original checkouts clean. Lead isolated in audit/mobile-web-alignment.

Read-only deployed OpenAPI receipt: /tmp/klinikaid-alignment/deployed-openapi.json. Confirms triage_patient and submit_assessed_document signatures and documents.source_assessment_id; it does not prove RLS policy bodies, deployed function code, migration history, or mobile release provenance.

Audit workers: auth_audit, staff_audit, other_audit. Private evidence destinations /tmp/klinikaid-alignment-{auth,staff,other}.md. No production writes or deployments.

Flutter/Dart absent from PATH. Provisioning an isolated SDK under /tmp/klinikaid-flutter-sdk; official release-index URL returned HTTP 404. No shipped APK/revision established.
