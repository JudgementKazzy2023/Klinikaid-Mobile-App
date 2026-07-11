// SYNC SOURCE: web constants.ts LAB_REFERENCE_RANGES + LAB_TEST_GROUPS. Case-sensitive. Do not edit without web sync. See Constraint #13.

class LabReferenceRange {
  final String parameter;
  final String unit;
  final double maleMin;
  final double maleMax;
  final double femaleMin;
  final double femaleMax;

  const LabReferenceRange({
    required this.parameter,
    required this.unit,
    required this.maleMin,
    required this.maleMax,
    required this.femaleMin,
    required this.femaleMax,
  });
}

const List<LabReferenceRange> kLabReferenceRanges = [
  LabReferenceRange(
    parameter: 'Hemoglobin',
    unit: 'g/dL',
    maleMin: 13.5,
    maleMax: 17.5,
    femaleMin: 12.0,
    femaleMax: 15.5,
  ),
  LabReferenceRange(
    parameter: 'White Blood Cells (WBC)',
    unit: 'x10^3/µL',
    maleMin: 4.5,
    maleMax: 11.0,
    femaleMin: 4.5,
    femaleMax: 11.0,
  ),
  LabReferenceRange(
    parameter: 'Platelets',
    unit: 'x10^3/µL',
    maleMin: 150.0,
    maleMax: 450.0,
    femaleMin: 150.0,
    femaleMax: 450.0,
  ),
  LabReferenceRange(
    parameter: 'Fasting Blood Sugar (FBS)',
    unit: 'mg/dL',
    maleMin: 70.0,
    maleMax: 100.0,
    femaleMin: 70.0,
    femaleMax: 100.0,
  ),
  LabReferenceRange(
    parameter: 'Creatinine',
    unit: 'mg/dL',
    maleMin: 0.6,
    maleMax: 1.2,
    femaleMin: 0.5,
    femaleMax: 1.1,
  ),
  LabReferenceRange(
    parameter: 'Cholesterol',
    unit: 'mg/dL',
    maleMin: 100.0,
    maleMax: 200.0,
    femaleMin: 100.0,
    femaleMax: 200.0,
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
