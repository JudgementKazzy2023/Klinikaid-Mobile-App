class RegistrationValidators {
  static const int minimumRegistrationAge = 18;

  /// Validates common email syntax, including plus tags and long TLDs.
  static bool validateEmail(String email) {
    final trimmed = email.trim();
    return RegExp(
      r"^[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$",
    ).hasMatch(trimmed);
  }

  // Rules below mirror web src/lib/validation.ts.
  static const passwordRequirementText =
      'Password must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character.';
  static const nameMaxLength = 100;
  static const addressMaxLength = 255;

  /// 8+ characters with an uppercase letter, a lowercase letter, a digit and a
  /// special character (web PASSWORD_REGEX).
  static bool validatePassword(String password) {
    return RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,}$')
        .hasMatch(password);
  }

  /// 2-100 characters after trim; letters (incl. accented), spaces, hyphens,
  /// apostrophes and periods only (web validateName).
  static bool validateName(String name) {
    final trimmed = name.trim();
    return trimmed.length >= 2 &&
        trimmed.length <= nameMaxLength &&
        RegExp(r"^[A-Za-zÀ-ÿ\s\-'\.]+$").hasMatch(trimmed);
  }

  static String nameFieldMessage(String label) =>
      '$label must be 2-$nameMaxLength characters and contain only letters, spaces, hyphens, apostrophes, or periods.';

  static bool validateFirstName(String firstName) => validateName(firstName);

  static bool validateLastName(String lastName) => validateName(lastName);

  /// Validates date of birth against today's calendar date in Manila (UTC+8,
  /// no DST), like web: not in the future, at most 120 years ago, and 18+.
  static String? validateDob(DateTime? dob, {DateTime? now}) {
    if (dob == null) return 'Date of birth is required';

    final manila = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    int compare(int y1, int m1, int d1, int y2, int m2, int d2) =>
        y1 != y2 ? y1 - y2 : (m1 != m2 ? m1 - m2 : d1 - d2);

    if (compare(dob.year, dob.month, dob.day, manila.year, manila.month, manila.day) > 0) {
      return 'Please enter a realistic date of birth';
    }
    if (compare(dob.year, dob.month, dob.day, manila.year - 120, manila.month, manila.day) < 0) {
      return 'Please enter a realistic date of birth';
    }
    if (compare(dob.year + minimumRegistrationAge, dob.month, dob.day, manila.year, manila.month, manila.day) > 0) {
      return 'You must be 18 years old or older to register';
    }
    return null; // valid
  }

  /// Validates Philippine contact format: ^(09|\+639)\d{9}$. Web stores only
  /// the 09 form, so save through [normalizeContactNumber].
  static bool validateContactNumber(String contactNumber) {
    final trimmed = contactNumber.trim();
    return RegExp(r'^(09|\+639)\d{9}$').hasMatch(trimmed);
  }

  /// `+639XXXXXXXXX` -> `09XXXXXXXXX` (web CONTACT_REGEX is `^09\d{9}$`).
  static String normalizeContactNumber(String contactNumber) {
    final trimmed = contactNumber.trim();
    return RegExp(r'^\+639\d{9}$').hasMatch(trimmed)
        ? '0${trimmed.substring(3)}'
        : trimmed;
  }

  static const addressFieldMessage =
      'Address is required and must be no more than $addressMaxLength characters.';

  /// Address is required and at most 255 characters (web validateAddress).
  static bool validateAddress(String address) {
    final trimmed = address.trim();
    return trimmed.isNotEmpty && trimmed.length <= addressMaxLength;
  }
}
