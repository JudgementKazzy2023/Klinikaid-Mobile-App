# Antigravity Task — OCR Retake Button Redirect Fix

> **Task type:** small UX bug fix — no schema changes, no new dependencies,
> no architectural changes.
> **Goal:** Fix the OCR "Retake" button so it returns the patient to the
> OCR landing page (where they can choose Camera or Gallery), not directly
> back to the camera.
>
> **Estimated effort:** ~30 minutes including verification.

---

## Context for this task

The OCR submission flow has three screens:

1. **OCR landing page** — patient picks Camera or Gallery as the input source
2. **Camera / Gallery screen** — the actual capture/picker
3. **OCR preview screen** — patient sees the captured image with two buttons: "Retake" and "Submit Document"

Current behavior: tapping **Retake** navigates the patient back to whichever
specific input they used (e.g., re-opens the camera directly).

Desired behavior: tapping **Retake** returns the patient to the **OCR
landing page** so they can choose a different input source (e.g., they
took a bad photo with the camera and want to switch to picking a clearer
image from the gallery).

---

## The fix

A single route-target change on the Retake button. Most likely a one-line
edit.

### Files affected (likely list — confirm by reading the actual files)

- `lib/features/ocr/presentation/screens/ocr_preview_screen.dart` — the
  screen with the Retake button (filename may vary; check `lib/features/ocr/`)
- The Retake button's `onPressed` handler

### Implementation guidance

The Retake button currently does something like:

```dart
// Before — navigates back to camera directly
ElevatedButton(
  onPressed: () {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CameraScreen(),
    ));
    // OR
    Navigator.pop(context);  // pops back to whichever screen was below
    // OR
    context.go('/patient/ocr/camera');
  },
  child: const Text('Retake'),
)
```

The fix: navigate to the OCR landing page route instead. The exact path
depends on the project's GoRouter configuration:

```dart
// After — navigates back to OCR landing page
ElevatedButton(
  onPressed: () {
    context.go('/patient/ocr');  // or whatever the landing page route is
  },
  child: const Text('Retake'),
)
```

**Important — clear the in-memory preview state.** When the patient
returns to the landing page, the previously captured image and OCR'd
text should NOT persist. Otherwise tapping Camera again then Cancel
might inadvertently re-show the old preview. Two ways to handle:

1. **Pop-based navigation:** `Navigator.popUntil((route) => route.settings.name == '/patient/ocr')`
   — pops back through the stack to the landing page. Any state held by
   the popped screens is automatically released.

2. **Provider-based clear:** if the captured image and OCR text are
   stored in an OCR provider (e.g., `OcrSubmissionProvider`), call
   something like `provider.clearCapturedImage()` before navigating.

**Recommended:** Option 1 (`Navigator.popUntil`) is simpler and uses
Flutter's stack semantics naturally. Option 2 is needed only if the
state persists across the provider lifecycle (e.g., kept alive via
`ChangeNotifierProvider` higher up the widget tree).

The agent should inspect the OCR provider/state holder to decide which
applies.

---

## Tests

### New widget test — `test/phase9_ocr_retake_redirect_test.dart`

A single test case:

- Pump the OCR preview screen with a captured image
- Tap the Retake button
- Assert the resulting route is the OCR landing page (not the camera
  screen)
- Optionally: assert that the captured image state is cleared from the
  provider

### Existing tests

Phase 4 OCR tests should still pass. Run them to confirm no regression.

---

## Verification (paste outputs in the walkthrough)

```bash
# 1. Static analysis still clean
flutter analyze

# 2. New retake redirect widget test passes
flutter test test/phase9_ocr_retake_redirect_test.dart

# 3. Existing OCR tests still pass
flutter test test/phase4_ocr_test.dart   # adjust path to match actual filename

# 4. Full test suite passes
flutter test
```

Plus **two screenshots** from the emulator:

- `ocr_preview_with_retake_button.png` — the preview screen showing the
  captured image and the Retake button visible
- `ocr_landing_after_retake.png` — the landing page after Retake was
  tapped, showing the Camera / Gallery option buttons

---

## Out of scope (deferred to post-defense)

- **File manager support for PDF/DOCX uploads.** This was discussed and
  consciously deferred to a post-defense feature task. The implementation
  involves PDF text extraction (for native-text PDFs), PDF page rendering
  + ML Kit OCR (for image-based PDFs), and a third input source on the
  OCR landing page. None of this is added here.
- **Schema changes.** None.
- **Library additions.** None.

---

## Defense framing

This is a small UX papercut fix, not a defense talking point. No new
narrative needed.

---

## When complete — walkthrough should include

1. The single file modified, with the one-line change shown
2. Which navigation approach was chosen (`popUntil` vs. provider clear)
   and why
3. The 4 bash command outputs
4. The 2 screenshots
5. Confirmation that the captured image / OCR text state does NOT
   persist after returning to the landing page (no stale preview risk)
