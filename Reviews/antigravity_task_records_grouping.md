# Antigravity Task — Group Multi-Parameter Records in Patient Mobile Records View

> **Task type:** mobile presentation-layer bug fix — no schema changes, no
> web team coordination required.
> **Goal:** Fix a defect in the patient's "My Medical Records" mobile screen
> where a single logical lab/imaging result with multiple parameters
> (e.g., a Leg X-ray with both "Findings" and "Impression") renders as
> separate cards instead of one consolidated card matching the web portal's
> display.

---

## Context for this task

The `department_records` table stores each test parameter as a separate row:
the schema has a flat `test_name` / `test_value` shape. When a technician
enters multiple parameters for a single examination (e.g., Findings and
Impression for one X-ray), the web app **inserts two rows**, then **groups
them visually** in the records-viewer as one card with both parameters
displayed side-by-side.

The mobile app doesn't apply this grouping. It renders every row as a
separate card. Result: one logical X-ray result appears as TWO cards on
the mobile patient's records screen (see attached bug report screenshots
from 2026-06-23).

This is a **presentation-layer mismatch**, not a schema issue. The fix
lives entirely in the mobile records feature — the data is correct, just
the display is wrong.

---

## Bug evidence (from the project lead's bug report)

**Web display (Image 1 in bug report):** ONE card titled "Leg X-ray" for
patient Victor Wembanyama, with both Findings ("Torn Achilles Tendon") and
Impression (full clinical paragraph) shown side-by-side. One technician
notes section. One NORMAL badge. One timestamp.

**Mobile display (Images 2 and 4):** TWO separate cards on the "My Medical
Records" screen. Both titled "Leg X-ray". Both at the same date
(2026-06-23 09:22). Both NORMAL.

**Mobile detail modal (Image 3):** Tapping one card shows TEST NAME =
"Impression", TEST VALUE = the paragraph. The second card is presumably
TEST NAME = "Findings".

---

## Design decisions (locked with project lead 2026-06-23)

The fix applies these specific rules:

### Grouping key
Group `department_records` rows by:
```
(patient_id, department, date_trunc('5 minutes', recorded_at))
```

The 5-minute bucket is chosen for robustness — it catches all rows the web
inserts during a single technician "save" action while being well shorter
than any realistic interval between two separate tests on the same patient
in the same department. **Do NOT use exact-microsecond match** (won't
group anything) or minute-truncation (too tight if the web's clock drifts).

The truncation can be done client-side in Dart after reading the rows:

```dart
DateTime _truncateToFiveMinutes(DateTime t) {
  final minutes = (t.minute ~/ 5) * 5;
  return DateTime(t.year, t.month, t.day, t.hour, minutes);
}
```

Then group by `(patient_id, department, _truncateToFiveMinutes(recorded_at))`.

### Card title

For grouped cards, the title is **Department + Date**, e.g.:
- `"Imaging — 2026-06-23"`
- `"Laboratory — 2026-06-21"`

This is what the web semantically intends and avoids lying about the data
(the schema's `test_name` column isn't actually the examination name —
it's the parameter name, like "Findings" or "Impression").

Department naming: use the `department` column value with proper casing.
Convert `"imaging"` → `"Imaging"`. The departments to handle: laboratory,
imaging, ecg, ultrasound (per the canonical schema enum).

Date format: `YYYY-MM-DD` only (no time). The detail modal can show full
timestamps if needed.

### Status badge (worst-case wins)

If grouped rows have different `reference_status` values, the badge shown
on the card follows clinical convention:

```
priority: CRITICAL > INCONCLUSIVE > NORMAL
```

If ANY parameter is `critical`, badge shows CRITICAL (red). Else if any
is `inconclusive`, badge shows INCONCLUSIVE (cream). Else badge shows
NORMAL (green).

Implementation:

```dart
ReferenceRangeStatus _aggregateStatus(List<DepartmentRecord> records) {
  if (records.any((r) => r.referenceStatus == ReferenceRangeStatus.critical)) {
    return ReferenceRangeStatus.critical;
  }
  if (records.any((r) => r.referenceStatus == ReferenceRangeStatus.inconclusive)) {
    return ReferenceRangeStatus.inconclusive;
  }
  return ReferenceRangeStatus.normal;
}
```

### Detail modal layout (stacked sections)

Tapping a grouped card opens the existing detail modal. The modal renders
**one labeled section per parameter**, stacked vertically:

```
Imaging — 2026-06-23  [NORMAL]
─────────────────────────────
Department: IMAGING

Findings
  Torn Achilles Tendon

Impression
  Weak Plantar Flexion: Significant weakness or
  inability to push the foot downward (e.g., pressing
  a gas pedal) or stand on the toes. Increased Passive
  Dorsiflexion: The ankle has more upward flexibility
  when gently manipulated compared to the uninjured
  side.

Technician Notes
  Rest for the whole Season

Close
```

Each parameter section has the parameter name as a small header (from
`test_name`) and the value as the body (from `test_value`). Technician
notes (`department_records.notes`) appear once per grouped card — if
multiple grouped rows have notes, concatenate them with line breaks
(rare case; usually only one row has notes).

### Empty / single-parameter case

If a group has only one row (single-parameter test, e.g., a Hemoglobin
result), display behavior is unchanged from today. The grouping logic
still wraps it in a group-of-one and renders identically to the previous
single-row card design. **Do NOT make the single-parameter case look
different from before.** Backward visual compatibility.

---

## Files affected (likely list — confirm by reading the actual files)

- `lib/features/records/presentation/providers/records_provider.dart`
  (or wherever the records list state is maintained) — add a grouping
  step after fetching rows from the repository.
- `lib/features/records/presentation/screens/records_screen.dart` — the
  list builder now iterates over **grouped records**, not raw rows.
- `lib/features/records/presentation/widgets/record_card.dart` (or
  equivalent) — accept a group of rows instead of a single row, render
  the consolidated card.
- `lib/features/records/presentation/widgets/record_detail_modal.dart`
  (or equivalent) — render stacked parameter sections.
- A new helper file is fine:
  `lib/features/records/domain/record_grouper.dart` — encapsulates the
  grouping rules so they're independently testable.
- New: `test/phase9_records_grouping_test.dart` — unit tests for the
  grouping logic.

---

## Implementation guidance

### 1. Domain model — `GroupedRecord`

Create a new domain class that wraps a list of `DepartmentRecord` rows
sharing the grouping key:

```dart
class GroupedRecord {
  final String patientId;
  final String department;
  final DateTime bucketStart;  // truncated recorded_at (5-min bucket)
  final List<DepartmentRecord> records;  // 1+ rows
  
  String get displayTitle => 
    '${_capitalize(department)} — ${_formatDate(bucketStart)}';
  
  ReferenceRangeStatus get aggregateStatus => 
    _aggregateStatus(records);
  
  String get aggregatedNotes => records
    .map((r) => r.notes)
    .where((n) => n != null && n.trim().isNotEmpty)
    .join('\n');
  
  // helper for the single-row case (preserves backward compat)
  bool get isSingleParameter => records.length == 1;
}
```

### 2. Grouping function

```dart
List<GroupedRecord> groupRecords(List<DepartmentRecord> raw) {
  // Stable order: most recent first
  raw.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  
  final Map<String, List<DepartmentRecord>> buckets = {};
  for (final r in raw) {
    final bucket = _truncateToFiveMinutes(r.recordedAt);
    final key = '${r.patientId}|${r.department}|${bucket.toIso8601String()}';
    buckets.putIfAbsent(key, () => []).add(r);
  }
  
  final groups = buckets.entries.map((entry) {
    final list = entry.value;
    final first = list.first;
    return GroupedRecord(
      patientId: first.patientId,
      department: first.department,
      bucketStart: _truncateToFiveMinutes(first.recordedAt),
      records: list,
    );
  }).toList();
  
  // Sort groups by most recent bucket first
  groups.sort((a, b) => b.bucketStart.compareTo(a.bucketStart));
  return groups;
}
```

### 3. Provider integration

The provider that today exposes `List<DepartmentRecord> records` should
now expose `List<GroupedRecord> groupedRecords`. The raw records list can
either be removed or kept private depending on whether anything else
reads it.

### 4. UI integration

The `records_screen.dart` ListView builder iterates over
`groupedRecords` instead of raw records. The card widget accepts a
`GroupedRecord` and renders accordingly. The detail modal accepts a
`GroupedRecord` and renders one section per row in `records`.

---

## Tests

### New unit tests — `test/phase9_records_grouping_test.dart`

Cover these cases:

1. **Single row groups alone.** One `department_records` row → one group
   with one record. `displayTitle` correct. `aggregateStatus` matches the
   row's status.
2. **Two rows close in time, same patient/department, group together.**
   Two rows 2 seconds apart with `test_name = "Findings"` and `"Impression"`
   → ONE group with two records. `displayTitle` shows department + date.
3. **Two rows >5 minutes apart, same patient/department, do NOT group.**
   Two rows 6 minutes apart → TWO groups. Each group has one record.
4. **Two rows close in time, same patient, DIFFERENT departments, do NOT
   group.** Laboratory + Imaging entries at the same minute → TWO groups.
5. **Worst-case status wins.** Group with three records: one NORMAL, one
   INCONCLUSIVE, one CRITICAL → group's `aggregateStatus` is CRITICAL.
6. **All-NORMAL group → NORMAL.** Status fallthrough.
7. **All-INCONCLUSIVE group → INCONCLUSIVE.** Status fallthrough.
8. **Notes aggregation.** Group with one notes value and one null notes
   → `aggregatedNotes` returns the one populated note (no leading/trailing
   blank line).
9. **Notes aggregation, both populated.** Group with two notes → joined
   with newlines.
10. **5-minute bucket alignment.** Row at 09:22:13 and row at 09:24:58
    should fall in the same 5-minute bucket (09:20-09:25). Verify the
    bucket math.
11. **Stable ordering.** Groups returned with most-recent bucket first;
    within a group, rows ordered by `created_at` ascending (so "Findings"
    appears before "Impression" if that was the insert order on the web).

### Widget tests (extension of existing or new)

If `records_screen.dart` has widget tests, extend them with:

- **Test: "Two same-bucket rows render as one card."** Mock provider
  supplies two `DepartmentRecord` rows with the same
  patient/department/bucket. Pump the screen. Assert exactly ONE
  RecordCard finder.
- **Test: "Grouped card detail modal shows both parameters."** Tap the
  card. Assert the modal contains both `test_name` headers (e.g., both
  "Findings" and "Impression" text are findable).
- **Test: "Single-row group renders unchanged."** One-row group renders
  with the same visual appearance as before the fix (backward compat).

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis clean
flutter analyze

# 2. New grouping unit tests pass
flutter test test/phase9_records_grouping_test.dart

# 3. Existing records tests still pass (no regressions)
flutter test test/phase6_records_queue_test.dart

# 4. Full test suite passes
flutter test
```

Plus **three screenshots** from the running emulator:

- `records_before_two_cards.png` — already exists from the bug report
  (Image 2). Reference it.
- `records_after_one_grouped_card.png` — same patient, same data, but now
  showing ONE card titled "Imaging — 2026-06-23" with the NORMAL badge.
- `records_after_grouped_detail_modal.png` — the modal opened from the
  grouped card showing both "Findings" and "Impression" as stacked
  sections, plus technician notes.

---

## Out of scope

- **Schema changes.** Not touching `department_records` table structure.
- **Web team coordination.** Not changing the web app's behavior. Mobile
  adapts.
- **Adding a `record_group_id` column.** Out of scope. We group
  implicitly by composite key.
- **Changing how rows are inserted.** Insertion logic is web-side and
  unchanged.
- **Performance optimization.** Grouping happens client-side on a list
  that should never exceed dozens of records per patient. No pagination
  or virtualization changes needed.

---

## Defense framing

When this lands, the records-display narrative becomes:

> *"Lab and imaging results in the canonical schema use a flat row-per-
> parameter structure to support test-types that have arbitrary numbers
> of parameters. The mobile app applies presentation-layer grouping by
> (patient, department, 5-minute bucket) to consolidate parameters from
> a single examination into one card view — matching the web portal's
> visual semantics. The aggregation chooses the worst-case status across
> parameters to surface clinical priority correctly, and the detail
> modal renders each parameter as its own labeled section."*

That's the answer to *"why does mobile group records?"* — clinical
correctness AND alignment with the web team's display.

---

## When complete — walkthrough should include

1. List of files modified with one-line changes per file.
2. The 4 bash command outputs.
3. The 3 screenshots (before/after card view + after detail modal).
4. Confirmation that the `groupRecords` function is correctly placed
   (either domain layer or as a helper) so it's independently testable.
5. Confirmation that single-parameter records still render identically
   to before (no visual regression for the common case).
6. Confirmation that Realtime UPDATE/INSERT events still refresh the
   grouped view correctly (Realtime delivers raw rows; the grouping step
   re-runs on each refresh).
7. Brief manual verification: sign in as a real patient with at least
   one multi-parameter record on the shared project, confirm the
   grouping renders correctly in the emulator.
