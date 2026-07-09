class RegistrationValidators {
  /// Validates standard email format
  static bool validateEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(trimmed);
  }

  /// Validates password rules:
  /// - Minimum 8 characters
  /// - At least 1 digit (0-9)
  /// - At least 1 special character (any non-alphanumeric)
  static bool validatePassword(String password) {
    if (password.length < 8) return false;
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    // Any character that is NOT a letter (a-z, A-Z) or digit (0-9)
    if (!RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) return false;
    return true;
  }

  /// Validates first name: minimum 3 characters after trim
  static bool validateFirstName(String firstName) {
    return firstName.trim().length >= 3;
  }

  /// Validates last name: non-empty after trim
  static bool validateLastName(String lastName) {
    return lastName.trim().isNotEmpty;
  }

  /// Validates date of birth:
  /// - Cannot be future date
  /// - Cannot be today or yesterday (block obvious garbage)
  /// - Cannot be more than 120 years ago
  /// - Enforces hard 13+ age minimum
  static String? validateDob(DateTime? dob) {
    if (dob == null) return 'Date of birth is required';
    
    final now = DateTime.now();
    
    // Future date
    if (dob.isAfter(now)) {
      return 'Please enter a realistic date of birth';
    }
    
    // Today or yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (!dob.isBefore(yesterday.subtract(const Duration(days: 1)))) {
      return 'Please enter a realistic date of birth';
    }
    
    // > 120 years ago
    final maxAge = now.subtract(const Duration(days: 365 * 120));
    if (dob.isBefore(maxAge)) {
      return 'Please enter a realistic date of birth';
    }
    
    // Under 13
    final age = now.year - dob.year
      - (now.month < dob.month || 
         (now.month == dob.month && now.day < dob.day) ? 1 : 0);
    if (age < 13) {
      return 'You must be 13 years old or older to register';
    }
    
    return null; // valid
  }

  /// Validates Philippine contact format: ^(09|\+639)\d{9}$
  static bool validateContactNumber(String contactNumber) {
    final trimmed = contactNumber.trim();
    return RegExp(r'^(09|\+639)\d{9}$').hasMatch(trimmed);
  }

  /// Validates address: non-empty after trim
  static bool validateAddress(String address) {
    return address.trim().isNotEmpty;
  }
}
