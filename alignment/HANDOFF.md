# Alignment handoff

Preserved checkouts: mobile main `d749c50`, web `06ccce1`; web remote master refreshed to `9aedf87`. Laboratory/submission contract files are unchanged across the web refresh. Private evidence lives on the audit host; public scope/acceptance is tracked in [LEDGER.md](LEDGER.md) and [roadmap #9](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/9).

| Draft PR | Tested revision | Covered local evidence |
|---|---|---|
| #5 email validation | `412335d` |40 focused checks |
| #6 authenticated triage | `8d39378` |9 focused checks |
| #7 saved-results/queue outcome | `cb6f981` |10 focused checks |
| #8 blood pressure | `9559bc8` |8 focused checks plus narrow-screen visual |
| #24 MFA/transient identity state | `77302ee` |24 focused checks |
| #25 deterministic default tests | `f65fd9d` |205 pass/1 existing skip/0 failures; analyzer142 |
| #26 queue/cache snapshots | `7b4fabd` |22 focused checks |
| #27 deferred draft ownership | `3270ad4` |19 ownership checks |
| #28 narrative laboratory results | `511bae2` |36 narrative/94 combined focused checks; full237 pass/1 skip/2 baseline failures |
| #29 immediate ownership, stacked on #27 | `0c9f7b0` |45 combined focused checks; full236 pass/1 skip/2 baseline failures |

Covered local acceptance passes for those revisions; none is a claim of merged/shipped parity or deployed authorization. Most implementation branches retain the two default-test failures repaired separately by #25. Full analyzer remains red (typically152 baseline findings); #28/#29 have no changed-file findings. #24 retains23 pre-existing infos. Earlier #5/#6 evidence used Flutter3.47.7; later native gates use pinned3.44.0/Dart3.12.0 and unchanged lockfile.

One Pi MiMo high worker is active: combined-source readiness in a scratch worktree, including #25. It will check PR interactions and return minimal conflict/regression patches without changing existing PR branches, pushing or merging main. #5/#6 still contain inherited audit-document commits in their histories; cleanup is a separate reviewability item. Task IDs and private receipts are in the durable host handoff under `refresh-6`.

Remaining priorities: issue #15 clinical numeric/reference criteria, session/permission and live Auth evidence under #11/#17/#18, shared backend submission contract under #16, read/cache honesty, chat identity/concurrency and language transport alignment, pagination, configuration and release provenance. Web opt-in dark mode is a platform/product decision; its new chat-language behavior needs shared-transport review.

PR #3 remains a review-only source draft (`3db90ac`):21 local Deno checks pass/3 integration cases blocked, persistence unwired. Planning, reconciliation UX and interim-function questions were answered in the PR; no deployment or interim-route approval was granted. No production mutations, fixtures or deployments. Already-dispatched requests, ambiguous commits and server idempotency remain backend requirements.

Read-only schema evidence does not establish policy/function bodies, grants or shipped versions. The checked local public key returned401; Edge management inventory lacks a token. Android SDK/device access and installed-artifact provenance remain unavailable. Every worked PR is linked; no watches run.
