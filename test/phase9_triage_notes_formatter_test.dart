import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/utils/triage_notes_formatter.dart';

void main() {
  group('Phase 9: Triage Notes Formatter Unit Tests', () {
    test('null input returns null', () {
      expect(extractTriageNotes(null), isNull);
    });

    test('empty string input returns null', () {
      expect(extractTriageNotes(''), isNull);
      expect(extractTriageNotes('   '), isNull);
    });

    test('valid JSON with notes returns extracted notes', () {
      expect(
        extractTriageNotes('{"notes":"Testing","queue_number":"ECG-001"}'),
        equals('Testing'),
      );
    });

    test('valid JSON with empty notes returns null', () {
      expect(
        extractTriageNotes('{"notes":"","queue_number":"ECG-001"}'),
        isNull,
      );
    });

    test('valid JSON with null notes returns null', () {
      expect(
        extractTriageNotes('{"notes":null,"queue_number":"ECG-001"}'),
        isNull,
      );
    });

    test('valid JSON with missing notes field returns null', () {
      expect(
        extractTriageNotes('{"queue_number":"ECG-001"}'),
        isNull,
      );
    });

    test('plain text input returns text as-is (legacy fallback)', () {
      expect(
        extractTriageNotes('Plain text note'),
        equals('Plain text note'),
      );
    });

    test('valid JSON with surrounding spaces and internal note spaces returns trimmed note', () {
      expect(
        extractTriageNotes('  {"notes":"  Testing  "}'),
        equals('Testing'),
      );
    });

    test('invalid json input returns input string as-is (legacy fallback)', () {
      expect(
        extractTriageNotes('{invalid json'),
        equals('{invalid json'),
      );
    });
  });
}
