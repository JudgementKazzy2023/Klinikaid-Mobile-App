# Antigravity Task — Binary Queue Status Display Across Mobile Surfaces

> **Task type:** mobile presentation-layer fix — no schema changes, no
> backend changes, no web team coordination required.
> **Goal:** Replace the misleading "N min estimated wait" counter with a
> clean binary status display ("Now Being Called" / "Waiting in Queue")
> everywhere queue status surfaces on the mobile app.
> **Project lead decision (2026-06-23):** the patient-facing wait-time
> counter was confusing — patients being called "now" saw "0 min wait,"
> and patients in queue saw inaccurate estimates. The binary display
> conveys exactly what the patient needs to know without false precision.

---

## Context for this task

The current Live Triage Queue ("Now Calling" card) and related queue
surfaces display "N min estimated wait" alongside a status. This creates
three UX problems:

1. **Estimate is fake.** The schema has no wait-time projection logic;
   the value displayed is often `0`, `--`, or stale.
2. **Title contradicts body.** The card title "NOW CALLING" appears even
   when the patient is still `waiting`, while the body shows a non-zero
   wait time — they can't both be true.
3. **No clinical or operational benefit.** A patient who's "next" doesn't
   benefit from seeing "0 min." A patient who's tenth in line doesn't
   benefit from seeing "30 min" if the estimate isn't real.

Replacing this with a status-driven binary display fixes all three.

---

## Design decisions (locked with project lead 2026-06-23)

### Mapping `patient_queue.status` → mobile display

The schema's `patient_queue.status` enum stays unchanged. Mobile displays
it via this mapping:

| DB `status` | Card title | Card icon | Body text | Where shown |
|---|---|---|---|---|
| `waiting` | **IN QUEUE** | clock icon | "Waiting in Queue" | Active card |
| `in_progress` | **NOW CALLING** | speaker icon (existing) | "Now Being Called" | Active card |
| `completed` | (n/a) | (n/a) | (n/a) | Queue History only, status badge "COMPLETED" — unchanged |

The Queue History section preserves its existing display — it shows the
final outcome (`COMPLETED`), which is appropriate for history.

### Color tokens

- **NOW CALLING** title and "Now Being Called" body: forest green
  (existing color for active state)
- **IN QUEUE** title and "Waiting in Queue" body: muted-foreground or
  the existing inactive-state color from the design system. Should look
  visually subordinate to NOW CALLING — patients should understand at
  a glance which state is "more urgent."

### Priority badge unchanged

The URGENT / ROUTINE / EMERGENCY badge (from `patient_queue.priority`)
remains visible in both states. It's a separate axis of information
(priority severity) and doesn't change with status.

### Wait-time display removed entirely

The "N min estimated wait" or "Est. Wait: -- mins" line is removed from
all four surfaces. No fallback, no replacement label. The new binary
body text replaces it functionally.

---

## Four mobile surfaces affected

### Surface 1 — Patient Live Triage Queue ("Now Calling" card)

File: `lib/features/queue/presentation/screens/queue_screen.dart` (or
wherever the patient's queue-active card lives).

**Before:**
```
🔊 NOW CALLING            [URGENT]
ECG
0 min estimated wait
```

**After (status = waiting):**
```
🕐 IN QUEUE              [URGENT]
ECG
Waiting in Queue
```

**After (status = in_progress):**
```
🔊 NOW CALLING            [URGENT]
ECG
Now Being Called
```

### Surface 2 — Patient Dashboard Queue Summary tile

File: `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
(the "Active Queue Summary" tile from test 2-2).

If the tile currently shows an estimated wait time, replace it with the
binary status text using the same mapping. The tile is smaller than the
Live Triage card; just one line of binary status text is appropriate:

```
[Active Queue Summary]
Department: ECG
Status: Now Being Called
Priority: URGENT
```

(Or whatever the existing layout supports — match the existing visual
pattern of the tile, just swap the wait-time line for the binary status.)

### Surface 3 — Department staff Department Queue cards

File: `lib/features/staff/presentation/widgets/queue_entry_card.dart`
or `lib/features/staff/presentation/screens/department_home_screen.dart`.

The current card shows:
```
[Patient Name]               [#queue_id]
[Department]  [PRIORITY]  [In Progress]
Est. Wait: -- mins      Arrived: HH:MM
```

The "Est. Wait: -- mins" line is removed. The card becomes:
```
[Patient Name]               [#queue_id]
[Department]  [PRIORITY]  [Status binary label]
Arrived: HH:MM
```

Where `[Status binary label]` is either "WAITING" or "NOW BEING CALLED"
(matching the patient-side binary text but in upper-case to fit the
existing badge style).

Note: the existing "In Progress" badge is what's currently shown for
`status='in_progress'`. The choice between displaying "NOW BEING CALLED"
(matching patient-side language) vs "IN PROGRESS" (matching staff-side
operational language) is a UX decision. **Recommended: use "NOW
BEING CALLED" on the patient side and "IN PROGRESS" on the staff side**
— the patient cares about being-called-now-vs-waiting; the staff cares
about workflow state. Different audiences, different vocabularies.

For waiting status, both surfaces use the same word: "WAITING" (staff
badge) / "Waiting in Queue" (patient body text).

### Surface 4 — Department staff queue detail modal

File: `lib/features/staff/presentation/screens/department_home_screen.dart`
(the `_showQueueDetails` modal that opens on tap).

Remove any "Est. Wait" row from the modal. The Status row in the modal
should read "WAITING" or "IN PROGRESS" matching the card. No binary
patient-facing text needed in this modal — it's a staff view.

---

## Files affected (likely list — confirm by reading the actual files)

- `lib/features/queue/presentation/screens/queue_screen.dart` — patient
  Live Triage active card (Surface 1)
- `lib/features/dashboard/presentation/screens/dashboard_screen.dart` —
  patient dashboard Queue Summary tile (Surface 2)
- `lib/features/staff/presentation/widgets/queue_entry_card.dart` —
  department queue card (Surface 3)
- `lib/features/staff/presentation/screens/department_home_screen.dart`
  — department detail modal (Surface 4)
- `lib/core/utils/queue_status_formatter.dart` (NEW) — shared helper
  for the status-to-label mapping
- `test/phase9_queue_binary_status_test.dart` (NEW) — unit tests for
  the formatter

---

## Implementation guidance

### Create a shared formatter helper

Encapsulate the mapping in one place so all four surfaces use the same
logic:

```dart
// lib/core/utils/queue_status_formatter.dart

enum QueueStatusDisplay {
  waiting,
  inProgress,
  completed,
}

class QueueStatusFormat {
  final String patientCardTitle;     // "IN QUEUE" / "NOW CALLING"
  final String patientBodyText;      // "Waiting in Queue" / "Now Being Called"
  final String staffBadgeLabel;      // "WAITING" / "IN PROGRESS"
  final IconData icon;               // Icons.access_time / Icons.volume_up
  final Color color;                 // muted / forest-green primary
  
  const QueueStatusFormat({
    required this.patientCardTitle,
    required this.patientBodyText,
    required this.staffBadgeLabel,
    required this.icon,
    required this.color,
  });
}

QueueStatusFormat formatQueueStatus(QueueStatus status, AppTheme theme) {
  switch (status) {
    case QueueStatus.waiting:
      return QueueStatusFormat(
        patientCardTitle: 'IN QUEUE',
        patientBodyText: 'Waiting in Queue',
        staffBadgeLabel: 'WAITING',
        icon: Icons.access_time,
        color: theme.colors.mutedForeground,
      );
    case QueueStatus.inProgress:
      return QueueStatusFormat(
        patientCardTitle: 'NOW CALLING',
        patientBodyText: 'Now Being Called',
        staffBadgeLabel: 'IN PROGRESS',
        icon: Icons.volume_up,
        color: theme.colors.primary,
      );
    case QueueStatus.completed:
      return QueueStatusFormat(
        patientCardTitle: 'COMPLETED',
        patientBodyText: 'Completed',
        staffBadgeLabel: 'COMPLETED',
        icon: Icons.check_circle,
        color: theme.colors.success ?? theme.colors.primary,
      );
  }
}
```

(Adjust class/enum/import structure to match the project's existing
conventions for theme access, icon usage, and color tokens.)

### Apply to all four surfaces

Each surface calls `formatQueueStatus(entry.status, theme)` to get the
formatter object, then renders the appropriate fields. This keeps the
display logic out of widget files and makes future status enum additions
trivial.

---

## Tests

### New unit tests — `test/phase9_queue_binary_status_test.dart`

Cover the formatter directly:

1. **waiting status → IN QUEUE / Waiting in Queue / WAITING / clock icon / muted color**
2. **in_progress status → NOW CALLING / Now Being Called / IN PROGRESS / speaker icon / primary color**
3. **completed status → COMPLETED everywhere / check icon / success color**

These are simple mapping tests — should be quick to write and run.

### Widget tests (extend existing or new)

Extend the patient queue widget test and the department widget test:

- **Patient Live Triage card with `waiting` status:** assert finder for "IN QUEUE" returns a match; assert finder for "Waiting in Queue" returns a match; assert finder for any "min estimated wait" text returns NO matches (regression guard).
- **Patient Live Triage card with `in_progress` status:** assert finder for "NOW CALLING" returns a match; finder for "Now Being Called" returns a match.
- **Department queue card with `waiting` status:** assert finder for "WAITING" badge; finder for "Est. Wait" returns NO match.
- **Department queue card with `in_progress` status:** assert finder for "IN PROGRESS" badge.

The "no match" assertions are the regression guards — they ensure no
remnant wait-time text accidentally renders.

### Existing tests

Phase 6's `phase6_records_queue_test.dart` covers the queue provider and
RLS layer — unchanged. Should still pass.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis clean
flutter analyze

# 2. New formatter unit tests pass
flutter test test/phase9_queue_binary_status_test.dart

# 3. Existing queue tests still pass (no regressions)
flutter test test/phase6_records_queue_test.dart

# 4. Full suite passes
flutter test

# 5. Confirm wait-time strings are gone from active UI files
grep -rn "estimated wait\|Est. Wait\|min wait" lib/features/queue/ lib/features/dashboard/ lib/features/staff/

# Expected: ZERO matches in active UI code. (Matches in comments or
# preserved dead-code helper methods are acceptable; matches in any
# rendered widget tree are NOT.)
```

Plus **four screenshots** from the emulator:

- `queue_patient_waiting.png` — patient Live Triage Queue while status is
  `waiting`. Card title "IN QUEUE" with clock icon. Body "Waiting in
  Queue". Priority badge visible.
- `queue_patient_now_calling.png` — patient Live Triage Queue while
  status is `in_progress`. Card title "NOW CALLING" with speaker icon.
  Body "Now Being Called". Priority badge visible.
- `queue_dashboard_tile.png` — patient Dashboard with the Queue Summary
  tile rendering the binary status (any state acceptable).
- `queue_department_card.png` — department staff queue card showing the
  binary status badge ("WAITING" or "IN PROGRESS") with NO wait-time
  line.

---

## Out of scope

- **Schema changes.** Not touching the `patient_queue.status` enum or
  any other column.
- **Web team coordination.** The web app handles its own queue display.
  Mobile changes don't propagate to web.
- **Removing other queue-related fields.** Queue ID, arrival timestamp,
  priority, department — all retained as today.
- **Patient queue position numbering.** No "you are 3rd in line" feature
  is being added. The binary display is intentional — no false precision.
- **Staff actions on the queue.** Already locked at read-only mobile.

---

## Defense framing

When this lands, the queue UX narrative becomes:

> *"The patient mobile queue display was originally showing 'N min
> estimated wait' alongside the patient's status. Two issues with that:
> first, the underlying schema has no wait-time projection logic, so the
> values were misleading (often 0 or stale). Second, the card title and
> body could contradict each other — 'NOW CALLING' with '0 min wait'
> isn't coherent. We resolved both by adopting a binary status display:
> patients see either 'IN QUEUE — Waiting in Queue' or 'NOW CALLING —
> Now Being Called' based on the actual `patient_queue.status` value.
> Card titles, icons, and body text all derive from one shared formatter,
> keeping the mapping consistent across the patient Live Triage screen,
> dashboard tile, and department staff views. The change is purely
> presentation-layer; the database schema is unchanged."*

That's the defense story. Honest, principled, addresses why the change
was made and what was preserved (the schema, the RLS, the role-aware
routing).

---

## When complete — walkthrough should include

1. List of files modified with one-line changes per file.
2. The 5 bash command outputs above.
3. The 4 screenshots.
4. Confirmation that:
   - The `QueueStatusFormat` helper is the single source of truth for
     status display.
   - The patient surfaces use the patient-vocabulary fields
     (`patientCardTitle`, `patientBodyText`).
   - The staff surfaces use the staff-vocabulary field
     (`staffBadgeLabel`).
   - Realtime UPDATE on `patient_queue.status` still propagates to all
     four surfaces (manual verification: update a queue row's status via
     SQL editor, watch all open mobile screens reflect the change).
5. Brief manual verification: signed in as a patient and a department
   staff side-by-side, queue status changes from `waiting` to
   `in_progress` via Supabase SQL editor — both surfaces flip from the
   waiting display to the in_progress display within ~1 second.
