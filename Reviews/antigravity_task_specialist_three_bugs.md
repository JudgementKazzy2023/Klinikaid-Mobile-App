# Antigravity Task — Medical Specialist Mobile: Three Bug Fixes

> **Task type:** mobile bug fix bundle — no schema changes, no web team
> coordination, two of the three fixes reuse existing helpers from prior
> post-Phase-9 work.
> **Goal:** Fix three defects in the medical specialist mobile mode:
> 1. Patient search fails on full names with spaces
> 2. Patient History timeline duplicates multi-parameter records
> 3. Long clinical text overflows the card horizontally
> **Constraint:** specialist mobile mode remains fully read-only per
> Constraint #12. No state-change UI is introduced.

---

## Context for this task

The medical specialist mobile mode (M9 in the v4 checklist) was the
earliest-stable staff role — read-only since Phase 8 — and received no
post-Phase-9 fixes until now. During final test-cycle execution the
project lead found three defects on the specialist surface:

**Bug 1 — Patient Search breaks on spaces.** Typing "Vic" finds Victor
Wembanyama. Typing "Victor Wem" returns "No patients found." The search
appears to be comparing the full query as a single substring against a
single name field rather than matching individual terms against the
name fields independently.

**Bug 2 — Patient History timeline duplicates multi-parameter records.**
The same Leg X-ray with both Findings and Impression renders as TWO
separate cards in the specialist's Patient History timeline — identical
to the bug that was previously fixed for the patient's "My Medical
Records" screen. The fix already exists (`record_grouper.dart`) but
was not applied to the specialist's timeline.

**Bug 3 — Long clinical text overflows the card.** When a record contains
a long `test_value` (e.g., the Impression paragraph "Weak Plantar
Flexion: Significant weakness..."), Flutter reports
"RIGHT OVERFLOWED BY 1546 PIXELS" and the text is visually truncated.

---

## Bug 1 — Patient search semantics

### Design specification (locked with project lead 2026-06-23)

The search uses term-based matching with AND logic across split terms:

1. **Split the query** by whitespace into terms. Multiple consecutive
   spaces collapse to a single delimiter. Empty terms are dropped.
2. **Each term must match somewhere** in either `first_name` OR
   `last_name` (substring, case-insensitive).
3. **All terms must match** for the patient to appear in results.
4. **Order-independent.** "Wem Victor" finds Victor Wembanyama just as
   "Victor Wem" does.

### Examples

| Query | Should find Victor Wembanyama? | Why |
|---|---|---|
| `Vic` | YES | "Vic" matches first_name |
| `Wem` | YES | "Wem" matches last_name |
| `Victor` | YES | matches first_name exactly |
| `Victor Wem` | YES | "Victor" matches first; "Wem" matches last |
| `Wem Victor` | YES | same logic, order-independent |
| `Vic Wem` | YES | partial matches across both fields |
| `victor wembanyama` (lowercase) | YES | case-insensitive |
| `Banks Victor` | NO | "Banks" matches nothing |
| `   Victor   ` (extra spaces) | YES | whitespace collapses cleanly |
| `""` (empty query) | YES (returns all, or empty list per existing behavior) | unchanged from today |

### Implementation guidance

Where to put the search logic depends on where it currently lives:

**Option A — Client-side filter (likely current pattern)**
If the specialist provider currently fetches all patients and filters
locally, update the filter:

```dart
List<Patient> filterPatients(List<Patient> all, String query) {
  if (query.trim().isEmpty) return all;
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return all;
  
  return all.where((p) {
    final first = p.firstName.toLowerCase();
    final last = p.lastName.toLowerCase();
    // Every term must appear in either first or last name
    return terms.every((t) => first.contains(t) || last.contains(t));
  }).toList();
}
```

**Option B — Server-side filter (Supabase query)**
If the specialist provider sends a query string to Supabase via PostgREST
`ilike`, this approach is harder because PostgREST doesn't natively
support per-term AND matching on a single query. Two ways to handle:

- (B1) Switch to client-side filtering as in Option A. Fetch all
  patients the specialist is authorized to see, filter in Dart.
- (B2) Build a more complex query: send N `ilike` filters, one per
  term, joined with `and` and an OR for each field per term. This
  scales poorly past 3-4 terms.

**Recommended:** Option A. The patient list for a specialist is bounded
(under a few thousand even for a busy clinic). Client-side filtering is
simpler, gives instant search feedback as the user types, and avoids
PostgREST query complexity.

### Files affected (Bug 1)

- `lib/features/staff/presentation/providers/specialist_provider.dart`
  (or equivalent) — update the search/filter method.
- `lib/features/staff/presentation/screens/specialist_home_screen.dart`
  (or the search screen) — likely unchanged; it should just call the
  provider's filter method as today.

---

## Bug 2 — Apply the existing records grouper to Patient History timeline

### Context

The fix was already implemented for the patient's "My Medical Records"
screen in the prior records grouping task. The domain helper is in
`lib/features/records/domain/record_grouper.dart` and exposes:

- `GroupedRecord` class
- `groupRecords(List<DepartmentRecord>)` function

The specialist's Patient History timeline currently fetches and renders
raw `department_records` rows. The fix is to call `groupRecords()` on
those rows and render the resulting groups instead.

### Implementation guidance

The specialist provider that loads a patient's records — likely
something like `loadPatientHistory(patientId)` — needs one additional
step:

```dart
// Before (current behavior):
final records = await repository.getRecordsForPatient(patientId);
state = state.copyWith(records: records);

// After:
final records = await repository.getRecordsForPatient(patientId);
final grouped = groupRecords(records);
state = state.copyWith(groupedRecords: grouped);
// Or keep raw records too if other code reads them:
state = state.copyWith(records: records, groupedRecords: grouped);
```

The timeline UI then iterates over `groupedRecords` and renders each
group as ONE card, not as one card per row. Within each card:

- If `isSingleParameter`: render the existing single-parameter card
  design (backward compat).
- If multi-parameter: render with the consolidated design — title
  derived from shared `test_type` if all rows share it (e.g., "Leg
  X-ray"), else "Department — Date" (e.g., "Imaging — 2026-06-23").
  Show all parameters stacked in the detail view, with the worst-case
  status badge (CRITICAL > INCONCLUSIVE > NORMAL).

The detail view for a grouped record should match the pattern already
established in the patient's My Medical Records modal — stacked
parameter sections.

### Files affected (Bug 2)

- `lib/features/staff/presentation/providers/specialist_provider.dart`
  — add grouping to the patient history load
- `lib/features/staff/presentation/screens/specialist_patient_history_screen.dart`
  (or wherever the timeline lives) — iterate over groups, not raw rows
- The timeline card widget — reuse or adapt the existing
  `record_card.dart` widget from the patient records feature, OR
  create a thin specialist-timeline wrapper that accepts a
  `GroupedRecord`

### Reuse vs. duplicate

**Strong preference:** reuse the existing `record_grouper.dart`
without modification. Do NOT duplicate the grouping logic in a
specialist-specific helper. The grouping rules are identical
regardless of who's viewing.

If the specialist timeline needs a different card layout (e.g., showing
a vertical timeline indicator on the left side, as visible in the bug
report screenshot), that's a presentation-layer choice. The card
widget can be specialist-specific while the grouping logic is shared.

---

## Bug 3 — Long clinical text overflows the card

### Symptom

Flutter reports a render error "RIGHT OVERFLOWED BY 1546 PIXELS" on the
card displaying the Impression record. The clinical text is truncated
visually with the standard yellow/black overflow indicator.

### Root cause (likely)

The card's text widget is inside a `Row` or other horizontal-axis
constraint without a `Flexible` or `Expanded` wrapper, so long strings
extend beyond the card's right edge instead of wrapping to multiple
lines.

### Fix

Wrap the long-text widget in `Flexible` (preferred) or `Expanded` so it
fills available horizontal space and wraps to multiple lines:

```dart
// Before:
Row(
  children: [
    Text("Result: "),
    Text(record.testValue),  // overflows for long strings
  ],
)

// After:
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text("Result: "),
    Flexible(
      child: Text(
        record.testValue,
        softWrap: true,
      ),
    ),
  ],
)
```

Or alternatively, use a `Column` if the label and value should stack
vertically:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text("Result:", style: labelStyle),
    Text(record.testValue, softWrap: true),
  ],
)
```

Apply this pattern to every text widget on the timeline card that could
contain long content: `test_value`, `notes`, and any other free-form
field.

### Files affected (Bug 3)

- The specialist timeline card widget (likely in
  `lib/features/staff/presentation/widgets/specialist_history_card.dart`
  or inline within the timeline screen)
- Possibly the patient detail modal if it shares the same widget

---

## Tests

### New unit tests — `test/phase9_specialist_search_test.dart`

Cover the search filter directly:

1. Empty query returns all patients (or unchanged behavior)
2. Single term "Vic" finds Victor Wembanyama
3. Single term "Wem" finds Victor Wembanyama (last name match)
4. Two terms "Victor Wem" finds Victor Wembanyama (each term in
   respective field)
5. Two terms reversed "Wem Victor" finds Victor Wembanyama
   (order-independent)
6. Two terms with partial match "Vic Wem" finds Victor Wembanyama
7. Case-insensitive: "victor wembanyama" finds Victor Wembanyama
8. Whitespace collapse: "   Victor   Wem   " finds Victor Wembanyama
9. Non-matching term "Banks Victor" does NOT find Victor Wembanyama
10. Multiple patients: "Vic" finds all patients with "vic" in either
    name field (Victor, Vicky, etc.)
11. Empty after trim: "   " returns all patients (treat as empty
    query)

### New widget tests — `test/phase9_specialist_timeline_grouping_test.dart`

1. Specialist Patient History timeline with two same-bucket
   `department_records` rows renders ONE card (the grouped card)
2. The grouped card's detail view shows both parameters stacked
3. Long `test_value` text on a timeline card wraps to multiple lines
   without overflow (no RenderFlex overflow error in the widget tree)
4. Single-parameter records on the timeline render unchanged (backward
   compat)

### Existing tests

The records grouping unit tests
(`test/phase9_records_grouping_test.dart`) should still pass — we're
reusing the same function, not modifying it. Run them to confirm no
regression.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis still clean
flutter analyze

# 2. New search filter unit tests pass
flutter test test/phase9_specialist_search_test.dart

# 3. New specialist timeline widget tests pass
flutter test test/phase9_specialist_timeline_grouping_test.dart

# 4. Existing records grouping tests still pass (proves reuse, not duplication)
flutter test test/phase9_records_grouping_test.dart

# 5. Full test suite passes
flutter test

# 6. Confirm no overflow errors during widget tests (visual check)
# When running the widget test in step 3, the test output should NOT
# contain any "RenderFlex overflowed" messages.

# 7. Grep — the grouper helper is reused, not duplicated
grep -rn "GroupedRecord\|groupRecords" lib/
# Expected: matches in lib/features/records/domain/record_grouper.dart
# (definition) AND in the specialist provider (usage). NO new file
# duplicating the GroupedRecord class.
```

Plus **four screenshots** from the emulator:

- `specialist_search_partial_name.png` — Specialist Portal with search
  field containing "Vic" returning Victor Wembanyama as a result
- `specialist_search_full_name_with_space.png` — Search field
  containing "Victor Wem" or "Victor Wembanyama" returning the same
  patient (proves the bug fix)
- `specialist_history_grouped_card.png` — Patient History timeline
  showing ONE Leg X-ray card consolidating Findings and Impression
  (compare to the bug report screenshot showing two cards)
- `specialist_history_long_text_no_overflow.png` — Same card or
  another with long clinical text rendering with proper line wrapping
  and NO yellow/black overflow indicator

---

## Out of scope

- **Schema changes.** Not touching `patients`, `department_records`, or
  any other table.
- **Server-side full-text search** (Postgres `tsvector` etc.).
  Client-side filtering is sufficient at the scale of this clinic.
- **Fuzzy/typo-tolerant search** (Levenshtein, soundex, etc.). Out of
  scope. Substring matching is enough.
- **Pagination of search results.** Out of scope. The patient list is
  bounded.
- **Reverse-applying** the grouper to other surfaces. The patient's My
  Medical Records already uses it; the receptionist mobile doesn't
  show records (read-only Documents lookup); the department staff
  Recent Records view could benefit from grouping, but is OUT OF SCOPE
  for this task. **Note: if the department staff Recent Records tab
  also duplicates multi-parameter records, flag it in the walkthrough
  as a follow-up.**
- **State-change actions on the specialist surface.** Specialist mobile
  remains fully read-only.

---

## Defense framing

When this lands, the specialist mobile narrative becomes:

> *"The specialist surface received final hardening alongside the patient
> records grouping fix. Patient search now uses term-based AND matching
> across both name fields case-insensitively, supporting full names with
> spaces and partial matching in any order. The Patient History timeline
> reuses the records grouper helper from the patient records feature —
> same domain function, same multi-parameter consolidation behavior,
> no logic duplication. And the timeline card now handles long clinical
> values with proper line wrapping. The specialist mobile mode remains
> fully read-only per Constraint #12."*

That's the line. It tells three coherent stories — search UX,
architectural reuse, layout fix — and reaffirms the read-only constraint.

---

## When complete — walkthrough should include

1. List of files modified with one-line changes per file.
2. The 7 bash command outputs above.
3. The 4 screenshots.
4. Confirmation that:
   - The search filter uses split-by-whitespace term-AND matching
     across `first_name` OR `last_name` case-insensitively
   - The `GroupedRecord` class and `groupRecords()` function are reused
     from `lib/features/records/domain/record_grouper.dart` — no
     duplicate definition exists in the specialist feature
   - The timeline card's long-text widgets use `Flexible` (or
     equivalent) with `softWrap: true`
5. **Follow-up flag:** if the department staff Recent Records view
   also shows multi-parameter records as separate cards, mention it in
   the walkthrough's closing notes as a candidate for a future small
   fix (NOT done in this task).
6. Manual verification on emulator with the project lead's actual test
   data: search "Victor Wembanyama" finds the patient; open Patient
   History; see ONE Leg X-ray card with both Findings and Impression
   visible in the detail view; no overflow warnings in the debug
   console.
