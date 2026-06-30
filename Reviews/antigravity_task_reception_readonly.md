# Antigravity Task — Receptionist Mobile to Read-Only (Bug Fix / Scope Tightening)

> **Task type:** scope tightening + UI removal — no new features, no schema changes.
> **Goal:** Make the receptionist mobile mode **fully read-only**, completing the
> mobile-staff-as-viewing-tool architectural decision. This finalizes the same
> pattern already applied to department staff in the previous bug fix task.
> **Project lead decision (2026-06-22):** mobile staff mode is a viewing tool.
> All state-change actions move to the web portal exclusively.

---

## Context for this task

The Phase 8 walkthrough originally approved three receptionist state-change
actions on mobile:

1. Mark queue entry arrived (`patient_queue.status` → `in_progress`)
2. Approve document (`documents.status` → `approved`)
3. Reject document with reason (`documents.status` → `rejected`, with
   `rejection_reason`)

Following the department-staff read-only change, the project lead has decided
that **all three mobile staff roles** (receptionist, department staff,
specialist) should be view-only. Web is the source of truth for all clinical
state changes.

Same architectural principle as Bug 1 of the previous task: the **database
layer (RLS) continues to permit the actions** — those policies serve the web
portal. We are removing only the **mobile UI exposure** of these actions.

---

## Scope of changes

### What to remove from the mobile UI

1. **Mark Arrived button** on the queue tab of `reception_home_screen.dart`.
2. **Approve button** on `documents` review cards.
3. **Reject button** (and the slide-up rejection-reason dialog) on `documents`
   review cards.
4. **Any UI affordance that triggers a state change** on the receptionist's
   side of the mobile app.

### What to preserve

1. **The queue list view** — the receptionist still sees today's queue with
   all entry details (patient name, department, priority, status, arrival
   time, triage notes via the formatter).
2. **The documents review tab** — but renamed to **"Pending Documents"** or
   similar, indicating it's a viewing list of items awaiting web-portal
   review.
3. **The detail modal** — tap on any queue entry or document still opens the
   full detail view (already read-only).
4. **The `StaffQueueRepository` methods** — keep `updateQueueStatus` and
   `updateDocumentStatus` intact. They are still used by the database layer
   to verify RLS works correctly. They are no longer called from the
   `ReceptionProvider`.
5. **The rejection-reason chip widget code** — can be left in the codebase
   but unreferenced, in case it's revived for the web flow on mobile later.
   Alternatively, delete it. Project lead's choice; default to deleting it
   to keep `lib/` clean.
6. **Realtime subscriptions** — the receptionist still subscribes to
   `patient_queue` and `documents` Realtime channels so the view updates
   live as the web portal makes changes. This is the whole point of the
   read-only mobile experience.

---

## Files affected (likely list — confirm by reading the actual files)

- `lib/features/staff/presentation/screens/reception_home_screen.dart` —
  remove Mark Arrived, Approve, Reject UI elements.
- `lib/features/staff/presentation/providers/reception_provider.dart` —
  remove provider methods that call `updateQueueStatus` and
  `updateDocumentStatus`. Keep Realtime subscriptions and read methods.
- `lib/features/staff/presentation/widgets/document_review_card.dart` —
  remove action buttons; rename to `document_view_card.dart` if appropriate.
- `lib/features/staff/presentation/widgets/queue_entry_card.dart` — already
  has the `showActionButtons` parameter from the department fix. The
  receptionist screen now passes `showActionButtons: false`.
- `lib/features/staff/presentation/widgets/rejection_reason_dialog.dart`
  (if it exists) — delete the file.
- `test/phase8_staff_reception_test.dart` — see "Tests" section below.

---

## Changes to make

### 1. UI changes

**`reception_home_screen.dart`:**
- Remove the Mark Arrived button from the queue tab.
- Pass `showActionButtons: false` to `QueueEntryCard` (parameter already
  exists from the department fix).
- Remove the Approve and Reject buttons from the documents tab cards.
- Remove the slide-up rejection-reason dialog code.
- Remove any imports that become unused.

**`document_review_card.dart` (or `document_view_card.dart` after rename):**
- Strip action buttons.
- The card still shows: patient name, document filename, document type, OCR
  preview snippet, current status badge (`pending` / `approved` / `rejected`).
- The current status badge is the **important addition** — since the
  receptionist can no longer take action, the badge makes clear what state
  the document is in from the web portal's perspective.

### 2. Provider changes

**`reception_provider.dart`:**
- Remove any method named `markAsArrived`, `approveDocument`,
  `rejectDocument`, or similar that calls a state-changing repository method.
- The provider remains responsible for:
  - Fetching today's queue (read)
  - Fetching pending documents (read)
  - Maintaining Realtime subscriptions (read)
  - Exposing loading/error states (read)

### 3. Test changes — IMPORTANT, treat with care

`test/phase8_staff_reception_test.dart` currently contains a verification
chain (Steps 4, 5, 6) that exercises the three state changes via the
`StaffQueueRepository`. These tests **must NOT be deleted** — they verify
that RLS still permits these actions, which is what serves the web portal.

Apply the same pattern used in the department fix:

- Keep the test file's outer group name as-is:
  `'Phase 8: Receptionist Portal Integration & Verification Chain'`.
- Rename **only the three transition-specific test cases** to make clear
  that these are RLS-layer verifications, not mobile-UI verifications:

  | Old name (likely) | New name |
  |---|---|
  | `"Receptionist can mark patient queue status as arrived (in_progress)"` | `"RLS permits receptionist to mark queue arrived (web portal action; not exposed on mobile UI)"` |
  | `"Receptionist can approve a pending document"` | `"RLS permits receptionist to approve documents (web portal action; not exposed on mobile UI)"` |
  | `"Receptionist can reject a pending document with reason"` | `"RLS permits receptionist to reject documents with reason (web portal action; not exposed on mobile UI)"` |

- Add a code comment above each renamed test explaining the
  mobile/web separation, matching the comment added to
  `phase8_staff_department_test.dart` during the previous fix.

### 4. New widget test

Create `test/phase9_reception_readonly_test.dart` with the test:

- `"ReceptionHomeScreen does not render Mark Arrived, Approve, or Reject
  buttons"` — pump the widget with a mock provider producing one queue entry
  and one pending document. Assert that no Finder for text "Mark Arrived",
  "Approve", or "Reject" returns a match.

### 5. Documentation updates

- **`MASTER_CONTEXT.md`** Constraint #12 needs updating again. Replace the
  current bullets with:

  ```
  12. **Mobile is read-only for ALL staff roles.** Receptionist, Department
      Staff, and Medical Specialist on mobile see scoped read views and
      Realtime live updates only. State changes — Mark Arrived, Approve,
      Reject, Queue Transition, Record Entry — are web-portal actions
      exclusively. The mobile app does NOT expose any state-change UI for
      staff roles. The patient role retains full read+write capabilities on
      mobile (document submission, chatbot, consent, profile).
  ```

- **The mobile guide v2 staff addendum** (if it exists in the workspace
  at `/home/claude/klinikaid/klinikaid_mobile_guide_v2_staff_addendum.md` or
  equivalent) — update the per-role sections to remove the bulleted
  permitted state-change actions. Leave only the "view" bullets.

- **`docs/05-features.md`** (when the GitHub documentation task is run) —
  the Receptionist, Department Staff, and Specialist sections should all
  list zero state-change actions in the Permitted column. All state changes
  go in the Web-portal column.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis still clean (lint count should be unchanged or lower)
flutter analyze

# 2. The renamed Phase 8 receptionist tests still pass (proving RLS works)
flutter test test/phase8_staff_reception_test.dart

# 3. The new widget test passes (proving no action buttons render)
flutter test test/phase9_reception_readonly_test.dart

# 4. Full test suite still passes
flutter test

# 5. Grep confirming no lingering receptionist action references in the UI
grep -rn "Mark Arrived\|Approve Document\|Reject Document\|markAsArrived\|approveDocument\|rejectDocument\|showRejectionDialog" lib/features/staff/

# Expected: ZERO matches in lib/features/staff/ (the repository method
# names like updateQueueStatus and updateDocumentStatus may remain in the
# repository file; that's correct because they serve the receptionist's
# RLS-permitted database operations from server-side / test contexts).

# 6. Grep confirming the rejection dialog widget file is gone (if deleted)
ls lib/features/staff/presentation/widgets/ | grep -i rejection
# Expected: no matches if the file was deleted
```

Plus **two screenshots** from the running emulator:

- `receptionist_after_no_arrival_button.png` — queue tab showing entries
  with NO Mark Arrived button visible.
- `receptionist_after_no_doc_actions.png` — documents tab showing review
  cards with NO Approve/Reject buttons; status badges visible instead.

---

## Out of scope for this task

- **Backend changes.** None. RLS policies stay exactly as they are.
- **Schema changes.** None.
- **Patient-side changes.** Patients keep document submission, chatbot,
  consent, profile updates, all of it. This task is staff-side only.
- **Specialist-side changes.** Specialist is already read-only since Phase 8.
  No changes there.
- **Mobile/web Realtime sync changes.** The receptionist's mobile screen
  must continue subscribing to Realtime so they see live updates from web
  actions. Verify this works after removing the actions: change a queue
  status from the web portal, watch the mobile receptionist screen update
  live without a refresh.

---

## When complete — walkthrough should include

1. The list of files modified, with one-line changes per file.
2. The six bash command outputs above.
3. The two screenshots.
4. Confirmation that:
   - `staff_queue_repository.updateQueueStatus` is **preserved**.
   - `staff_queue_repository.updateDocumentStatus` is **preserved**.
   - All Realtime subscriptions still work (manual verification on emulator).
   - The Phase 8 receptionist tests' RLS verifications still pass after
     rename.
5. Confirmation that the rejection-reason dialog file was deleted (or kept
   intentionally, with reason).
6. Constraint #12 in `MASTER_CONTEXT.md` updated.
7. A note about what the staff addendum guide needs updating to reflect.

---

## Reviewer focus at Gate D

I will verify:

- All three "Mark Arrived / Approve / Reject" UI elements are gone from the
  rendered screens.
- The Phase 8 receptionist test file still PASSes after rename with the
  same database verification steps.
- The new widget test confirms no action buttons render.
- The Realtime subscription continues to work — meaning a web-side change
  flips the mobile receptionist screen live.
- No regressions in patient-side functionality (Phase 0-6 features still
  work).
- The grep returns clean.
- The screenshots match the expected after-state.
- The status badges on document cards are clearly visible — replacing the
  removed action buttons with something useful (status visibility) is the
  defense story.

---

## Defense framing (for the agent's reference)

When this lands, the mobile staff narrative becomes:

> *"Mobile staff mode is a deliberate viewing tool. Receptionists, department
> staff, and medical specialists use the mobile app to stay aware of clinic
> status from anywhere — Realtime updates let them see queue progressions
> and document reviews live as they happen on the web. All clinical actions
> happen on the web portal where the keyboard, screen, and full workflow
> context support the work better. This avoids mobile/web conflicts and
> keeps the audit trail clean."*

That's the line. The agent should keep this framing in mind during the
build — when the agent encounters a place where it might be tempted to
"helpfully" preserve an action, the architecture says no.
