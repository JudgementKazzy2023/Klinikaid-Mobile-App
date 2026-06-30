# Antigravity Task — AI-Powered OCR Quality Assessment (Path A)

> **Task type:** mobile architectural change — replaces the hardcoded
> pre-screen pipeline with an AI-driven quality assessment that uses
> Gemini via a new Supabase Edge Function. Includes Constraint #6
> rewording. Preserves Constraint #7 (no auto-rejection).
> **Scope:** image quality and legibility assessment only. No clinic
> policy logic, no document-type sophistication, no expiry checks.
> Those are post-defense scope.
> **Goal:** replace the four hardcoded pre-screen checks (date pattern,
> doctor token, name match, diagnostic keywords) with one AI quality
> call that returns a numerical score plus a list of patient-facing
> issues. Patient sees traffic-light feedback AND the numerical score.
> Submit-anyway always remains available.

---

## Context for this task

The current OCR pre-screen pipeline (v4 checklist sub-tasks 4.6, 4.7,
4.8, 4.9) uses four hardcoded checks designed for medical referrals:

- 4.6 Date pattern detection (regex)
- 4.7 Doctor token detection ("Dr.", "M.D.")
- 4.8 Patient name cross-reference (string comparison)
- 4.9 Diagnostic keyword matching ("laboratory", "x-ray", "cbc", etc.)

These checks are scope-mismatched. They were designed assuming the
document is always a medical referral, but they fail for valid non-
medical documents (IDs, certificates, etc.). They also can't detect
the most common patient-side problem: poor image quality. A patient
submitting a blurry photo gets no feedback about the actual problem.

This task replaces 4.6, 4.7, and 4.9 with an AI-driven quality
assessment. **Sub-task 4.8 (patient name cross-reference) STAYS** as
a hardcoded check — it's identity matching, not quality assessment.

The web team's decision (2026-06-XX): mobile owns the OCR pipeline
end-to-end. Web's AI OCR was disabled in favor of this division of
responsibility. Mobile owns capture and quality assessment; web's
receptionist screen owns the final approve/reject review.

---

## Path A Architecture (locked with project lead)

```
1. Patient captures or picks an image
2. ML Kit extracts text ON-DEVICE (unchanged from Phase 4)
3. App calls a NEW Edge Function (assess-document-quality)
   with: { ocr_text, patient_name_for_identity_check }
4. Edge Function calls Gemini (text model, not Vision) with a
   quality-assessment prompt
5. Edge Function returns: { score, verdict, issues[] }
6. Mobile runs the ONE preserved hardcoded check (sub-task 4.8 —
   patient name cross-reference) against the OCR text
7. Mobile UI shows:
   - Traffic light (green/yellow/red) prominently
   - Numerical score (e.g., "Quality Score: 78/100") below it
   - Issue list under that
   - Identity warning (if name check fails) as a separate alert
   - Submit and Retake buttons — BOTH always enabled
8. Patient taps Submit (or Retake)
9. Submission flow continues unchanged (Supabase Storage upload,
   documents row insert with status='pending')
```

**Constraint #6 preservation:** the IMAGE never leaves the device.
Only the OCR'd text transits to the Edge Function. ML Kit on-device
text extraction remains the mobile architecture's privacy boundary.

**Constraint #7 preservation:** Submit-anyway is always available
even on a low score / red light. No auto-rejection.

---

## What gets built

### 1. New Supabase Edge Function — `assess-document-quality`

Location: `supabase/functions/assess-document-quality/index.ts`

Responsibility: receive OCR'd text, call Gemini, return quality
assessment.

**Request shape:**

```json
{
  "ocr_text": "string — the full OCR-extracted text from the image",
  "patient_name": "string — the logged-in patient's full name, for identity check context"
}
```

(Note: `patient_name` is included so the prompt can mention the
expected name when prompting Gemini, NOT as the identity match
mechanism itself. The identity match still runs in mobile code as a
deterministic check per sub-task 4.8.)

**Response shape (locked):**

```json
{
  "score": 78,
  "verdict": "good" | "marginal" | "poor",
  "issues": [
    {
      "type": "blur" | "illegible_text" | "incomplete_info" | "low_text_density" | "other",
      "severity": "low" | "medium" | "high",
      "description": "Short patient-facing string explaining the issue"
    }
  ]
}
```

- `score`: integer 0-100
- `verdict`: maps to traffic light (good=green, marginal=yellow, poor=red)
- `issues`: 0+ items; empty array means no issues found

**Verdict thresholds (server-side, agent can tune):**

- `good` (green): score >= 80, no high-severity issues
- `marginal` (yellow): score 50-79, OR any medium-severity issue
- `poor` (red): score < 50, OR any high-severity issue

The thresholds are hardcoded in the Edge Function (not configurable
from the client). Document them in the function's comments so future
adjustments are findable.

**Prompt design (starting point — agent tunes):**

```
You are a document quality assessor for a medical clinic intake
system. A patient submitted a document via their mobile app. The
extracted OCR text is below. Assess the quality of the document's
capture (NOT the document content itself).

Focus on:
- Is the OCR text complete and coherent, or does it appear truncated
  or fragmented?
- Are there signs the image was blurry, glared, or cropped (e.g.,
  partial words, garbled characters, very low text count)?
- Is the text legible enough for a clinic receptionist to read and
  process?

Do NOT:
- Judge whether the document is a medical referral or another type
- Judge whether dates are recent or expired
- Judge whether required fields are present (this is the receptionist's job)
- Refuse to assess if the document type is unusual

Return a JSON object with:
- "score": integer 0-100 (overall quality)
- "verdict": "good" | "marginal" | "poor"
- "issues": array of {type, severity, description} objects

Issue types must be one of: "blur", "illegible_text",
"incomplete_info", "low_text_density", "other"

Descriptions should be short patient-facing strings, max ~15 words
each, written in second person ("Your document...").

Expected patient name (for context only; do NOT use as a rejection
criterion): {patient_name}

OCR text to assess:
---
{ocr_text}
---

Return ONLY valid JSON, no markdown fences, no preamble.
```

The agent should adjust this prompt for clarity and tested behavior.
The shape of the JSON response is locked; the prompt language can
be tuned.

**Error handling:**

- Gemini API failure → return `{ score: 50, verdict: "marginal", issues: [{type: "other", severity: "low", description: "Quality assessment unavailable. Receptionist will review."}] }` and log the failure
- Invalid Gemini JSON response → same fallback
- Timeout (> 10s) → same fallback
- Constraint #1 (Gemini key): the key lives ONLY in the Edge Function's
  Supabase secrets (`supabase secrets set GEMINI_API_KEY=<value>`).
  Never in the mobile APK.

### 2. Mobile-side integration

**New file:** `lib/features/ocr/data/document_quality_service.dart`

A thin wrapper that calls the Edge Function:

```dart
class DocumentQualityService {
  Future<QualityAssessment> assess({
    required String ocrText,
    required String patientName,
  }) async {
    // POST to assess-document-quality edge function
    // Parse response
    // Return QualityAssessment
    // On error, return the fallback assessment
  }
}
```

**New domain model:** `lib/features/ocr/domain/quality_assessment.dart`

```dart
enum QualityVerdict { good, marginal, poor }

enum QualityIssueType {
  blur,
  illegibleText,
  incompleteInfo,
  lowTextDensity,
  other,
}

enum QualityIssueSeverity { low, medium, high }

class QualityIssue {
  final QualityIssueType type;
  final QualityIssueSeverity severity;
  final String description;
}

class QualityAssessment {
  final int score;
  final QualityVerdict verdict;
  final List<QualityIssue> issues;
  
  Color get verdictColor => switch (verdict) {
    QualityVerdict.good => Colors.green,    // adjust to theme
    QualityVerdict.marginal => Colors.amber,
    QualityVerdict.poor => Colors.red,
  };
  
  String get verdictLabel => switch (verdict) {
    QualityVerdict.good => 'Looks good',
    QualityVerdict.marginal => 'Some issues found',
    QualityVerdict.poor => 'Quality may be too low',
  };
}
```

### 3. Replace the four hardcoded checks with one AI call

**File:** `lib/features/ocr/presentation/screens/ocr_preview_screen.dart`
(or wherever the pre-screen logic lives — likely in a provider or
service called by the preview screen).

**Remove (or comment out for traceability):**

- Sub-task 4.6 — date pattern regex check
- Sub-task 4.7 — doctor token detection
- Sub-task 4.9 — diagnostic keyword matching

**Add:** call to `DocumentQualityService.assess()` after ML Kit OCR
completes.

**Keep:** sub-task 4.8 — patient name cross-reference. Run it
deterministically against the OCR text, surface as a separate
warning if the logged-in patient's name doesn't appear in the OCR
text. This is independent of the AI score.

### 4. UI changes on the OCR preview screen

The preview screen currently shows the captured image plus the four
hardcoded check results. Replace the four check rows with:

**A. The traffic light card (prominent):**

```
┌─────────────────────────────────────┐
│ [green dot]  Looks good             │
│              Quality Score: 87/100  │
└─────────────────────────────────────┘
```

Or for marginal/poor:

```
┌─────────────────────────────────────┐
│ [yellow dot]  Some issues found     │
│               Quality Score: 64/100 │
│                                     │
│ • Your image appears slightly blurry │
│ • Some text may be hard to read     │
└─────────────────────────────────────┘
```

**B. Identity-match warning (if applicable, separate card):**

```
┌─────────────────────────────────────┐
│ ⚠ Your name was not found on this   │
│   document. If this document does   │
│   belong to you, you may still      │
│   submit it for receptionist review.│
└─────────────────────────────────────┘
```

**C. Action buttons (both always enabled):**

```
[ Retake ]   [ Submit Document ]
```

Even on a red verdict, both buttons stay enabled. The Submit button
may visually de-emphasize (outlined instead of filled) on a red
verdict to nudge the patient toward Retake, but it must remain
tappable. Constraint #7.

### 5. Store the assessment in `documents.metadata`

When the document is submitted, include the AI assessment in the
`extracted_metadata` jsonb column:

```json
{
  "ocr_text": "...",
  "quality_assessment": {
    "score": 78,
    "verdict": "marginal",
    "issues": [...]
  },
  "identity_match": true,
  "submitted_with_warnings": true,
  ...other existing metadata
}
```

This way the web receptionist screen can see the score and issues
during their review — even though we're not building a receptionist
UI for it in this task. The data is there for the web team to surface
later if they want.

---

## Files affected (likely list — confirm by reading the actual files)

- `supabase/functions/assess-document-quality/index.ts` — NEW Edge Function
- `lib/features/ocr/data/document_quality_service.dart` — NEW mobile service
- `lib/features/ocr/domain/quality_assessment.dart` — NEW domain models
- `lib/features/ocr/presentation/screens/ocr_preview_screen.dart` — UI rebuild
- `lib/features/ocr/presentation/providers/ocr_provider.dart` (or similar) — replace hardcoded checks with AI call
- `lib/features/ocr/domain/pre_screen_checks.dart` (or wherever 4.6/4.7/4.9 live) — remove the three checks; keep 4.8
- `test/phase9_ocr_ai_quality_test.dart` — NEW tests
- `lib/core/config/env.dart.example` — confirm GEMINI_API_KEY is NOT here (it's an Edge Function secret only)

---

## Tests

### New unit tests — `test/phase9_ocr_ai_quality_test.dart`

Cover the mobile-side parsing and presentation logic. The Edge
Function itself is tested separately (see below).

1. `DocumentQualityService` parses a well-formed Gemini response into
   `QualityAssessment` correctly
2. `DocumentQualityService` returns fallback assessment on HTTP error
3. `DocumentQualityService` returns fallback assessment on malformed JSON
4. `QualityAssessment.verdictColor` maps verdict → color correctly
   for all three verdicts
5. `QualityAssessment.verdictLabel` returns correct text for all three
   verdicts
6. Patient name cross-reference (sub-task 4.8) still works:
   - Name in OCR text → match succeeds
   - Name NOT in OCR text → match fails
   - Case-insensitive match
   - Whitespace-tolerant match
7. Pipeline integration: ML Kit returns text → service is called →
   verdict is correctly applied to the assessment state (use a
   mocked Edge Function call)

### Widget tests — extend existing or add new

1. Traffic-light card renders with correct color for each verdict
2. Score number renders correctly (e.g., "Quality Score: 78/100")
3. Issue list renders all issues from the response
4. Submit button stays enabled on red verdict (Constraint #7 guard)
5. Identity-match warning renders when name check fails; absent
   when it succeeds
6. Empty issues array → no issues list rendered (clean UI)

### Edge Function tests

The Edge Function should have a basic test confirming:

1. Valid request → 200 with the expected JSON shape
2. Missing `ocr_text` → 400 with clear error
3. Gemini API error → fallback assessment returned with 200 (graceful)
4. Response always conforms to the locked JSON shape

These can be run via the Supabase CLI's local function testing OR via
a simple curl-based smoke test documented in the walkthrough.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis clean
flutter analyze

# 2. New AI OCR tests pass
flutter test test/phase9_ocr_ai_quality_test.dart

# 3. Existing Phase 4 OCR tests still pass (regression check)
flutter test test/phase4_ocr_test.dart   # adjust filename if needed

# 4. Full test suite passes
flutter test

# 5. Constraint #1 check: APK does NOT contain GEMINI_API_KEY
flutter build apk --release
apktool d build/app/outputs/flutter-apk/app-release.apk -o /tmp/klinikaid_decompiled
grep -r "AIzaSy" /tmp/klinikaid_decompiled    # expected: 0 matches
grep -r "GEMINI" /tmp/klinikaid_decompiled    # expected: 0 matches

# 6. Constraint #6 check: image processing stays on-device
grep -rn "ml_kit\|MlKit\|TextRecognizer" lib/features/ocr/
# Expected: ML Kit usage present (proves on-device text extraction is preserved)

# 7. Removed hardcoded checks are gone
grep -rn "diagnostic_keyword\|doctor_token\|date_pattern" lib/features/ocr/
# Expected: 0 matches in active code (matches in comments documenting the
# removal are acceptable)

# 8. Patient name check preserved (sub-task 4.8)
grep -rn "patientName\|patient_name_match\|name_cross_reference" lib/features/ocr/
# Expected: matches present
```

Plus **four screenshots** from the emulator showing the new UI states:

- `ocr_preview_good_quality.png` — green traffic light, score ≥ 80,
  no issues listed
- `ocr_preview_marginal_quality.png` — yellow traffic light, score
  50-79, 1-2 issues listed
- `ocr_preview_poor_quality.png` — red traffic light, score < 50,
  issue list shown, Submit button still enabled but de-emphasized
- `ocr_preview_identity_mismatch.png` — any verdict, with the
  identity-match warning card visible (achieved by submitting a doc
  with a different patient's name on it)

---

## Documentation updates

### `MASTER_CONTEXT.md`

- **Constraint #6 rewording** (since the wording was sharpened in
  prior discussion):

  > *Image-to-text extraction has zero network egress (ML Kit on-device).
  > The extracted text is sent to a Supabase Edge Function
  > (`assess-document-quality`) for AI-driven quality assessment using
  > Gemini. The image itself never leaves the device. The most-sensitive
  > content — the original image — remains on-device throughout the
  > submission lifecycle.*

- **Architectural decision record** — add a brief note that the OCR
  pre-screen was redesigned during final hardening, with the
  rationale: hardcoded checks were scope-mismatched (medical referrals
  only); AI quality assessment scales to any document type the clinic
  may accept; web team's decision to disable their own AI OCR confirmed
  mobile-owns-OCR architectural separation.

### `v4 checklist` (if you want to update it in this task)

Sub-tasks 4.6, 4.7, 4.9 should be marked superseded or rewritten:

- 4.6 (was: Date Pattern Detection) → "AI Quality Assessment — Image
  Coherence Check"
- 4.7 (was: Doctor Token Detection) → "AI Quality Assessment —
  Legibility Check"
- 4.9 (was: Diagnostic Keyword Matching) → "AI Quality Assessment —
  Completeness Check"

Sub-task 4.8 (patient name cross-reference) stays as-is.

**OR** the agent can flag these for the project lead to update
manually after this fix lands. Either is fine; just make the update
explicit somewhere.

---

## Out of scope (explicitly deferred)

- **Clinic policy as data** (Postgres `document_validity_policies`
  table). Deferred to post-defense.
- **Document-type detection** ("is this a referral vs an ID vs a
  certificate?"). The AI assesses quality only, not type.
- **Expiry date checks** (e.g., "this document is more than 90 days
  old"). The AI does NOT enforce recency. Receptionist handles that.
- **Image-to-Gemini-Vision** approach. We're on Path A
  (text-to-Gemini), explicitly chosen for the Constraint #6
  preservation reason.
- **Receptionist UI changes on web**. The quality assessment is stored
  in `documents.metadata` so the web team can surface it later if they
  want; building the receptionist-side display is out of mobile scope.
- **Web team's prompt re-use**. They offered to share but the project
  lead chose to design fresh.

---

## Defense framing

When this lands, the OCR pipeline narrative becomes:

> *"The document submission pre-screen was redesigned during final
> hardening. The original hardcoded checks (date pattern, doctor token,
> name match, diagnostic keywords) were scope-mismatched — they assumed
> medical referrals as the only document type, but the clinic accepts
> a broader range. More importantly, they couldn't catch the most
> common patient-side problem: poor image capture quality.*
>
> *We replaced them with AI-driven quality assessment via a new
> Supabase Edge Function. ML Kit continues to extract text on-device
> (Constraint #6 preserved — the image never leaves the device). The
> extracted text is sent to Gemini for quality reasoning. The patient
> sees a traffic-light indicator with an actionable issue list before
> deciding whether to submit. Identity verification (sub-task 4.8)
> stays as a deterministic check because it's a fraud-deterrence
> question, not a quality question.*
>
> *The Submit button remains enabled even on a poor verdict because
> the receptionist is the final authority — Constraint #7 (no auto-
> rejection) is preserved. The quality assessment is stored in the
> document's metadata so the receptionist can see it during their
> web-side review.*
>
> *The architectural decision to put quality assessment on mobile rather
> than web was a joint call with the web team — their AI OCR was
> disabled in favor of this clean separation: mobile owns capture and
> quality, web owns the receptionist's authoritative review."*

That's the line.

---

## When complete — walkthrough should include

1. List of files modified or created with one-line summary per file.
2. The 8 verification command outputs above.
3. The 4 emulator screenshots.
4. The actual prompt used for the Edge Function (so the project lead
   can review and refine if needed).
5. A sample Gemini response showing the structured JSON output.
6. Confirmation that:
   - The image never leaves the device (Constraint #6)
   - The Gemini key is NOT in the APK (Constraint #1)
   - Sub-task 4.8 (patient name cross-reference) is preserved
   - Sub-tasks 4.6, 4.7, 4.9 are removed (or clearly commented out
     with rationale)
   - Submit-anyway works on a red verdict (Constraint #7)
   - The quality assessment is stored in `documents.metadata`
7. Note in the walkthrough whether v4 checklist sub-task wording was
   updated or flagged for the project lead.
8. Manual verification: submit at least one good document, one blurry
   document, and one with a wrong name to verify all three traffic-
   light states and the identity warning behavior.
