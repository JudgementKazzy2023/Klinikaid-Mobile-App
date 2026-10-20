# Ordered GitHub alignment work

[Roadmap #9](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/9) tracks updates against mobile `d749c50` and web `06ccce1`. Each issue has pinned evidence, ownership, dependencies and acceptance checks. The numbers below are execution order, not an instruction to serialize independent work. Existing PRs are linked instead of duplicated.

- 01 · P1 · [#10: Restore deterministic native verification before acceptance](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/10)
- 02 · P1 · [#11: Complete session, account-switch and deferred-work isolation](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/11)
- 03 · P1 · [#12: Preserve patient queue state across cache and realtime changes](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/12)
- 04 · P1 · [#13: Align reception routing and vitals with the shared triage contract](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/13)
- 05 · P1 · [#14: Report saved results and queue completion as distinct outcomes](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/14)
- 06 · P1 · [#15: Complete laboratory recording and reference-data compatibility](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/15)
- 07 · P1 · [#16: Deliver the reviewed patient submission contract and coordinated mobile adapter](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/16)
- 08 · P1 · [#17: Verify shared authentication, onboarding and recovery contracts](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/17)
- 09 · P1 · [#18: Align staff read/mutation permissions and authoritative side effects](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/18)
- 10 · P2 · [#19: Make cached patient reads honest, scoped and complete](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/19)
- 11 · P2 · [#20: Preserve chat turn identity and safe request lifecycle](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/20)
- 12 · P2 · [#21: Make staff search, pagination and totals complete and truthful](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/21)
- 13 · P2 · [#22: Share intended form, calendar and email validation across clients](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/22)
- 14 · P2 · [#23: Establish Android release configuration and shipped-build provenance](https://github.com/JudgementKazzy2023/Klinikaid-Mobile-App/issues/23)

Backend-blocked tasks remain explicit. PR #3 retains its submission execution/release hold. Focused passing checks do not waive native gates, live-contract evidence or release ownership.

Delivery updates: draft #24 covers the MFA/transient portion of #11; draft #25 repairs the two default-test failures under #10; draft #26 covers the locally verified queue/cache portion of #12. Deferred-draft ownership under #11 is the next bounded implementation. These are draft changes, not shipped parity or closed acceptance issues.
