# Antigravity Task — Hide Receptionist's Today's Queue Tab (UI Scope Reduction)

> **Task type:** UI scope reduction — no schema changes, no logic deletion.
> **Goal:** Hide the receptionist's **Today's Queue** tab from the mobile UI
> so the receptionist mobile mode becomes a documents-lookup tool only. The
> queue management surface is owned by the web team's portal.
> **Project lead decision (2026-06-22):** the mobile team and the web team
> agreed that queue management belongs exclusively to the web portal. The
> mobile receptionist no longer needs queue visibility.
>
> **Sequencing note:** This task must run AFTER the three-tab Documents view
> (Pending / Approved / Rejected) has been built, gated, and PASSed. Do NOT
> start this task while that build is in flight.

---

## What "hide" means here

The project lead chose **Implementation A: single-tab view, no Queue tab
visible at all**. The Today's Queue tab disappears entirely from the
receptionist screen. The receptionist sees only the Documents tab (which
contains the Pending / Approved / Rejected sub-tabs from the in-flight
build).

The code behind the queue tab — the widget, the provider methods, the
Realtime subscription — **stays in `lib/`**. It is unwired from the UI
only. This preserves the ability to re-enable the queue tab later
(post-defense, after a clinic operational review, or for a future
release) without rebuilding it from scratch.

The Realtime subscription **stays active**. The project lead explicitly
chose to keep it in case it becomes useful for derived UI elsewhere
later (e.g., a notification badge, a dashboard summary).

---

## Files affected (likely list — confirm by reading the actual files)

- `lib/features/staff/presentation/screens/reception_home_screen.dart` —
  remove the Queue tab from the `TabBar` and `TabBarView`; collapse
  `DefaultTabController` from `length: 2` to `length: 1`, OR remove the
  `DefaultTabController` entirely if only the Documents tab remains.
- `lib/features/staff/presentation/providers/reception_provider.dart` —
  preserve the queue-related methods (`loadQueue`, `quietFetchQueue`,
  `subscribeQueue`) and the queue list state. The Realtime subscription
  remains active per project lead decision. The UI just doesn't surface
  the data.
- `test/phase8_staff_reception_test.dart` — the RLS verification chain
  (the four split tests) MUST still pass. The queue-creation step in the
  shared test setup remains intact, because the test verifies that RLS
  permits the receptionist to transition queue status (web-portal
  action). No test changes expected, but verify.
- `test/phase9_reception_three_tab_test.dart` (the in-flight test) —
  verify the new file from the three-tab build doesn't assume a Queue tab
  is present. If it does, that's a defect to fix here.
- `test/phase9_reception_readonly_test.dart` (the prior read-only test)
  — this test verifies no action buttons render. It should still pass
  after the queue tab is hidden. Verify.

---

## Changes to make

### 1. `reception_home_screen.dart` — collapse the TabController

Replace the existing two-tab structure:

```dart
// Before (paraphrased — agent verifies actual structure)
DefaultTabController(
  length: 2,
  child: Scaffold(
    appBar: AppBar(
      bottom: TabBar(
        tabs: const [
          Tab(text: "Today's Queue"),
          Tab(text: "Documents"),
        ],
      ),
    ),
    body: TabBarView(
      children: [
        _queueTabBody(),
        _documentsTabBody(),  // three-tab nested view
      ],
    ),
  ),
);
```

With:

```dart
// After
Scaffold(
  appBar: AppBar(
    title: const Text("Reception Portal"),
    // No bottom TabBar — single content view
  ),
  body: _documentsTabBody(),  // three-tab nested view becomes the whole body
);
```

The `_queueTabBody()` method itself **stays in the file** as dead code,
with a comment header explaining why:

```dart
// Queue tab body. Currently unwired from the UI per project decision
// 2026-06-22: queue management is owned by the web portal. The widget,
// provider, and Realtime subscription are preserved in case the queue
// tab is re-enabled in a future release.
Widget _queueTabBody() {
  // ... existing code, untouched
}
```

If the dead-code lint warns about an unused method, **suppress the
warning with a comment** — do NOT delete the method. The intent is
preservation.

### 2. `reception_provider.dart` — preserve queue logic

No removal. The Realtime subscription stays active. The queue list
state stays in the provider. The provider's `loadQueue()` and
`quietFetchQueue()` methods stay. The provider keeps subscribing on
mount, even though no UI consumes the data right now.

Add a class-level doc comment to the provider explaining:

```dart
/// Reception provider for the receptionist mobile mode.
///
/// As of 2026-06-22, the Today's Queue tab is hidden from the receptionist
/// UI per joint decision with the web team. The queue list state,
/// loading methods, and Realtime subscription are preserved here so the
/// data is available for derived UI elements (notification badges,
/// summary counts) or for re-enabling the queue tab in a future release.
///
/// State changes (Mark Arrived, Approve, Reject, etc.) remain unsupported.
/// The receptionist mobile mode is fully read-only.
class ReceptionProvider extends ChangeNotifier {
  // ...
}
```

### 3. Tests

#### Existing test: `test/phase8_staff_reception_test.dart`

The four split RLS verification tests (data setup, queue arrived,
document approve, document reject) **must continue to pass**. They verify
that RLS at the database level permits the receptionist to make these
state changes — these policies serve the web portal. The mobile UI does
not expose the actions, but the RLS layer is unchanged.

**No code changes expected.** Just run the test file and confirm all
four tests still pass.

#### Existing test: `test/phase9_reception_readonly_test.dart`

This test verifies no action buttons render on the receptionist screen.
After hiding the Queue tab, this test should still pass. The Queue tab's
"Mark Arrived" button was already removed in the prior read-only fix;
hiding the entire tab is consistent with that direction.

**Action:** read the test file. If it asserts the Queue tab is *visible*
(via a Finder for "Today's Queue" text), update that assertion to verify
the tab is **not** present. If it only asserts no action buttons render,
no change needed.

#### Existing test: `test/phase9_reception_three_tab_test.dart`

If this test exists from the three-tab build, verify it doesn't assume a
parent Queue tab is present. The three-tab nested view should render
correctly as the screen's primary content.

#### NEW test: `test/phase9_reception_queue_tab_hidden_test.dart`

Create a single widget test:

- **Test:** `"ReceptionHomeScreen does not render a Today's Queue tab"`
  — pump the screen with a mock provider supplying queue entries AND
  documents. Assert that:
  - No Finder for the text "Today's Queue" returns a match.
  - No Finder for the test patient's name from the queue list returns a
    match (the queue data is loaded into the provider but not surfaced
    in any visible widget).
  - The Documents content (Pending / Approved / Rejected sub-tabs) IS
    rendered as the primary screen content.

This test guards against the queue tab being accidentally re-enabled by
a future refactor.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis still clean (or unchanged from prior baseline)
flutter analyze

# 2. The Phase 8 RLS verification chain still passes (queue logic preserved)
flutter test test/phase8_staff_reception_test.dart

# 3. The prior read-only widget test still passes
flutter test test/phase9_reception_readonly_test.dart

# 4. The three-tab widget test still passes
flutter test test/phase9_reception_three_tab_test.dart

# 5. The new queue-hidden widget test passes
flutter test test/phase9_reception_queue_tab_hidden_test.dart

# 6. Full test suite passes
flutter test

# 7. Confirm the queue tab is genuinely gone from the UI but NOT deleted
grep -rn "Today's Queue" lib/features/staff/
# Expected: matches may exist inside _queueTabBody() comment or string literal,
# but NOT in any TabBar, Tab, or TabBarView construction.

# 8. Confirm the queue logic in the provider is intact
grep -rn "subscribeQueue\|loadQueue\|quietFetchQueue" lib/features/staff/
# Expected: matches inside reception_provider.dart — the methods still exist.
```

Plus **two screenshots** from the emulator:

- `reception_after_queue_hidden_documents_view.png` — receptionist
  screen showing only the Documents content with three sub-tabs visible.
  No top-level TabBar with "Today's Queue" should be visible.
- `reception_after_queue_hidden_pending_subtab.png` — Pending sub-tab
  active to confirm the three-tab build's UI still renders correctly as
  the primary content of the receptionist screen.

---

## Out of scope for this task

- **Deleting the queue tab code.** Explicitly out of scope. Preservation
  is the architectural choice.
- **Removing the Realtime queue subscription.** Project lead decided to
  keep it active.
- **Changes to the Department or Specialist screens.** Their queue views
  remain as-is (department-scoped read-only; specialist
  cross-department read-only).
- **Schema changes.** None.
- **Web team coordination.** None — the decision is already made.

---

## Documentation updates

### `MASTER_CONTEXT.md` Constraint #12

Update to reflect the queue-tab-hidden state. Current wording (from the
read-only conversion task):

> *Mobile is read-only for ALL staff roles. Receptionist, Department
> Staff, and Medical Specialist on mobile see scoped read views and
> Realtime live updates only. State changes... are web-portal actions
> exclusively. The mobile app does NOT expose any state-change UI for
> staff roles.*

Add a sentence after the existing constraint #12 text:

> *As of 2026-06-22, the receptionist mobile screen does not surface the
> queue tab — queue management is owned by the web portal per joint
> architectural decision with the web team. The queue state, methods, and
> Realtime subscription are preserved in the receptionist provider for
> potential re-enabling or for derived UI use.*

### `klinikaid_mobile_guide_v2_staff_addendum.md` (if present)

Update the Receptionist section's "What they see on mobile" list to
remove queue references. The receptionist sees only the Documents view
(three sub-tabs).

### Defense materials note

When the screenshots are captured, the receptionist mobile screenshot
from the defense punch list should be updated to the post-hide version
(showing Documents-only). The old screenshot showing the two-tab layout
becomes stale.

---

## When complete — walkthrough should include

1. List of files modified with one-line summary per file.
2. The 8 bash command outputs above.
3. The 2 screenshots.
4. Confirmation that:
   - The Queue tab is not visible in the rendered UI.
   - The queue tab code (`_queueTabBody()`) is preserved in the file
     with explanatory comment.
   - The Realtime queue subscription is still active in the provider.
   - The Phase 8 four-test RLS verification chain still passes.
   - The Phase 9 read-only widget test still passes.
   - The three-tab widget test still passes.
   - The new queue-hidden widget test passes.
5. Constraint #12 in `MASTER_CONTEXT.md` updated with the additional
   sentence.

---

## Defense framing

When this lands, the receptionist mobile narrative becomes:

> *"The receptionist mobile mode is a documents-lookup tool. Queue
> management is owned by the web portal per architectural agreement with
> the web team — the queue is a high-velocity workflow that benefits
> from full keyboard and screen, and is the web's primary surface. The
> mobile receptionist sees the full document lifecycle (pending,
> approved, rejected from the last 30 days) with Realtime updates
> reflecting decisions made on the web. The queue state and subscription
> are preserved in the codebase for potential re-enabling but are
> unwired from the UI."*

That's the line. It acknowledges the scope reduction honestly
("preserved for potential re-enabling") while making the architectural
case ("agreement with the web team... web's primary surface"). It also
turns the Realtime preservation into a forward-looking design choice
rather than dead code.

---

## Reviewer focus at Gate D

I will verify:

- The screenshots show a single-content receptionist screen with no
  top-level TabBar.
- The Documents three-tab nested view renders as the screen's whole
  body.
- The 8 verification commands all produce the expected outputs.
- The dead code is truly preserved (greppable) — not deleted.
- The Realtime subscription is still in `subscribeQueue()` and is still
  called by the provider's `init` or constructor.
- Constraint #12 in MASTER_CONTEXT.md has the additional sentence.

This is the final scope reduction on the receptionist mobile side. After
this, the mobile staff philosophy is locked at: read-only viewing,
documents lifecycle visibility, no queue surface on receptionist mobile.
