# Recon — Web Patient OCR Test-Detection + Selection (#8–#10) (READ-ONLY)

> **Type:** read-only reconnaissance to gather facts for SPEC'ing the mobile port
> of web's patient OCR **test-detection + checkbox selection** feature (#8),
> plus **prep-info per test** (#9) and **reception shows selected tests** (#10).
> NOT a build. Output one input doc.
>
> **⚠️ Read-only. No code changes. No secrets copied (placeholders only).**
> **⚠️ Primarily the WEB repo `Setsuna-guwah/KlinikAid` (feature source); also
> check the MOBILE codebase for reusable OCR/Edge-Function infrastructure.**
> **⚠️ No images. Ask Ralph if repo access path differs.**

## The feature (context)
On web, a patient uploads a lab document → OCR **detects which tests are on it**
→ shows **checkboxes** → the patient **selects** which tests they want → only the
selected tests are routed to reception. Web also shows **prep instructions**
(fasting, etc.) per detected test, and reception cards **display the
patient-selected tests**. Mobile has the OCR upload but none of the detection/
selection layer. We need the authoritative web facts before designing the mobile
version.

## PRE-CHECK
Confirm #8–#10 are NOT part of the "big changes" the web team is currently making
(they're reshaping #11 / `employee_type`). If this area is also in flux, note it
and stop — we recon after it settles.

## What to extract (facts for the SPEC)

### 1. Detection mechanism (the deciding factor)
- **How does web detect which tests are on the document?**
  - Image sent to **Gemini** (like the department `extract-lab-values` pattern),
    or **OCR text matched against a catalog** (a constants file), or a hybrid?
  - If Gemini: capture the **prompt** used and the model.
  - If catalog-matching: capture the **matching logic** (exact/keyword/fuzzy).
- Is detection **server-side** (Edge Function / API route with the key
  server-side) or client-side? (Mobile can only use a server-side path — anon
  key only.)

### 2. The test catalog (mobile needs this)
- The **full list of detectable tests** and where it's defined (constants file).
- Is detection at the **panel** level (CBC, FBS, Renal, Lipid — the 4 we already
  have) or a **broader catalog of orderable tests**? Capture every entry: test
  id, display name, and which panel/group it belongs to.
- How each detected test maps to a catalog entry.

### 3. Selection + storage data model
- How detected tests are presented (checkbox list) and how the patient's
  **selection** is captured.
- **Where the selection is stored** — a column on `documents`? inside
  `extracted_metadata`? a separate table? Capture the exact field/shape and the
  type discriminator, so mobile writes it identically (cross-platform parity).
- Does selection happen **before** submit (patient picks, then submits only
  selected) — confirm the exact flow.

### 4. Prep-info per test (#9)
- Where per-test **prep instructions** (fasting, etc.) are defined (a constants
  file keyed by test id?). Capture the structure and a few examples.

### 5. Reception display (#10)
- How the reception **queue card / validation screen** reads and displays the
  patient-selected tests. What field it reads, how it renders them.

### 6. Mobile reuse (check the mobile codebase)
- Confirm the existing mobile **Edge Function pattern** we can clone: we already
  ship `extract-lab-values` (Gemini image → structured JSON, server-side key)
  and `assess-document-quality`. If web's detection is Gemini-based, mobile's
  version would be a **new Edge Function following the same pattern with a
  detection prompt** — confirm that's viable.
- Confirm the existing patient-upload flow (on-device ML Kit + document-type
  picker + dedup) that this detection layer would slot into.

## Output — `PATIENT_TEST_DETECTION_SPEC_INPUT.md` (mobile repo)
- Detection mechanism (Gemini vs catalog-match; server vs client; prompt/model or
  matching logic)
- Full test catalog (ids/names/panel mapping) + where defined
- Selection storage model (field/shape/discriminator) + the exact flow
- Prep-info structure + examples
- Reception display logic (field read + render)
- Mobile reuse: which Edge Function pattern to clone, and where the layer slots in
- Whether #8–#10 are stable or mid-change on web
- Redaction confirmation line

Keep it tight — this is the fact base for the SPEC. Do NOT build anything.
