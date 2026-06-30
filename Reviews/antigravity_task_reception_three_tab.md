# Antigravity Task — Receptionist Documents Three-Tab View (Read-Only Expansion)

> **Task type:** read-only feature expansion — no schema changes, no new
> state-change actions, no backend coordination required.
> **Goal:** Replace the receptionist's single "Pending Documents" tab with a
> nested three-tab view: **Pending / Approved / Rejected** — letting the
> receptionist look up the lifecycle status of documents from mobile without
> taking any actions.
> **Constraint:** This must NOT reintroduce any state-change affordances. The
> receptionist mobile mode remains fully read-only per the locked Constraint #12.

---

## Context for this task

After the prior bug fixes locked mobile staff mode as fully read-only, the
project lead identified a gap: the receptionist on mobile can see pending
documents but cannot look up the historical state of approved or rejected
documents. The web portal shows a kanban view with five status columns; this
mobile feature provides a more focused subset of that capability — the three
status states that actually exist in the canonical `documents.status` enum.

**The web team's "AI Verified" and "Staff Review" columns are out of scope.**
Those derive from logic that lives in the web team's code and likely depends
on fields or computed values we don't have access to. The mobile view uses
only the three canonical `documents.status` values:

- `pending`
- `approved`
- `rejected`

---

## Design specification (locked with project lead 2026-06-22)

### Tab structure

The Receptionist Home Screen has two existing top-level tabs:

```
[Today's Queue]  [Documents]            ← existing top-level (rename "Pending Documents" to "Documents")
```

Inside the **Documents** tab, add three nested sub-tabs:

```
                  [Pending]  [Approved]  [Rejected]    ← NEW nested sub-tabs
```

Each sub-tab is its own scrollable list of document cards filtered by the
matching `documents.status` value.

### Data window

- **Pending tab:** all-time (same as today's behavior — pending docs are
  unbounded but typically small).
- **Approved tab:** last 30 days only. Filter at the query layer using
  `updated_at >= now() - interval '30 days'`. Order descending by
  `updated_at`.
- **Rejected tab:** last 30 days only, same filter and ordering.

The 30-day window is enforced at the database query level, not client-side,
to keep the mobile responsive. If the query returns >100 rows in any tab,
implement pagination later — for now, no limit beyond the time window.

### Card design per tab

| Tab | Card content |
|---|---|
| **Pending** | Patient name, file name, OCR preview snippet, status badge `PENDING` (orange) |
| **Approved** | Patient name, file name, OCR preview snippet, status badge `APPROVED` (green), small text under the badge: *"Approved on YYYY-MM-DD HH:MM"* |
| **Rejected** | Patient name, file name, OCR preview snippet, status badge `REJECTED` (red), small text under the badge: *"Rejected on YYYY-MM-DD HH:MM — <rejection_reason>"* |

For the timestamp source: use `documents.updated_at` unless an explicit
`approved_at` / `rejected_at` column exists in the schema. **Confirm by
inspecting the schema before writing the query.** If the column exists, use
it; if not, use `updated_at` and note the assumption in the walkthrough.

### Read-only enforcement (CRITICAL — do not regress)

- NO action buttons on any card.
- NO tap-to-action behavior. Tapping a card opens a read-only detail modal
  showing extended info (the same modal pattern the queue tab uses), with
  ONE button: Close.
- The existing receptionist provider (which was made read-only in the
  prior task) must remain read-only. No new state-change methods.

### Empty states

Each tab needs an empty state:

| Tab | Empty state copy |
|---|---|
| Pending | *"No pending documents. New submissions will appear here."* |
| Approved | *"No approved documents in the last 30 days."* |
| Rejected | *"No rejected documents in the last 30 days."* |

Use a subtle icon (e.g., document icon, check icon, cross icon) above each
empty-state message in the muted-foreground color.

### Realtime behavior

The receptionist already subscribes to the `documents` table via the
existing Realtime subscription. **Reuse this subscription** — do NOT create
three separate subscriptions for the three tabs. The provider should:

1. Load all three lists on screen mount (one query per status, or a single
   query that returns all and partitions client-side).
2. On any Realtime UPDATE event, refresh all three lists (a doc may have
   transitioned from one status to another and the user expects all tabs
   to be consistent).

This keeps the Realtime story simple: one subscription, three derived views.

---

## Files affected (likely list — confirm by reading the actual files)

- `lib/features/staff/data/repositories/staff_queue_repository.dart` —
  expand `getPendingDocuments()` into three methods OR add filter parameters.
  See "Repository changes" below.
- `lib/features/staff/presentation/providers/reception_provider.dart` — hold
  three lists in state (`pendingDocuments`, `approvedDocuments`,
  `rejectedDocuments`) instead of just one.
- `lib/features/staff/presentation/screens/reception_home_screen.dart` —
  replace the single Documents tab body with a `DefaultTabController` of
  three nested tabs.
- `lib/features/staff/presentation/widgets/document_review_card.dart` —
  conditionally render the per-status metadata (approved-on, rejected-on +
  reason) based on the document's status.
- `test/phase8_staff_reception_test.dart` — extend the existing setup to
  also create one approved and one rejected document, so the test data set
  reflects the new view.
- New: `test/phase9_reception_three_tab_test.dart` — widget test verifying
  each tab renders only documents of the matching status.

---

## Repository changes

Update `staff_queue_repository.dart`:

### Option A (preferred — minimal API change)

Add an optional parameter to the existing method:

```dart
Future<List<Document>> getDocumentsByStatus({
  required DocumentStatus status,
  Duration? maxAge,  // null = no time limit; 30 days for approved/rejected
}) async {
  var query = _client
      .from('documents')
      .select()
      .eq('status', status.toDbValue());
  
  if (maxAge != null) {
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();
    query = query.gte('updated_at', cutoff);
  }
  
  final result = await query.order('updated_at', ascending: false);
  return result.map((row) => Document.fromJson(row)).toList();
}
```

The existing `getPendingDocuments()` can either remain as a thin wrapper
around `getDocumentsByStatus(status: DocumentStatus.pending)` or be removed
entirely if no longer used elsewhere.

### Why Option A

It uses one method with parameters rather than three nearly-identical
methods. Easier to maintain, easier to test.

---

## Provider changes

`reception_provider.dart` adds three list properties (one per status) and a
method `loadAllDocumentStatuses()` that triggers three queries in parallel
on screen mount and on Realtime events.

The existing `pendingDocuments` getter renames to align with the new naming
or stays for backward compatibility — agent's call, but maintain a clear
naming pattern across all three.

**Important:** the existing Realtime subscription stays. The Realtime
handler now calls `loadAllDocumentStatuses()` instead of just refreshing
pending. This is the simplest, most robust approach.

---

## Screen changes

`reception_home_screen.dart`:

1. Rename the second top-level tab from "Pending Documents" to "Documents".
2. The tab body for "Documents" becomes a nested `DefaultTabController`
   with three tabs: Pending, Approved, Rejected.
3. Each nested tab body is a `ListView.builder` over the corresponding
   list from the provider.
4. Each list item is a `DocumentReviewCard` with the appropriate per-status
   metadata.
5. Empty states render when the list is empty for the active tab.

The styling for nested tabs should match the existing app theme (cream
background, forest-green active tab, muted inactive tabs).

---

## Tests

### Existing test update

`test/phase8_staff_reception_test.dart` — the existing test creates a
single pending document. Extend setUp to also create:

- One additional document set to `approved` status with `updated_at`
  recently
- One additional document set to `rejected` status with `updated_at`
  recently and a `rejection_reason` value

This expands the test data set without changing the RLS verification
assertions. The four split tests (data setup, mark arrived, approve, reject)
all still pass as before.

### New widget test

Create `test/phase9_reception_three_tab_test.dart`:

- **Test 1:** *"Pending tab shows only pending documents"* — pump screen
  with a mock provider supplying 2 pending + 1 approved + 1 rejected
  documents. Activate the Pending tab. Assert exactly 2 cards render.
- **Test 2:** *"Approved tab shows only approved documents with approval
  timestamp"* — same provider data, activate Approved tab. Assert 1 card
  renders, and the card text contains "Approved on" and the formatted date.
- **Test 3:** *"Rejected tab shows only rejected documents with timestamp
  and reason"* — activate Rejected tab. Assert 1 card renders, the card
  text contains "Rejected on", the formatted date, and the rejection reason
  string.
- **Test 4:** *"All three tabs render no action buttons"* — for each tab
  in turn, assert no Finder for "Approve", "Reject", "Mark Arrived" text
  returns a match. This is the read-only regression check.
- **Test 5:** *"Empty state renders for tab with no documents"* — supply a
  provider with all three lists empty. Activate each tab in turn. Assert
  the empty-state text renders correctly per tab.

### Database integration check (optional but recommended)

If the agent has time and a real test user available, add a quick test that
queries the `documents` table directly for all three statuses against the
shared project, verifies the time window filter works correctly, and
confirms the rejection_reason column is non-null on rejected rows. This is
the kind of evidence that becomes useful for defense.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis still clean
flutter analyze

# 2. Existing receptionist tests still pass with expanded data
flutter test test/phase8_staff_reception_test.dart

# 3. New three-tab widget tests pass
flutter test test/phase9_reception_three_tab_test.dart

# 4. Full test suite still passes
flutter test

# 5. Read-only regression check — no action buttons anywhere
grep -rn "Mark Arrived\|Approve Document\|Reject Document\|markAsArrived\|approveDocument\|rejectDocument\|showRejectionDialog" lib/features/staff/

# Expected: ZERO matches in lib/features/staff/.
```

Plus **three screenshots** from the emulator, one per tab:

- `reception_pending_tab.png` — Pending sub-tab active, at least one
  pending doc visible.
- `reception_approved_tab.png` — Approved sub-tab active, at least one
  approved doc visible with "Approved on [date]" metadata.
- `reception_rejected_tab.png` — Rejected sub-tab active, at least one
  rejected doc visible with "Rejected on [date] — [reason]" metadata.

---

## Out of scope for this task

- **AI Verified and Staff Review columns** from the web view. These depend
  on logic owned by the web team that we don't have access to.
- **Five-column kanban layout**. Three tabs only.
- **State-change actions** in any form. Read-only is non-negotiable.
- **Backend schema changes**. None.
- **Web team coordination**. None required.
- **Pagination beyond the 30-day window**. The window is sufficient for
  the mobile lookup use case; if the receptionist needs older records,
  that's web-portal territory.

---

## Defense framing

When this lands, the mobile receptionist narrative gets even stronger:

> *"Mobile receptionists have full lifecycle visibility into patient
> documents — they can look up any pending, approved, or rejected
> submission from the last 30 days from anywhere in the clinic. The web
> portal remains the place for the actions themselves: approving,
> rejecting, providing rejection reasons. Mobile is the read-only
> situational-awareness tool that complements the web's
> action-taking interface. The Realtime subscription means a status
> change made on the web flips live on mobile within a second, so
> staff are never working off stale information."*

That's the line. The agent should keep this framing in mind while
building — every UI decision should reinforce **lookup + lifecycle
visibility + Realtime live updates**, never action-taking.

---

## When complete — walkthrough should include

1. The list of files modified with one-line changes per file.
2. The 5 bash command outputs above.
3. The 3 emulator screenshots.
4. Confirmation that:
   - The Realtime subscription was reused, not duplicated.
   - The 30-day filter is enforced at the database query layer.
   - The schema-column check was done (using `updated_at` or
     `approved_at`/`rejected_at` as appropriate, with the decision
     documented).
   - The existing four Phase 8 RLS-verification tests still pass.
5. Constraint #12 in `MASTER_CONTEXT.md` does NOT need to change — this
   task does not alter the read-only philosophy. Confirm no edits to that
   constraint.
6. Brief manual confirmation: signed in as receptionist on the shared
   project, opened the new Documents → Approved tab, saw an approved doc
   from the last 30 days; opened Rejected, saw a rejected doc with its
   reason visible.
