// SYNC SOURCE: web constants.ts LAB_REFERENCE_RANGES + LAB_TEST_GROUPS. Case-sensitive. Do not edit without web sync. See Constraint #13.

class LabReferenceRange {
  final String parameter;
  final String unit;
  final double maleMin;
  final double maleMax;
  final double femaleMin;
  final double femaleMax;

  /// Outside this range the value is not a measurement (a typo or wrong unit),
  /// so it is refused rather than saved as flagged. Mirrors web `plausibleMin/Max`.
  final double plausibleMin;
  final double plausibleMax;

  const LabReferenceRange({
    required this.parameter,
    required this.unit,
    required this.maleMin,
    required this.maleMax,
    required this.femaleMin,
    required this.femaleMax,
    this.plausibleMin = double.negativeInfinity,
    this.plausibleMax = double.infinity,
  });
}

/// The refusal message for a value outside [range]'s plausible bounds, or null.
/// [entered] is echoed as typed, like web (`30.0` stays `30.0`).
String? labPlausibilityError(LabReferenceRange range, double value, {String? entered}) {
  if (value >= range.plausibleMin && value <= range.plausibleMax) return null;
  return '${range.parameter}: ${entered ?? _fmt(value)} ${range.unit} is outside the possible range '
      '(${_fmt(range.plausibleMin)}–${_fmt(range.plausibleMax)} ${range.unit}). '
      'Check the value and its unit.';
}

String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

const List<LabReferenceRange> kLabReferenceRanges = [
  LabReferenceRange(
    parameter: 'Hemoglobin',
    unit: 'g/dL',
    maleMin: 13.5,
    maleMax: 17.5,
    femaleMin: 12.0,
    femaleMax: 15.5,
    plausibleMin: 1,
    plausibleMax: 25,
  ),
  LabReferenceRange(
    parameter: 'White Blood Cells (WBC)',
    unit: 'x10^3/µL',
    maleMin: 4.5,
    maleMax: 11.0,
    femaleMin: 4.5,
    femaleMax: 11.0,
    plausibleMin: 0,
    plausibleMax: 1000,
  ),
  LabReferenceRange(
    parameter: 'Platelets',
    unit: 'x10^3/µL',
    maleMin: 150.0,
    maleMax: 450.0,
    femaleMin: 150.0,
    femaleMax: 450.0,
    plausibleMin: 0,
    plausibleMax: 5000,
  ),
  LabReferenceRange(
    parameter: 'Fasting Blood Sugar (FBS)',
    unit: 'mg/dL',
    maleMin: 70.0,
    maleMax: 100.0,
    femaleMin: 70.0,
    femaleMax: 100.0,
    plausibleMin: 5,
    plausibleMax: 3000,
  ),
  LabReferenceRange(
    parameter: 'Creatinine',
    unit: 'mg/dL',
    maleMin: 0.6,
    maleMax: 1.2,
    femaleMin: 0.5,
    femaleMax: 1.1,
    plausibleMin: 0.1,
    plausibleMax: 40,
  ),
  LabReferenceRange(
    parameter: 'Cholesterol',
    unit: 'mg/dL',
    maleMin: 100.0,
    maleMax: 200.0,
    femaleMin: 100.0,
    femaleMax: 200.0,
    plausibleMin: 20,
    plausibleMax: 2000,
  ),
];

const Map<String, List<String>> kLabTestGroups = {
  'Complete Blood Count (CBC)': [
    'Hemoglobin',
    'White Blood Cells (WBC)',
    'Platelets',
  ],
  'Fasting Blood Sugar (FBS)': [
    'Fasting Blood Sugar (FBS)',
  ],
  'Renal Function': [
    'Creatinine',
  ],
  'Lipid Profile': [
    'Cholesterol',
  ],
};

// SYNC SOURCE: web constants.ts LAB_NARRATIVE_TESTS + LAB_NARRATIVE_FIELDS +
// LAB_NARRATIVE_MAX_LENGTH. Case-sensitive, including spaces around the '/'.
// Narrative laboratory tests have no documented reference ranges, so they are
// recorded as text (Findings required, Impression optional) and are never
// flagged. Disjoint from the keys of kLabTestGroups above.
const List<String> kLabNarrativeTests = [
  'Urinalysis',
  'Fecalysis',
  'Blood Urea Nitrogen (BUN)',
  'SGPT / ALT',
  'SGOT / AST',
  'Lipid Profile (narrative)',
];

const List<String> kLabNarrativeFields = ['Findings', 'Impression'];

const int kLabNarrativeMaxLength = 5000;
