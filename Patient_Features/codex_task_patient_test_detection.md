# SPEC — Patient OCR Test-Detection + Selection (#8 + #9 + #10)

**KlinikAid Mobile (Flutter/Android). Coder: ChatGPT Codex. Reviewer gates plan
(Gate B) + on-device walkthrough (Gate D).**

Mirror of web's patient OCR feature: after a patient uploads a lab document,
**detect which tests appear on it** (from OCR text), show **checkboxes** (with
**prep info** per test), let the patient **select** which they want, store the
selection, and **display it on reception**. Reference facts from
`PATIENT_TEST_DETECTION_SPEC_INPUT.md` (web repo recon).

## STANDING RULES (self-contained)
- **Investigate before changing** — report current state first.
- **Trim testing:** one regression guard + one happy path per change; touched
  test files during iteration, full suite once at end.
- **Mock all external channels** (Supabase/auth) — no live client in tests.
- **Real-device verification** mandatory.
- No native/dep change expected (pure Dart + existing OCR/picker) → **release
  build not required** (state it). If deps/native get touched, run it.
- No images/mockups. Terse pass/fail. Don't claim a check you didn't run.

## LOCKED DECISIONS (veto at Gate B if you disagree)
1. **Detection is on-device Dart** — port web's catalog + substring matcher, run
   it on the ML Kit OCR text mobile already extracts. **No Edge Function, no
   Gemini, no server key** for detection. (The matcher is pure string logic.)
2. **Keep mobile's existing single submit flow** — do NOT replicate web's
   `pending_document_ocr` two-step server round-trip. Detect in-flow, select,
   write metadata on the existing submit.
3. **Zero selected is allowed** — mirror web (`selected_tests: []` permitted).
4. **Mobile reception displays selected tests** (#10) — the mobile
   document-validation screen shows the picks, matching web reception.

---

## Part 1 — Catalog + matcher (Dart, mirror web EXACTLY)

Port from web `src/lib/constants.ts` + `detectRequestedTests.ts`. **Byte-match**
the alias strings and matcher logic — if mobile detects differently than web,
the two platforms disagree on the same document.

- **`CLINIC_TEST_CATALOG`** — all 12 entries (id, label, aliases): `cbc`,
  `urinalysis`, `fecalysis`, `fbs`, `lipid_profile`, `creatinine`, `bun`,
  `sgpt_alt`, `sgot_ast`, `chest_xray`, `ecg`, `ultrasound`. Copy the exact
  aliases from the recon doc.
- **`CLINIC_TEST_PREP_INSTRUCTIONS`** — all 12 prep strings, keyed by id (copy
  verbatim from recon).
- **Matcher** — exact port:
  - `normalizeText(s)` = lowercase, collapse whitespace to single spaces, trim.
  - `detectRequestedTests(ocrText)` = normalize the text; return each catalog
    entry where **any** alias (normalized) is a **substring** of the normalized
    text; return `[{id, label}]`.
  - No fuzzy matching, no "improvements." Substring match only — same
    over-detection tolerance web has (patient deselects false positives).

> **Drift note:** this catalog is web's source of truth; mobile mirrors it →
> drifts if web changes it (same as template categories / placeholder ranges).
> Acceptable for now; note it for a future shared-source coordination.

## Part 2 — Patient submit: detection + selection UI (#8 + #9)

Insertion point: **after** on-device ML Kit OCR obtains `ocrText`, **before**
final submit. Coexists with the existing quality gate and the `document_type`
dedup picker (see interaction note).

- Run `detectRequestedTests(ocrText)`.
- **If detected tests exist:** show a checkbox list on the review card, **all
  checked by default** (mirror web), each row showing the test **label** and its
  **prep instruction** (#9) from `CLINIC_TEST_PREP_INSTRUCTIONS` beneath it.
- Patient toggles selection. **Zero selected is allowed.**
- **If no tests detected:** no checkbox step; submit proceeds normally.

## Part 3 — Mobile reception display (#10)

In the mobile document-validation screen (the one already handling templates),
read `extracted_metadata.selected_tests`:
- If `selected_tests.length > 0` → show a **"Patient-selected Tests"** section
  with each test's `label` as a badge (mirror web's emerald-outline badge).
- If absent/empty → no section. Null-safe.

---

## Metadata contract (byte-parity with web — CRITICAL)

On submit, when detection ran, add to `documents.extracted_metadata` the EXACT
web shape:
```json
{
  "detected_tests": [{ "id": "fbs", "label": "Fasting Blood Sugar (FBS)" }],
  "selected_tests": [{ "id": "fbs", "label": "Fasting Blood Sugar (FBS)" }],
  "test_detection_source": "ocr_text_catalog_match",
  "test_detection_version": 1
}
```
- `test_detection_source` and `test_detection_version` must be **exactly** these
  values.
- **Preserve existing keys** — do NOT clobber `ocr_text`, `quality_assessment`,
  `identity_match`, `submitted_with_warnings`, or `document_type`. Merge, don't
  replace.
- **If no tests detected → do NOT add these keys** (mirror web: the feature
  metadata is simply absent).

## Interaction notes (don't conflate)
- **`document_type` (dedup) vs `selected_tests` (this feature) are different
  and coexist.** `document_type` = coarse doc category (Referral / Lab Request /
  …) for the once-per-type dedup. `selected_tests` = specific tests found on the
  doc. Both are written; neither replaces the other. A "Lab Request"
  `document_type` may carry CBC+FBS `selected_tests`.
- Detection runs on the **same OCR text** the quality gate already produced —
  reuse it, don't OCR twice.
- Review-card order (leave exact UX to the plan): quality assessment →
  detected-tests checkboxes + prep (if any) → `document_type` picker → submit.

---

## Tests (mocked)
- **Unit — matcher:** OCR text with "hemoglobin" → detects `cbc`; "fasting blood
  sugar" → `fbs`; text with several → multiple; empty/poor text → `[]`;
  `normalizeText` collapses case/whitespace. Match a couple of exact web cases.
- **Unit — metadata builder:** detected+selected written in the exact shape
  (source + version correct); existing keys preserved (merge, not clobber); NO
  feature keys when detection is empty.
- **Widget — selection:** detected tests render as checkboxes (all checked by
  default) with prep text; toggling updates selection; zero-selected allowed.
- **Widget — reception:** a doc with `selected_tests` renders the badges; a doc
  without → no section (null-safe).
- **Regression:** existing submit still works — dedup/`document_type`, quality
  gate, and a document with NO detected tests all submit normally.

## Real-device verification
1. Upload a doc with recognizable test names (e.g. a CBC/FBS sheet) → detected
   tests appear as checkboxes with prep info → deselect one → submit.
2. Open the submitted doc in **mobile** reception → "Patient-selected Tests"
   badges show the picks; open in **web** reception → same picks (byte-parity).
3. A doc with no recognizable tests → no checkbox step, submits normally.
4. Deselect all → allowed (`selected_tests: []`), submits.
5. No native/dep change → release build not required (state it). No server key
   added (detection is on-device) → APK grep N/A (state it).

## Files affected (expected)
**New:** Dart catalog + prep + matcher (e.g. `lib/features/documents/clinic_test_catalog.dart`); tests.
**Modified:** patient submit screen/provider (detection + checkbox UI + prep +
metadata merge); mobile document-validation screen (selected-tests badges).

No Edge Function, no Gemini, no server key. No schema change. Metadata byte-matches web.
