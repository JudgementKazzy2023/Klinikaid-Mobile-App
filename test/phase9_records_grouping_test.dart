import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';

void main() {
  group('Phase 9: Records Grouping Unit Tests', () {
    final patientId = 'patient-123';
    final recorderId = 'recorder-456';
    final now = DateTime.utc(2026, 6, 23, 9, 22, 13); // 2026-06-23 09:22:13

    DepartmentRecord createMockRecord({
      required String id,
      required Department department,
      required String testType,
      required ReferenceRangeStatus referenceRangeStatus,
      required DateTime createdAt,
      Map<String, dynamic>? testResults,
      String? notes,
    }) {
      return DepartmentRecord(
        id: id,
        patientId: patientId,
        recorderId: recorderId,
        department: department,
        testType: testType,
        testResults: testResults ?? {},
        referenceRangeStatus: referenceRangeStatus,
        notes: notes,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
    }

    test('1. Single row groups alone', () {
      final record = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Hemoglobin',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        notes: 'Notes text',
      );

      final groups = groupRecords([record]);

      expect(groups.length, 1);
      final group = groups.first;
      expect(group.patientId, patientId);
      expect(group.department, Department.laboratory);
      expect(group.isSingleParameter, true);
      expect(group.displayTitle, 'Hemoglobin');
      expect(group.aggregateStatus, ReferenceRangeStatus.normal);
      expect(group.aggregatedNotes, 'Notes text');
    });

    test('2. Two rows close in time, same patient/department, group together', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.imaging,
        testType: 'Leg X-ray',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        testResults: {'test_name': 'Findings', 'test_value': 'Torn Achilles Tendon'},
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.imaging,
        testType: 'Leg X-ray',
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 2)),
        testResults: {'test_name': 'Impression', 'test_value': 'Weak plantar flexion'},
      );

      final groups = groupRecords([rec1, rec2]);

      expect(groups.length, 1);
      final group = groups.first;
      expect(group.isSingleParameter, false);
      expect(group.records.length, 2);
      expect(group.displayTitle, 'Leg X-ray');
    });

    test('3. Two rows >5 minutes apart, same patient/department, do NOT group', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'CBC',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'CBC',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(minutes: 6)),
      );

      final groups = groupRecords([rec1, rec2]);

      expect(groups.length, 2);
      expect(groups[0].isSingleParameter, true);
      expect(groups[1].isSingleParameter, true);
    });

    test('4. Two rows close in time, same patient, DIFFERENT departments, do NOT group', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'CBC',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.imaging,
        testType: 'Leg X-ray',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(seconds: 10)),
      );

      final groups = groupRecords([rec1, rec2]);

      expect(groups.length, 2);
      expect(groups.any((g) => g.department == Department.laboratory), true);
      expect(groups.any((g) => g.department == Department.imaging), true);
    });

    test('5. Worst-case status wins (criticalHigh > inconclusive > normal)', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 2)),
      );
      final rec3 = createMockRecord(
        id: 'rec-3',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.criticalHigh,
        createdAt: now.add(const Duration(seconds: 4)),
      );

      final groups = groupRecords([rec1, rec2, rec3]);

      expect(groups.length, 1);
      expect(groups.first.aggregateStatus, ReferenceRangeStatus.criticalHigh);
    });

    test('6. All-NORMAL group -> NORMAL', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(seconds: 2)),
      );

      final groups = groupRecords([rec1, rec2]);
      expect(groups.first.aggregateStatus, ReferenceRangeStatus.normal);
    });

    test('7. All-INCONCLUSIVE group -> INCONCLUSIVE', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now,
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 2)),
      );

      final groups = groupRecords([rec1, rec2]);
      expect(groups.first.aggregateStatus, ReferenceRangeStatus.inconclusive);
    });

    test('8. Notes aggregation (one value and one null notes)', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        notes: 'First note',
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(seconds: 2)),
        notes: null,
      );

      final groups = groupRecords([rec1, rec2]);
      expect(groups.first.aggregatedNotes, 'First note');
    });

    test('9. Notes aggregation (both populated)', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        notes: 'First note  ',
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(seconds: 2)),
        notes: 'Second note',
      );

      final groups = groupRecords([rec1, rec2]);
      expect(groups.first.aggregatedNotes, 'First note\nSecond note');
    });

    test('9.5 Notes aggregation (identical notes are de-duplicated)', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        notes: 'Rest for the whole Season',
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now.add(const Duration(seconds: 2)),
        notes: '  Rest for the whole Season  ',
      );

      final groups = groupRecords([rec1, rec2]);
      expect(groups.first.aggregatedNotes, 'Rest for the whole Season');
    });

    test('10. 5-minute bucket alignment', () {
      // Row at 09:22:13
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 22, 13),
      );
      // Row at 09:24:58 (same bucket: 09:20-09:25)
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 24, 58),
      );
      // Row at 09:25:01 (different bucket: 09:25-09:30)
      final rec3 = createMockRecord(
        id: 'rec-3',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 25, 01),
      );

      final groups = groupRecords([rec1, rec2, rec3]);
      expect(groups.length, 2);
      expect(groups[0].records.length, 1); // 09:25 bucket
      expect(groups[1].records.length, 2); // 09:20 bucket
    });

    test('11. Stable ordering (most-recent bucket first, records within group sorted ascending)', () {
      final rec1 = createMockRecord(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 20, 10), // Earlier
      );
      final rec2 = createMockRecord(
        id: 'rec-2',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 24, 20), // Later
      );
      final rec3 = createMockRecord(
        id: 'rec-3',
        department: Department.laboratory,
        testType: 'Panel',
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: DateTime.utc(2026, 6, 23, 9, 31, 00), // Most recent bucket
      );

      final groups = groupRecords([rec1, rec2, rec3]);
      
      expect(groups.length, 2);
      // Most recent bucket group first
      expect(groups[0].bucketStart, DateTime.utc(2026, 6, 23, 9, 30).toLocal());
      
      // Older bucket group contains rec1 and rec2, sorted by createdAt ascending
      expect(groups[1].bucketStart, DateTime.utc(2026, 6, 23, 9, 20).toLocal());
      expect(groups[1].records.first.id, 'rec-1');
      expect(groups[1].records.last.id, 'rec-2');
    });
  });
}
