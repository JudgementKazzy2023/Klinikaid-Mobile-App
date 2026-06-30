# Phase 9 Plan Review — Testing, Hardening & Release

> **Gate B — Plan Review.** Reviewer: Claude (per `MASTER_CONTEXT.md` section 5).
> Subject: Phase 9 Implementation Plan (`1782007559650_implementation_plan.md`).
> This file is authoritative plan review feedback for the Antigravity agent.

## Verdict: CHANGES REQUIRED — seven items

The plan covers the right surface area (consent cleanup, test execution, security pass, integration demo, release build) and the consent migration cleanup is correctly scheduled. But the plan has **several material gaps** for a final phase that determines defense readiness. None require rewriting from scratch — they need additions and one factual correction.

Phase 9 is the **final** phase. The verification standard set by Phases 5/7/8 must hold here too: every claim has matching evidence. The plan has weakened from Phase 8's rigor in two key places (ISO 25010 and APK security pass). Fix those and add four smaller items, and Gate B is APPROVED.

What's right before flagging issues:

- **Consent cleanup correctly scheduled.** Phase 8 marked this as a punch-list item; Phase 9 closes it. Right timing.
- **The `pumpAndSettle` fix** addresses a real testing pain point. Good.
- **Two integration scenarios** (document submission + queue progression) are reasonable workflow demos.
- **Patient regression suite** is comprehensive — all six patient test files listed.

Now the issues.

---

## CHANGES REQUIRED — Issue 1 (factual): the ISO 25010 Usability description is wrong

The plan says:

> *Usability: Readability, **Outfit font presentation, dark-themed style**, simple input validations, appropriate size for action chips.*

This is factually incorrect post-Phase-6. The 2026-06-11 theme migration replaced the dark indigo + Outfit font with the **light cream + forest-green palette and Inter typography** (per `MASTER_CONTEXT.md` Section 2 "CURRENT REALITY" and the `theme_migration_review_final.md`).

If the ISO 25010 evaluation report references "Outfit font" and "dark-themed style," any panelist who has seen the actual app will spot the mismatch immediately. This signals the documentation hasn't kept up with the implementation — a credibility issue right before defense.

**Required action:** correct the Usability description to: *"Readability, Inter typography, light cream + forest-green palette consistency with the web team's design system, simple input validations, appropriate size for action chips."*

---

## CHANGES REQUIRED — Issue 2: the ISO 25010 evaluation is underspecified

A "1-5 scale across the five characteristics" is a rubric, not a methodology. For a defense-ready ISO 25010 evaluation, the plan must specify:

- **Who scores it.** Self-scored by the team? Scored by clinic staff? Scored by an outside evaluator? Each has different credibility levels.
- **What artifacts result.** A scored table? A written report? A demo video? A test recording?
- **What evidence supports each score.** A score of "4/5 for Reliability" needs a backing test or observation — not just a number.
- **The minimum-spec performance scenarios from Phase 6 review.** That review specified four concrete load scenarios for ISO 25010 Performance Efficiency:
  1. 100 concurrent users hitting the `chat` Edge Function.
  2. One user with 500 historical `chatbot_logs` opening the chat tab.
  3. Realtime burst — 10+ status changes in 60 seconds.
  4. Phase 4 offline queue — 20 queued submissions all syncing at once.

The plan does not mention these scenarios. They were committed to in writing in `phase6_review.md`.

- **The minimum-spec hardware requirement.** Scenarios 2 and 4 require a **real Android 8.0 / 4GB / quad-core device**, not an emulator. The emulator gives functional verification only — not performance numbers worth defending.

**Required action:** restructure the ISO 25010 section to specify scoring methodology, the four load scenarios, and the real-device requirement for Scenarios 2 and 4.

---

## CHANGES REQUIRED — Issue 3: APK security pass methodology is too vague

The plan says:

> *"Extract the contents of the generated APK (or perform a code inspection on compiled assets). Search files for the Gemini API key pattern (`AIzaSy...`) and the word `service_role` to confirm zero matches."*

Two problems:

**Problem A — the "or" is dangerous.** "Code inspection on compiled assets" is not a valid substitute for decompiling the actual APK. The agent could literally `grep` the source code in `lib/` (where the key obviously isn't), declare it clean, and miss anything baked into compiled Dart bytecode or Android resources. The threat model is: **what's actually in the file that ships to users?**

**Problem B — the search strings are incomplete.** Phase 5's APK decompile check used:
- `AIzaSy` (Google API key prefix)
- `GEMINI` (variable name)
- `service_role` (Supabase admin key role identifier)

The Phase 6 plan added (for Phase 7/9): "and known JWT prefixes." Phase 9's list should include all of these.

**Required action:** rewrite the APK security pass methodology to:

1. Specify the decompile tool — `apktool` or `jadx`. No "code inspection" substitute.
2. Specify the exact commands:
   ```
   flutter build apk --release
   apktool d build/app/outputs/flutter-apk/app-release.apk -o /tmp/klinikaid_decompiled
   grep -r "AIzaSy" /tmp/klinikaid_decompiled
   grep -r "GEMINI" /tmp/klinikaid_decompiled
   grep -r "service_role" /tmp/klinikaid_decompiled
   grep -r "eyJ" /tmp/klinikaid_decompiled    # known JWT prefix; expect anon-key matches only
   ```
3. Specify what counts as a pass: `AIzaSy`, `GEMINI`, `service_role` all return zero matches. `eyJ` may match the anon key — that's expected and not a security issue.
4. Specify the evidence to paste at Gate D: the actual grep output, not a "no matches found" summary.

---

## CHANGES REQUIRED — Issue 4: the mobile/web integration test has no participation plan

The integration demo script defines two scenarios that span **mobile and web**. Both scenarios assume the web team is participating with their web app. But the plan doesn't say:

- Has the web team agreed to a time and date for the integration test?
- Is their app pointed at the shared project (`onzeyejlfydvvbkejvwf`) for the test, or do they need to switch configurations?
- Who plays what role during the demo — a team member on mobile, a web team member on web, or someone signed in to both?
- What if the web team is unavailable? Do you run a "single-operator" version where you sign in to both apps simultaneously?

This was flagged as a coordination item all the way back in Phase 1 and reaffirmed in Phase 6's walkthrough. The Phase 6 plan said: *"For the Phase 7 mobile/web integration test, we will temporarily configure the web app locally to connect to our mobile project's URL and anon key to demonstrate full interoperability."* That was Phase 7's wording at the time, but Phase 9 inherits this open coordination item.

**Required action:** specify in writing:

1. Has the web team confirmed they will participate, and on what date?
2. Which project URL their app will use during the demo.
3. The single-operator fallback if the web team is unavailable: you sign in to mobile + web simultaneously on two devices yourself, demonstrating the same scenarios.

The single-operator fallback is acceptable as a defense backup but should be documented as the contingency, not the primary plan.

---

## CHANGES REQUIRED — Issue 5: punch-list items from Phases 7 and 8 not addressed

The Phase 7 and Phase 8 review files left three documentation items on the punch list:

- **Phase 7 admin-block dialog screenshot** — committed but not delivered.
- **Phase 8 consent back-fill end-to-end test** — code path exists but no DB confirmation.
- **Phase 8 three staff dashboard screenshots** — receptionist + department + specialist UIs.

The Phase 9 plan should fold these into either: the ISO 25010 manual verification (where screenshots become evidence) or a small "Defense Materials" section.

**Required action:** add a "Defense Materials" subsection to the Verification Plan listing the screenshots and end-to-end tests that need to be produced. Without this, these items will likely be forgotten before defense.

---

## CHANGES REQUIRED — Issue 6: the release-build process is too thin

> *Generate the final production APK: `flutter build apk --release`. Confirm the binary builds cleanly and locate the path.*

For a capstone defense, a release build is more than a debug-mode build with the `--release` flag. The plan doesn't address:

1. **Signing.** The APK needs a signing keystore. The plan doesn't say if one exists, who owns it, or how it's stored. A panelist asking *"how do you sign the APK for distribution?"* needs an answer.
2. **Version code.** `pubspec.yaml`'s version field should be set to something defensible — e.g., `1.0.0+1` for the first production version.
3. **Distribution.** How will the APK reach the defense demo? Sideloaded onto a phone? Hosted somewhere? Both?
4. **Final analyze + test run.** Before building the release APK, run `flutter analyze` (zero warnings) and `flutter test` (all green) as the last sanity check. The plan should require this.

**Required action:** expand the release section to cover keystore signing (even if a debug-signed APK is acceptable for academic defense, state that), version stamping in `pubspec.yaml`, distribution method, and a final analyze+test gate before building.

---

## CHANGES REQUIRED — Issue 7: documentation cleanup is missing entirely

Phase 9 is the last phase. The Phase 8 review listed concrete documentation tasks that must complete before defense:

- `MASTER_CONTEXT.md` progress tracker -> all green.
- Capstone paper Chapter 4 updated to reflect staff scope (or addendum if the paper text cannot be amended).
- `schema_proposals.md` adoption-status snapshot — record what the web team accepted / edited / rejected.
- `migration_notes.md` updated with the Phase 9 release date and any final changes.

None of these are in the Phase 9 plan.

**Required action:** add a "Documentation" section to the plan listing each of the above items with concrete acceptance criteria.

---

## Two observations (not blockers)

**Observation 1 — the `pumpAndSettle` fix is correct but worth one safety note.** Replacing `pumpAndSettle()` with `pump(Duration(milliseconds: 500))` works around infinite animation loops, but it also masks real timing issues. If a screen takes 600ms to settle in production, the test will miss it. Worth one sentence: *"The 500ms duration is calibrated to current load times. If staff screens slow down in future builds, this timeout will need to be revisited."*

**Observation 2 — the Open Questions section says there are no unresolved open questions.** That's a strong claim for the final phase. There's at least one I can think of: the web team's response to `schema_proposals.md`'s three proposals (the `patients` INSERT policy, Storage RLS policies, `match_rag_documents` RPC). The previous reviews left this as an active risk. If Phase 9 doesn't address it, who does? Better to acknowledge it openly than claim no questions exist.

---

## What the revised plan needs

Submit a v2 of the plan addressing:

1. **Correct the Usability description** in ISO 25010 (Inter typography, light cream + forest-green palette).
2. **Specify ISO 25010 methodology** — who scores, what artifacts, the four load scenarios from Phase 6 review, real-device requirement for Scenarios 2 and 4.
3. **Rewrite the APK security pass** — concrete decompile tool, the four greps, what counts as pass, evidence format.
4. **Mobile/web integration test participation plan** — web team confirmation, project URL, single-operator fallback.
5. **Defense Materials section** with the Phase 7-8 punch-list items.
6. **Release build expansion** — signing, version code, distribution, final analyze+test gate.
7. **Documentation section** for `MASTER_CONTEXT.md`, paper Chapter 4, `schema_proposals.md` adoption, `migration_notes.md`.

Once these are in the revised plan, Gate B will be APPROVED and Phase 9 moves to Gate C (Build).

---

## A point of process

This is the **final phase before defense, in 3-4 weeks**. The previous five phase plans got progressively tighter as the verification standard solidified. Phase 9's plan is a step backwards in rigor compared to Phase 8 — particularly on ISO 25010 and the APK security pass. The reason matters: this is the work the defense panel will scrutinize most. The plan must specify what evidence will be produced and how.

Phase 9 does not introduce new features. It tests, hardens, and documents the existing build. That's a narrower scope than Phase 8 was — which means more time to get the evidence right. Use that time.

---

## Status & next gate

- **Gate B for Phase 9: CHANGES REQUIRED.** Revise the plan and resubmit.
- **No code work begins until Gate B is APPROVED.** Strict Gate-B enforcement from Phase 6/7/8 stands.

Send the v2 plan when ready and we will close out Gate B.
