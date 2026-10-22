import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/features/auth/domain/registration_validators.dart';

// Expectations mirror web src/lib/validation.ts.
void main() {
  group('password (web PASSWORD_REGEX)', () {
    for (final ok in ['Abcdef1!', 'Xy9#xxxx', 'Pässw0rd!']) {
      test('accepts $ok', () => expect(RegistrationValidators.validatePassword(ok), isTrue));
    }
    for (final bad in ['abcdef1!', 'ABCDEF1!', 'Abcdefg!', 'Abcdefg1', 'Ab1!xyz']) {
      test('rejects $bad', () => expect(RegistrationValidators.validatePassword(bad), isFalse));
    }
  });

  group('names (web validateName)', () {
    for (final ok in ['Al', 'José', "O'Neil", 'Mary-Ann', 'Ma. Clara', '  Li  ']) {
      test('accepts "$ok"', () => expect(RegistrationValidators.validateName(ok), isTrue));
    }
    for (final bad in ['A', ' ', 'R2D2', 'Ann_Marie', 'x' * 101]) {
      test('rejects "${bad.length > 10 ? '${bad.length} chars' : bad}"',
          () => expect(RegistrationValidators.validateName(bad), isFalse));
    }
  });

  test('address is required and at most 255 characters', () {
    expect(RegistrationValidators.validateAddress('  '), isFalse);
    expect(RegistrationValidators.validateAddress('a' * 255), isTrue);
    expect(RegistrationValidators.validateAddress('a' * 256), isFalse);
  });

  test('+639 contact numbers are saved in the web 09 form', () {
    expect(RegistrationValidators.normalizeContactNumber(' +639171234567 '), '09171234567');
    expect(RegistrationValidators.normalizeContactNumber('09171234567'), '09171234567');
    expect(RegistrationValidators.normalizeContactNumber('+6391712345'), '+6391712345');
  });

  group('date of birth uses the Manila calendar day', () {
    // 2026-10-21 17:00 UTC is already 2026-10-22 01:00 in Manila.
    final now = DateTime.utc(2026, 10, 21, 17);
    String? dob(int y, int m, int d) =>
        RegistrationValidators.validateDob(DateTime(y, m, d), now: now);

    test('turns 18 on the Manila date, not the UTC date', () {
      expect(dob(2008, 10, 22), isNull);
      expect(dob(2008, 10, 23), contains('18'));
    });

    test('future dates are refused', () {
      expect(dob(2026, 10, 23), isNotNull);
    });

    test('exactly 120 years is allowed, older is refused', () {
      expect(dob(1906, 10, 22), isNull);
      expect(dob(1906, 10, 21), 'Please enter a realistic date of birth');
    });

    test('a 29 February birthday is not 18 until 1 March', () {
      final feb28 = DateTime.utc(2026, 2, 27, 17); // 2026-02-28 in Manila
      expect(RegistrationValidators.validateDob(DateTime(2008, 2, 29), now: feb28), contains('18'));
      final mar1 = DateTime.utc(2026, 2, 28, 17); // 2026-03-01 in Manila
      expect(RegistrationValidators.validateDob(DateTime(2008, 2, 29), now: mar1), isNull);
    });
  });
}
