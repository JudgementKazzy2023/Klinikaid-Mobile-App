# Combined source verification

Historical scratch `d552ca1c457c5403ec7ab267223af43932c4ad29` on main `d749c50` combined the source changes from PRs #5/#6/#7/#8/#24/#25/#26/#27/#28/#29. It was a local integration check, not a main merge, deployed-backend check or shipped build. All of those PRs have since merged to `main`; the current reference is `fd37ec5`.

## Scratch `d552ca1` (historical)

| Gate | Result |
|---|---|
|13 focused suites |215 passed,0 failed |
|Full tests, isolated network namespace |374 passed,1 existing skip,0 failures |
|Full analyzer |141 findings; exit1; no new normalized diagnostics against main or #25 baseline |
|Changed-path analyzer |27 existing findings; no new diagnostics |
|SDK/config |Flutter3.44.0/Dart3.12.0; unchanged lockfile and analyzer config |

The full analyzer improves from 152 on main to 141 in the combined set (11 fewer); it is not a clean static gate. The skipped deactivation test and live Auth/RLS/Realtime/AAL2 acceptance remain explicit. No Android SDK/device or installed artifact was verified.

The test repair in #25 is essential to the zero-failure combined result. One interaction needed a test-only correction: #28's queue PATCH mock returned an empty 204, while #7 requests updated row IDs. The mock now returns selected rows in #28 `ca69849`.

Source replay order (historical): #25, #5, #6, #7, #8, #24, #26, #27, #28, #29. The #29 stack requires #27. #5's audit-state hunk was omitted from the source-only replay; #5/#6 inherited audit histories were cleaned separately without changing implementation blobs.

## Main `fd37ec5` (2026-10-25 refresh)

| Gate | Result |
|---|---|
|GitHub Actions `Flutter checks` (job `analyze-and-test`) on `fd37ec5` |completed, success (2026-10-24T09:57:37Z) |
|Local tests, analyzer and Android build at `fd37ec5` |not re-run in this refresh |

The `d552ca1` counts above are not claimed for `fd37ec5`. Merged PRs #30–#69 landed after the scratch run (see [LEDGER.md](LEDGER.md)); their per-PR receipts are the evidence for those changes. Android SDK/device gates and installed-artifact provenance remain open under #23.

Private host artifacts retain the full source manifest, conflict notes, reproducible script, exact revisions/input hashes, baseline comparisons and logs under `combined-readiness`. No production accounts, rows, uploads, deployments or PR merges were used for the scratch check.
