import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';

class MockDepartmentRepository extends DepartmentRepository {
  String? lastPatientId;
  List<LabResultRow>? lastRows;
  bool shouldThrow = false;
  bool isQueueUpdateCalled = false;

  @override
  String? get currentUserId => 'mock-recorder-uuid';

  @override
  Future<void> submitLabResults({
    required String patientId,
    required List<LabResultRow> rows,
  }) async {
    if (shouldThrow) {
      throw Exception('Database insert error');
    }
    lastPatientId = patientId;
    lastRows = rows;
    isQueueUpdateCalled = true;
  }
}

void main() {
  group('Phase D2: Laboratory Result Entry Tests', () {
    late ResultEntryProvider provider;
    late MockDepartmentRepository mockRepo;

    setUp(() {
      mockRepo = MockDepartmentRepository();
      provider = ResultEntryProvider(mockRepo);
    });

    test('9. CBC group parameter membership', () {
      expect(
        kLabTestGroups['Complete Blood Count (CBC)'],
        containsAll(['Hemoglobin', 'White Blood Cells (WBC)', 'Platelets']),
      );
    });

    test('10. Enter 3 values → submit → repo receives 3 rows', () async {
      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setParameterValue('Hemoglobin', '14.0');
      provider.setParameterValue('White Blood Cells (WBC)', '7.0');
      provider.setParameterValue('Platelets', '250.0');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isTrue);
      expect(mockRepo.lastPatientId, 'patient-123');
      expect(mockRepo.lastRows?.length, 3);
    });

    test('11. One param flagged → record status is flagged (derived on read)', () {
      // Simulate reading a record where is_flagged is true (derived)
      final recordJson = {
        'id': 'record-123',
        'patient_id': 'patient-123',
        'recorder_id': 'recorder-456',
        'department': 'laboratory',
        'test_type': 'Complete Blood Count (CBC)',
        'is_flagged': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      final record = DepartmentRecord.fromJson(recordJson);
      expect(record.referenceRangeStatus, ReferenceRangeStatus.flagged);
    });

    test('12. All params normal → record status is normal (derived on read)', () {
      final recordJson = {
        'id': 'record-123',
        'patient_id': 'patient-123',
        'recorder_id': 'recorder-456',
        'department': 'laboratory',
        'test_type': 'Complete Blood Count (CBC)',
        'is_flagged': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      final record = DepartmentRecord.fromJson(recordJson);
      expect(record.referenceRangeStatus, ReferenceRangeStatus.normal);
    });

    test('13. Empty param skipped, remaining submitted', () async {
      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setParameterValue('Hemoglobin', '14.0');
      provider.setParameterValue('Platelets', '250.0');
      // WBC left empty

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isTrue);
      expect(mockRepo.lastRows?.length, 2);
      expect(mockRepo.lastRows?[0].testName, 'Hemoglobin');
      expect(mockRepo.lastRows?[1].testName, 'Platelets');
    });

    test('14. All params empty → submit blocked', () async {
      provider.setLabGroup('Complete Blood Count (CBC)');
      
      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isFalse);
      expect(provider.errorMessage, 'Please enter at least one parameter value.');
      expect(mockRepo.lastRows, isNull);
    });

    test('15. Decimal value accepted', () async {
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', '0.85');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isTrue);
      expect(mockRepo.lastRows?[0].testValue, '0.85');
    });

    test('16. Submit success → queue update is triggered', () async {
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', '0.85');

      await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(mockRepo.isQueueUpdateCalled, isTrue);
    });

    test('17. Insert fails → error surfaced gracefully', () async {
      mockRepo.shouldThrow = true;
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', '0.85');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isFalse);
      expect(provider.errorMessage, contains('Database insert error'));
    });

    test('18. Stringification check: numeric value (10.5) is inserted as string "10.5"', () async {
      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setParameterValue('Hemoglobin', '10.5');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isTrue);
      expect(mockRepo.lastRows?[0].testValue, '10.5');
      expect(mockRepo.lastRows?[0].testValue, isA<String>());
    });

    test('19. Stored range check: female Creatinine row resolves range (0.5 to 1.1)', () async {
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', '0.8');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'female',
      );

      expect(success, isTrue);
      expect(mockRepo.lastRows?[0].referenceRangeMin, 0.5);
      expect(mockRepo.lastRows?[0].referenceRangeMax, 1.1);
    });

    test('20. Stored range check (mirror): null gender Creatinine row defaults to male range (0.6 to 1.2)', () async {
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', '0.8');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: null,
      );

      expect(success, isTrue);
      expect(mockRepo.lastRows?[0].referenceRangeMin, 0.6);
      expect(mockRepo.lastRows?[0].referenceRangeMax, 1.2);
    });

    test('Extra: Non-numeric input blocks submission with error', () async {
      provider.setLabGroup('Renal Function');
      provider.setParameterValue('Creatinine', 'abc');

      final success = await provider.submitLabResults(
        patientId: 'patient-123',
        gender: 'male',
      );

      expect(success, isFalse);
      expect(provider.errorMessage, contains('Invalid numeric input'));
    });
  });
}
