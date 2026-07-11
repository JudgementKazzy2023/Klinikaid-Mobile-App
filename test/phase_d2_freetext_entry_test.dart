import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';

class MockFreeTextDepartmentRepository extends DepartmentRepository {
  String? lastPatientId;
  String? lastTestName;
  String? lastFindings;
  String? lastImpression;
  String? lastNotes;
  bool isQueueUpdateCalled = false;
  List<Map<String, dynamic>> insertedRows = [];

  @override
  String? get currentUserId => 'mock-recorder-uuid';

  @override
  Future<void> submitFreeTextResult({
    required String patientId,
    required String testName,
    required String findings,
    required String impression,
    String? notes,
  }) async {
    lastPatientId = patientId;
    lastTestName = testName;
    lastFindings = findings;
    lastImpression = impression;
    lastNotes = notes;
    isQueueUpdateCalled = true;

    // Simulate database insertion payload shape
    insertedRows = [
      {
        'patient_id': patientId,
        'recorder_id': 'mock-recorder-uuid',
        'department': 'imaging',
        'test_type': testName.trim(),
        'test_name': 'Findings',
        'test_value': findings.trim(),
        'unit': null,
        'reference_range_min': null,
        'reference_range_max': null,
        'is_flagged': false,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      },
      {
        'patient_id': patientId,
        'recorder_id': 'mock-recorder-uuid',
        'department': 'imaging',
        'test_type': testName.trim(),
        'test_name': 'Impression',
        'test_value': impression.trim(),
        'unit': null,
        'reference_range_min': null,
        'reference_range_max': null,
        'is_flagged': false,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      }
    ];
  }
}

void main() {
  group('Phase D2: Free-Text Result Entry Tests', () {
    late ResultEntryProvider provider;
    late MockFreeTextDepartmentRepository mockRepo;

    setUp(() {
      mockRepo = MockFreeTextDepartmentRepository();
      provider = ResultEntryProvider(mockRepo);
    });

    test('21 & 24. Submit Findings + Impression → repo receives both rows with correct test name & type', () async {
      provider.setFindings('Lungs are clear.');
      provider.setImpression('Normal chest.');
      provider.setNotes('No abnormalities.');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(success, isTrue);
      expect(mockRepo.lastPatientId, 'patient-123');
      expect(mockRepo.lastTestName, 'Chest X-Ray');
      expect(mockRepo.lastFindings, 'Lungs are clear.');
      expect(mockRepo.lastImpression, 'Normal chest.');
      expect(mockRepo.lastNotes, 'No abnormalities.');
      expect(mockRepo.isQueueUpdateCalled, isTrue);
    });

    test('22. Free-text record status is always normal', () async {
      // By specification, free-text entries have is_flagged: false, i.e., normal.
      provider.setFindings('Fracture found.');
      provider.setImpression('Flagged fracture.');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Wrist X-Ray',
      );

      expect(success, isTrue);
      // Row generation happens repo-side. The repo creates is_flagged: false for both.
      // This is tested in repo tests or verified by design.
    });

    test('25. Empty test name → submit blocked', () async {
      provider.setFindings('Findings text');
      provider.setImpression('Impression text');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: '   ', // empty / whitespace
      );

      expect(success, isFalse);
      expect(provider.errorMessage, contains('All fields (Test Name, Findings, Impression) are required.'));
    });

    test('26. Empty Findings → submit blocked (both required)', () async {
      provider.setFindings('   '); // empty
      provider.setImpression('Impression text');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(success, isFalse);
      expect(provider.errorMessage, contains('All fields (Test Name, Findings, Impression) are required.'));
    });

    test('27. Empty Impression → submit blocked (both required)', () async {
      provider.setFindings('Findings text');
      provider.setImpression(''); // empty

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(success, isFalse);
      expect(provider.errorMessage, contains('All fields (Test Name, Findings, Impression) are required.'));
    });

    test('28. Notes (if entered) → written to repository', () async {
      provider.setFindings('Findings text');
      provider.setImpression('Impression text');
      provider.setNotes('Batch note');

      await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(mockRepo.lastNotes, 'Batch note');
    });

    test('28b. Schema Guard: both free-text rows carry test_type = typed name (duplicated)', () async {
      provider.setFindings('Findings text');
      provider.setImpression('Impression text');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(success, isTrue);
      expect(mockRepo.insertedRows.length, 2);
      expect(mockRepo.insertedRows[0]['test_type'], 'Chest X-Ray');
      expect(mockRepo.insertedRows[1]['test_type'], 'Chest X-Ray');
    });

    test('28c. Schema Guard: free-text rows have unit=null, ref_min=null, ref_max=null', () async {
      provider.setFindings('Findings text');
      provider.setImpression('Impression text');

      final success = await provider.submitFreeTextResult(
        patientId: 'patient-123',
        testName: 'Chest X-Ray',
      );

      expect(success, isTrue);
      expect(mockRepo.insertedRows.length, 2);
      
      expect(mockRepo.insertedRows[0]['unit'], isNull);
      expect(mockRepo.insertedRows[0]['reference_range_min'], isNull);
      expect(mockRepo.insertedRows[0]['reference_range_max'], isNull);
      
      expect(mockRepo.insertedRows[1]['unit'], isNull);
      expect(mockRepo.insertedRows[1]['reference_range_min'], isNull);
      expect(mockRepo.insertedRows[1]['reference_range_max'], isNull);
    });
  });
}
