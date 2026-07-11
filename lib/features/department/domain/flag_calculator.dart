import 'lab_reference_ranges.dart';

/// Checks if a given laboratory numeric test [value] is outside the expected 
/// reference bounds for the patient's [gender]. If the gender is null, "other", 
/// or "male", it defaults to the male reference range.
bool isValueFlagged(double value, LabReferenceRange range, String? gender) {
  final isFemale = gender?.toLowerCase() == 'female';
  final min = isFemale ? range.femaleMin : range.maleMin;
  final max = isFemale ? range.femaleMax : range.maleMax;
  return value < min || value > max;
}
