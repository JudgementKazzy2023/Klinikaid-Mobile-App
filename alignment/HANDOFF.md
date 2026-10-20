# Alignment handoff

Mobile source d749c50; current web63a4f01; submission draft3db90ac. Original checkouts preserved. Full discrepancy evidence and sensitive findings remain private; the public acceptance backlog is [LEDGER.md](LEDGER.md).

- Draft #5 (`412335d`): shared email validation,40focused checks pass.
- Draft #6 (`8d39378`): authenticated triage RPC,9focused checks pass.
- Draft #7 (`cb6f981`): honest result/queue completion outcome,10focused checks pass.
- Draft #8 (`9559bc8`): current web BP input rules,8focused checks and narrow-screen visual check pass.
- PR #3 (`3db90ac`): review response posted;21local Deno tests pass,3integration cases blocked; lint/typecheck pass. Backend persistence remains unwired, ownership acceptance/spec finalization/release gates remain open.

Queue/cache, MFA-state cleanup and deterministic default tests are in progress in isolated Pi MiMo worktrees. New subagents explicitly select Pi `xiaomi-token-plan-sgp/mimo-v2.6-flash`, thinking high. Previous interrupted partial work is retained.

Latest native environment is documented Flutter3.44.0/Dart3.12.0 with committed lockfile. Full gates remain red: two existing failures and151–152analyzer diagnostics; one existing skipped test. APK builds attempted and blocked by missing Android SDK; device access disabled. Focused regressions do not prove deployed RLS or installed APK behavior.

Read-only schema refresh confirms relevant RPCs and an added role-normalization surface. Public-key configuration still answers401; deployed policy/function-code inventory and shipped APK provenance remain blocked. No production writes, fixtures or deployments.
