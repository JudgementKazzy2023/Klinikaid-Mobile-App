# Combined source verification

Scratch revision `d552ca1c457c5403ec7ab267223af43932c4ad29` on main `d749c50` combines the source changes from PRs #5/#6/#7/#8/#24/#25/#26/#27/#28/#29. This is a local integration check, not a main merge, deployed-backend check or shipped build.

| Gate | Result |
|---|---|
|13 focused suites |215 passed,0 failed |
|Full tests, isolated network namespace |374 passed,1 existing skip,0 failures |
|Full analyzer |141 findings; exit1; no new normalized diagnostics against main or #25 baseline |
|Changed-path analyzer |27 existing findings; no new diagnostics |
|SDK/config |Flutter3.44.0/Dart3.12.0; unchanged lockfile and analyzer config |

The full analyzer improves from152 on main to141 in the combined set (11 fewer); it is not a clean static gate. The skipped deactivation test and live Auth/RLS/Realtime/AAL2 acceptance remain explicit. No Android SDK/device or installed artifact was verified.

The test repair in #25 is essential to the zero-failure combined result. Other individual implementation branches still carry the two known default-test failures until that repair is integrated.

One interaction needed a test-only correction: #28's queue PATCH mock returned an empty204, while #7 requests updated row IDs. The mock now returns selected rows in #28 `ca69849`; that test blob matches the corrected combined input. Its exact-revision rerun passes36 narrative checks, with full237 pass/1 skip/2 baseline failures and152 analyzer findings on the individual branch.

Source replay order: #25, #5, #6, #7, #8, #24, #26, #27, #28, #29. The #29 stack requires #27. #5's audit-state hunk was omitted from the source-only replay; #5/#6 inherited audit histories are being cleaned separately without changing implementation blobs. No tests or guards were dropped.

Private host artifacts retain the full source manifest, conflict notes, reproducible script, exact revisions/input hashes, baseline comparisons and logs under `combined-readiness`; the lead handoff preserves a durable copy. No production accounts, rows, uploads, deployments or PR merges were used.
