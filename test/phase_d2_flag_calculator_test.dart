import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/features/department/domain/flag_calculator.dart';
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';

void main() {
  group('Phase D2: Flag Calculator Tests', () {
    final hgbRange = kLabReferenceRanges.firstWhere((r) => r.parameter == 'Hemoglobin');
    final wbcRange = kLabReferenceRanges.firstWhere((r) => r.parameter == 'White Blood Cells (WBC)');

    test('1. Hemoglobin male 13.5 (min boundary) is not flagged', () {
      expect(isValueFlagged(13.5, hgbRange, 'male'), isFalse);
    });

    test('2. Hemoglobin male 13.4 is flagged', () {
      expect(isValueFlagged(13.4, hgbRange, 'male'), isTrue);
    });

    test('3. Hemoglobin female 12.0 is not flagged, 11.9 is flagged (gender differentiation)', () {
      expect(isValueFlagged(12.0, hgbRange, 'female'), isFalse);
      expect(isValueFlagged(11.9, hgbRange, 'female'), isTrue);
    });

    test('4. Null gender uses male range', () {
      // Male min is 13.5, female min is 12.0. If null, should flag 13.0.
      expect(isValueFlagged(13.0, hgbRange, null), isTrue);
      expect(isValueFlagged(14.0, hgbRange, null), isFalse);
    });

    test('5. "other" gender uses male range', () {
      expect(isValueFlagged(13.0, hgbRange, 'other'), isTrue);
      expect(isValueFlagged(14.0, hgbRange, 'other'), isFalse);
    });

    test('6. "MALE" / "Female" case-insensitive checks', () {
      expect(isValueFlagged(13.0, hgbRange, 'MALE'), isTrue);
      expect(isValueFlagged(12.0, hgbRange, 'Female'), isFalse);
    });

    test('7. Value at max boundary (17.5) is not flagged, 17.6 is flagged', () {
      expect(isValueFlagged(17.5, hgbRange, 'male'), isFalse);
      expect(isValueFlagged(17.6, hgbRange, 'male'), isTrue);
    });

    test('8. WBC (identical M/F range) checks', () {
      expect(isValueFlagged(4.5, wbcRange, 'male'), isFalse);
      expect(isValueFlagged(4.5, wbcRange, 'female'), isFalse);
      expect(isValueFlagged(4.4, wbcRange, 'male'), isTrue);
      expect(isValueFlagged(11.0, wbcRange, 'female'), isFalse);
      expect(isValueFlagged(11.1, wbcRange, 'male'), isTrue);
    });
  });
}
