class ClinicTest {
  final String id;
  final String label;
  final List<String> aliases;

  const ClinicTest({
    required this.id,
    required this.label,
    required this.aliases,
  });

  Map<String, String> toDetectedJson() => {
        'id': id,
        'label': label,
      };
}

const List<ClinicTest> clinicTestCatalog = [
  ClinicTest(
    id: 'cbc',
    label: 'Complete Blood Count (CBC)',
    aliases: ['cbc', 'complete blood count', 'hematology', 'hemoglobin', 'white blood cells', 'wbc', 'platelets'],
  ),
  ClinicTest(
    id: 'urinalysis',
    label: 'Urinalysis',
    aliases: ['urinalysis', 'urine', 'urine analysis', 'routine urinalysis', 'clinical microscopy', 'urine test', 'ua'],
  ),
  ClinicTest(
    id: 'fecalysis',
    label: 'Fecalysis',
    aliases: ['fecalysis', 'routine fecalysis', 'stool', 'stool exam', 'stool examination', 'fecal exam'],
  ),
  ClinicTest(
    id: 'fbs',
    label: 'Fasting Blood Sugar (FBS)',
    aliases: ['fbs', 'fasting blood sugar', 'blood sugar', 'fasting glucose', 'glucose'],
  ),
  ClinicTest(
    id: 'lipid_profile',
    label: 'Lipid Profile',
    aliases: ['lipid', 'lipid profile', 'cholesterol', 'triglycerides', 'hdl', 'ldl'],
  ),
  ClinicTest(
    id: 'creatinine',
    label: 'Creatinine',
    aliases: ['creatinine', 'serum creatinine', 'renal function', 'kidney function'],
  ),
  ClinicTest(
    id: 'bun',
    label: 'Blood Urea Nitrogen (BUN)',
    aliases: ['bun', 'blood urea nitrogen', 'urea nitrogen'],
  ),
  ClinicTest(
    id: 'sgpt_alt',
    label: 'SGPT / ALT',
    aliases: ['sgpt', 'alt', 'alanine aminotransferase'],
  ),
  ClinicTest(
    id: 'sgot_ast',
    label: 'SGOT / AST',
    aliases: ['sgot', 'ast', 'aspartate aminotransferase'],
  ),
  ClinicTest(
    id: 'chest_xray',
    label: 'Chest X-ray',
    aliases: ['chest x-ray', 'chest xray', 'cxr', 'x-ray chest', 'xray chest', 'chest radiograph'],
  ),
  ClinicTest(
    id: 'ecg',
    label: 'ECG',
    aliases: ['ecg', 'ekg', 'electrocardiogram'],
  ),
  ClinicTest(
    id: 'ultrasound',
    label: 'Ultrasound',
    aliases: ['ultrasound', 'ultrasonography', 'utz'],
  ),
];

const Map<String, String> clinicTestPrepInstructions = {
  'cbc': 'No special preparation needed.',
  'urinalysis': 'No special preparation needed. Collect a clean midstream sample if instructed.',
  'fecalysis': 'No special preparation needed.',
  'fbs': 'Fast for 8 hours before the test. Water is allowed.',
  'lipid_profile': 'Fast for 9-12 hours before the test. Water is allowed.',
  'creatinine': 'No special preparation needed.',
  'bun': 'No special preparation needed.',
  'sgpt_alt': 'No special preparation needed.',
  'sgot_ast': 'No special preparation needed.',
  'chest_xray': 'Remove metal objects and jewelry. Inform staff if you may be pregnant.',
  'ecg': 'No special preparation needed.',
  'ultrasound': 'Preparation varies by type - please follow the specific instructions from your clinic.',
};

String normalizeClinicTestText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<ClinicTest> detectRequestedTests(String ocrText) {
  final normalizedText = normalizeClinicTestText(ocrText);

  if (normalizedText.isEmpty) {
    return [];
  }

  return clinicTestCatalog
      .where(
        (test) => test.aliases.any(
          (alias) => normalizedText.contains(normalizeClinicTestText(alias)),
        ),
      )
      .toList();
}

List<Map<String, String>> clinicTestsToMetadata(List<ClinicTest> tests) {
  return tests.map((test) => test.toDetectedJson()).toList();
}

Map<String, dynamic> buildTestDetectionMetadata({
  required List<ClinicTest> detectedTests,
  required List<String> selectedTestIds,
}) {
  if (detectedTests.isEmpty) {
    return const {};
  }

  final selectedIdSet = selectedTestIds.toSet();
  final selectedTests = detectedTests.where((test) => selectedIdSet.contains(test.id)).toList();

  return {
    'detected_tests': clinicTestsToMetadata(detectedTests),
    'selected_tests': clinicTestsToMetadata(selectedTests),
    'test_detection_source': 'ocr_text_catalog_match',
    'test_detection_version': 1,
  };
}

List<Map<String, dynamic>> readSelectedTests(Map<String, dynamic>? metadata) {
  final raw = metadata?['selected_tests'];
  if (raw is! List) return const [];

  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .where((item) => item['id'] is String && item['label'] is String)
      .toList();
}
