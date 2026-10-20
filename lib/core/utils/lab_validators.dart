import 'package:flutter/services.dart';

class MaxIntegerDigitsFormatter extends TextInputFormatter {
  final int maxIntegerDigits;
  final int maxDecimalDigits;

  const MaxIntegerDigitsFormatter(this.maxIntegerDigits, {this.maxDecimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final regExp = RegExp('^\\d{0,$maxIntegerDigits}(\\.\\d{0,$maxDecimalDigits})?\$');
    if (regExp.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

class BloodPressureFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final text = newValue.text;
    if (!RegExp(r'^[0-9/]*$').hasMatch(text)) {
      return oldValue;
    }
    if ('/'.allMatches(text).length > 1) {
      return oldValue;
    }
    final parts = text.split('/');
    if (parts[0].length > 3) {
      return oldValue;
    }
    if (parts.length > 1 && parts[1].length > 3) {
      return oldValue;
    }
    return newValue;
  }
}

String? validateBloodPressure(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d{2,3})/(\d{2,3})$').firstMatch(trimmed);
  if (match == null) {
    return 'BP must be in NNN/NNN format';
  }
  // Match the shared web triage contract; these are input bounds, not targets.
  final systolic = int.parse(match.group(1)!);
  final diastolic = int.parse(match.group(2)!);
  if (systolic < 40 || systolic > 300 || diastolic < 20 || diastolic > 200) {
    return 'Systolic must be 40-300 and diastolic 20-200 mmHg.';
  }
  if (systolic <= diastolic) {
    return 'Systolic must be higher than diastolic.';
  }
  return null;
}

String? validateVitalsValue(
  String? text, {
  required int maxIntegerDigits,
  required int maxDecimalDigits,
}) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final charsRegExp = RegExp(r'^[0-9.]*$');
  if (!charsRegExp.hasMatch(trimmed)) {
    return 'Enter numeric characters only';
  }
  if ('.'.allMatches(trimmed).length > 1) {
    return 'Enter a valid decimal number';
  }
  final val = double.tryParse(trimmed);
  if (val == null || val.isNaN || val.isInfinite || val < 0) {
    return 'Enter a valid positive number';
  }
  final parts = trimmed.split('.');
  final integerPart = parts[0];
  if (integerPart.isEmpty || integerPart.length > maxIntegerDigits) {
    return 'Integer part must be 1-$maxIntegerDigits digits';
  }
  if (parts.length > 1) {
    final decimalPart = parts[1];
    if (decimalPart.length > maxDecimalDigits) {
      return 'Max $maxDecimalDigits decimal places';
    }
  }
  return null;
}

String? validateLabValue(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  // Check for allowed characters: only 0-9 and a single '.'
  final charsRegExp = RegExp(r'^[0-9.]*$');
  if (!charsRegExp.hasMatch(trimmed)) {
    return 'Enter numeric characters only';
  }
  // Check dot count
  if ('.'.allMatches(trimmed).length > 1) {
    return 'Enter a valid decimal number';
  }
  // Check if double.tryParse works
  final val = double.tryParse(trimmed);
  if (val == null || val.isNaN || val.isInfinite || val < 0) {
    return 'Enter a valid positive number';
  }
  // Check magnitude: integer part 1-4 digits
  final parts = trimmed.split('.');
  final integerPart = parts[0];
  if (integerPart.isEmpty || integerPart.length > 4) {
    return 'Integer part must be 1-4 digits';
  }
  // Check decimal places: ≤ 2 places
  if (parts.length > 1) {
    final decimalPart = parts[1];
    if (decimalPart.length > 2) {
      return 'Max 2 decimal places';
    }
  }
  return null;
}

bool isDisplayableLabValue(String? textValue) {
  if (textValue == null) return false;
  final trimmed = textValue.trim();
  if (trimmed.isEmpty) return false;
  final val = double.tryParse(trimmed);
  if (val == null || val.isNaN || val.isInfinite || val < 0.0 || val > 99999.0) {
    return false;
  }
  return true;
}
