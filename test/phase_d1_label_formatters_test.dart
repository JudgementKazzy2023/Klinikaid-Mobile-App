import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/utils/role_formatter.dart';
import 'package:klinikaid_mobile/core/utils/reference_status_formatter.dart';

void main() {
  group('roleDisplayLabel — dept-specific labels for departmentStaff', () {
    test('laboratory → "Laboratory Staff"', () {
      expect(
        roleDisplayLabel(UserRole.departmentStaff, Department.laboratory),
        'Laboratory Staff',
      );
    });

    test('imaging → "Imaging Staff"', () {
      expect(
        roleDisplayLabel(UserRole.departmentStaff, Department.imaging),
        'Imaging Staff',
      );
    });

    test('ultrasound → "Ultrasound Staff"', () {
      expect(
        roleDisplayLabel(UserRole.departmentStaff, Department.ultrasound),
        'Ultrasound Staff',
      );
    });

    test('ecg → "ECG Staff"', () {
      expect(
        roleDisplayLabel(UserRole.departmentStaff, Department.ecg),
        'ECG Staff',
      );
    });

    test('null department → fallback "Department Staff"', () {
      expect(
        roleDisplayLabel(UserRole.departmentStaff, null),
        'Department Staff',
      );
    });

    test('non-dept roles are unchanged', () {
      expect(roleDisplayLabel(UserRole.receptionist, null), 'Receptionist');
      expect(roleDisplayLabel(UserRole.medicalSpecialist, null), 'Medical Specialist');
      expect(roleDisplayLabel(UserRole.patient, null), 'Patient');
      expect(roleDisplayLabel(UserRole.admin, null), 'Admin');
    });
  });

  group('referenceStatusDisplayLabel — collapsed normal/flagged labels', () {
    test('normal → "Normal"', () {
      expect(referenceStatusDisplayLabel(ReferenceRangeStatus.normal), 'Normal');
    });

    test('flagged → "Flagged"', () {
      expect(referenceStatusDisplayLabel(ReferenceRangeStatus.flagged), 'Flagged');
    });

    test('inconclusive → "Inconclusive"', () {
      expect(
        referenceStatusDisplayLabel(ReferenceRangeStatus.inconclusive),
        'Inconclusive',
      );
    });
  });

  group('ReferenceRangeStatus.fromString — legacy DB value mapping', () {
    test('critical_high maps to flagged', () {
      expect(
        ReferenceRangeStatus.fromString('critical_high'),
        ReferenceRangeStatus.flagged,
      );
    });

    test('critical_low maps to flagged', () {
      expect(
        ReferenceRangeStatus.fromString('critical_low'),
        ReferenceRangeStatus.flagged,
      );
    });

    test('flagged maps to flagged', () {
      expect(
        ReferenceRangeStatus.fromString('flagged'),
        ReferenceRangeStatus.flagged,
      );
    });

    test('normal maps to normal', () {
      expect(
        ReferenceRangeStatus.fromString('normal'),
        ReferenceRangeStatus.normal,
      );
    });

    test('unknown string defaults to normal', () {
      expect(
        ReferenceRangeStatus.fromString('unknown_value'),
        ReferenceRangeStatus.normal,
      );
    });
  });

  group('isStatusFlagged', () {
    test('flagged → true', () {
      expect(isStatusFlagged(ReferenceRangeStatus.flagged), isTrue);
    });

    test('normal → false', () {
      expect(isStatusFlagged(ReferenceRangeStatus.normal), isFalse);
    });

    test('inconclusive → false', () {
      expect(isStatusFlagged(ReferenceRangeStatus.inconclusive), isFalse);
    });
  });
}
