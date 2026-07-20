# Patient OCR Test-Detection + Selection Recon Input

Source repo checked: `C:\Users\Ralph\Downloads\Setsuna KlinikAid`

Mobile repo checked: `C:\Users\Ralph\Downloads\Klinikaid Mobile app`

## Stability Pre-Check

#8-#10 appear separate from the current `employee_type` work. `employee_type` changes are in admin/staff/profile areas, while this feature is in patient submit, document detection utilities, and reception document review.

Relevant web files:
- `src/lib/documents/detectRequestedTests.ts`
- `src/lib/constants.ts`
- `src/app/(dashboard)/patient/submit/actions.ts`
- `src/app/(dashboard)/patient/submit/DocumentSubmitClient.tsx`
- `src/components/DocumentApprovalClient.tsx`
- `src/lib/db/migration_13.sql`
- `src/types/index.ts`

## 1. Detection Mechanism

Web test detection is not Gemini image classification. It is OCR text plus catalog matching.

Flow:
1. Patient uploads PDF/JPG/PNG in `DocumentSubmitClient`.
2. Server action `assessDocumentQualityAction` uploads the source file to `patient-documents`.
3. `extractDocumentText(fileBuffer, file.type)` extracts OCR text using Google Generative AI.
4. If OCR text is poor/empty/refusal-like, detection is skipped and `detectedTests = []`.
5. If OCR text is usable, `detectRequestedTests(storedOcrText)` runs catalog matching.

Detection implementation:
```ts
function normalizeText(value: string) {
  return value.toLowerCase().replace(/\s+/g, " ").trim();
}

export function detectRequestedTests(ocrText: string): DetectedClinicTest[] {
  const normalizedText = normalizeText(ocrText);
  if (!normalizedText) return [];

  return CLINIC_TEST_CATALOG.filter((test) =>
    test.aliases.some((alias) => normalizedText.includes(normalizeText(alias)))
  ).map(({ id, label }) => ({ id, label }));
}
```

Matching type: normalized substring match against aliases. No fuzzy matching. No prompt/model specifically for test detection.

Server/client boundary:
- OCR extraction happens server-side in web.
- Detection itself is server-side in `actions.ts`, using already-extracted OCR text.
- Patient checkbox selection is client-side UI, then submitted back to server.

Mobile implication:
- Mobile can reuse on-device ML Kit OCR text or a server OCR function, then run the same catalog match.
- If server parity is preferred, create a new Edge Function that accepts OCR text or image and returns the same `{ id, label }[]` shape. Do not put any Gemini key in mobile.

## 2. Full Test Catalog

Defined in web `src/lib/constants.ts` as `CLINIC_TEST_CATALOG`.

Current catalog:

| id | label | aliases |
|---|---|---|
| `cbc` | `Complete Blood Count (CBC)` | `cbc`, `complete blood count`, `hematology`, `hemoglobin`, `white blood cells`, `wbc`, `platelets` |
| `urinalysis` | `Urinalysis` | `urinalysis`, `urine`, `urine analysis`, `routine urinalysis`, `clinical microscopy`, `urine test`, `ua` |
| `fecalysis` | `Fecalysis` | `fecalysis`, `routine fecalysis`, `stool`, `stool exam`, `stool examination`, `fecal exam` |
| `fbs` | `Fasting Blood Sugar (FBS)` | `fbs`, `fasting blood sugar`, `blood sugar`, `fasting glucose`, `glucose` |
| `lipid_profile` | `Lipid Profile` | `lipid`, `lipid profile`, `cholesterol`, `triglycerides`, `hdl`, `ldl` |
| `creatinine` | `Creatinine` | `creatinine`, `serum creatinine`, `renal function`, `kidney function` |
| `bun` | `Blood Urea Nitrogen (BUN)` | `bun`, `blood urea nitrogen`, `urea nitrogen` |
| `sgpt_alt` | `SGPT / ALT` | `sgpt`, `alt`, `alanine aminotransferase` |
| `sgot_ast` | `SGOT / AST` | `sgot`, `ast`, `aspartate aminotransferase` |
| `chest_xray` | `Chest X-ray` | `chest x-ray`, `chest xray`, `cxr`, `x-ray chest`, `xray chest`, `chest radiograph` |
| `ecg` | `ECG` | `ecg`, `ekg`, `electrocardiogram` |
| `ultrasound` | `Ultrasound` | `ultrasound`, `ultrasonography`, `utz` |

This is a broader orderable-test catalog, not only the four mobile lab-result panels. It includes laboratory, imaging, ultrasound, and ECG entries.

Detection returns only:
```ts
type DetectedClinicTest = Pick<ClinicTestCatalogItem, "id" | "label">;
```

So the persisted selected/detected item shape is:
```json
{ "id": "fbs", "label": "Fasting Blood Sugar (FBS)" }
```

## 3. Selection + Storage Data Model

Selection UI:
- `DocumentSubmitClient.tsx` shows detected tests as checkbox rows.
- All detected tests are selected by default:
```ts
setSelectedTestIds(result.detectedTests.map((test) => test.id));
```
- User can toggle each checkbox.
- Submit button changes to `Submit Selected Tests`.

Selection happens before final document submit:
1. First submit runs assessment/OCR/detection and stores a pending row.
2. If detected tests exist, client pauses on checkbox selection.
3. Second submit calls `confirmSubmitDocumentAction(assessmentId, selectedTestIds)`.
4. Server recomputes `detectedTests` from pending OCR text.
5. Server filters submitted ids through `selectDetectedTests(detectedTests, selectedTestIds)`.
6. Final `documents` row is inserted.

Temporary storage:
- Table: `pending_document_ocr`
- Defined in `src/lib/db/migration_13.sql`
- Stores uploaded pending file path, OCR text, and token counts.
- Important columns:
  - `id uuid`
  - `user_id uuid`
  - `patient_id uuid`
  - `file_name text`
  - `file_type text`
  - `file_path text`
  - `ocr_text text`
  - `prompt_token_count integer`
  - `candidates_token_count integer`
  - `total_token_count integer`

Final storage:
- Table: `documents`
- Column: `extracted_metadata jsonb`
- Type is `Record<string, unknown> | null` in `src/types/index.ts`.

When detected tests exist, web writes:
```json
{
  "detected_tests": [
    { "id": "cbc", "label": "Complete Blood Count (CBC)" }
  ],
  "selected_tests": [
    { "id": "cbc", "label": "Complete Blood Count (CBC)" }
  ],
  "test_detection_source": "ocr_text_catalog_match",
  "test_detection_version": 1
}
```

If no tests are detected, `extracted_metadata` for this feature is not added by the web submit action.

## 4. Prep Info Per Test

Defined in web `src/lib/constants.ts` as `CLINIC_TEST_PREP_INSTRUCTIONS`.

Shape:
```ts
export const CLINIC_TEST_PREP_INSTRUCTIONS: Record<string, string> = {
  cbc: "No special preparation needed.",
  fbs: "Fast for 8 hours before the test. Water is allowed.",
  lipid_profile: "Fast for 9-12 hours before the test. Water is allowed.",
};
```

Full current map:
- `cbc`: No special preparation needed.
- `urinalysis`: No special preparation needed. Collect a clean midstream sample if instructed.
- `fecalysis`: No special preparation needed.
- `fbs`: Fast for 8 hours before the test. Water is allowed.
- `lipid_profile`: Fast for 9-12 hours before the test. Water is allowed.
- `creatinine`: No special preparation needed.
- `bun`: No special preparation needed.
- `sgpt_alt`: No special preparation needed.
- `sgot_ast`: No special preparation needed.
- `chest_xray`: Remove metal objects and jewelry. Inform staff if you may be pregnant.
- `ecg`: No special preparation needed.
- `ultrasound`: Preparation varies by type - please follow the specific instructions from your clinic.

Web renders each detected checkbox with:
```tsx
{CLINIC_TEST_PREP_INSTRUCTIONS[test.id]}
```

## 5. Reception Display

Reception document details page:
- `src/app/(dashboard)/reception/queue/[documentId]/page.tsx`
- Fetches `documents.*`, patient, and uploader.
- Passes the row to `DocumentApprovalClient`.

`DocumentApprovalClient` reads:
```ts
const metadata = doc.extracted_metadata as {
  detected_tests?: DetectedClinicTest[];
  selected_tests?: DetectedClinicTest[];
  test_detection_source?: string;
  test_detection_version?: number;
} | null;

const selectedTests = metadata?.selected_tests || [];
```

Render logic:
- If `selectedTests.length > 0`, show a `Patient-selected Tests` section in the document metadata card.
- Each selected test is rendered as an emerald outline badge using `test.label`.

The reception API/list query does not transform the selected tests; it returns `documents.*`, so the display reads directly from `documents.extracted_metadata.selected_tests`.

## 6. Mobile Reuse

Existing mobile patient upload flow:
- `lib/features/documents/presentation/screens/submit_document_screen.dart`
- `lib/features/documents/presentation/providers/document_submission_provider.dart`
- User picks/captures image through `image_picker`.
- Mobile performs on-device OCR via ML Kit:
```dart
TextRecognizer(script: TextRecognitionScript.latin)
```
- Mobile calls `assess-document-quality` Edge Function via `DocumentQualityService`.
- `preScreenMetadata` currently includes:
```json
{
  "ocr_text": "...",
  "quality_assessment": {},
  "identity_match": true,
  "submitted_with_warnings": false
}
```
- On submit, mobile writes `Document.extractedMetadata = metadata` and adds:
```json
{ "document_type": "<selected document type>" }
```

Existing mobile Edge Function patterns:
- `assess-document-quality`: mobile sends OCR text to a Supabase Edge Function.
- `extract-lab-values`: mobile sends image base64 to a Supabase Edge Function and receives structured JSON.

Recommended mobile insertion point:
1. After `processOnDeviceOcr` obtains `ocrText`.
2. Run catalog detection against the same catalog.
3. If detected tests exist, show checkbox selection + prep notes before final submit.
4. Store web-compatible metadata:
```json
{
  "detected_tests": [{ "id": "fbs", "label": "Fasting Blood Sugar (FBS)" }],
  "selected_tests": [{ "id": "fbs", "label": "Fasting Blood Sugar (FBS)" }],
  "test_detection_source": "ocr_text_catalog_match",
  "test_detection_version": 1
}
```
5. Preserve existing metadata keys: `ocr_text`, `quality_assessment`, `identity_match`, `submitted_with_warnings`, `document_type`.

Implementation choice for mobile spec:
- Lowest-risk parity: port `CLINIC_TEST_CATALOG`, `CLINIC_TEST_PREP_INSTRUCTIONS`, and the exact normalized substring matcher into Dart.
- Server-side option: create a new Edge Function if the team wants detection centralized. It can accept OCR text and return `DetectedClinicTest[]`; no Gemini needed unless replacing the current catalog matcher.

## Open Design Questions For Mobile SPEC

- Should mobile use on-device ML Kit OCR text for detection, matching current mobile flow, or send image/OCR text to a new Edge Function for centralized parity?
- Should mobile mirror web's pending assessment step, or keep its current single local cached submission flow and only add selection metadata before `submitDocument`?
- Should mobile allow submitting with zero selected tests after detection? Web allows toggling all off, resulting in `selected_tests: []`.
- Should mobile show selected tests in any mobile receptionist/validation view, or is web reception the only required display?

## Redaction Confirmation

No secrets, service-role keys, anon keys, passwords, or real patient data were copied into this document. Paths and code shapes only.
