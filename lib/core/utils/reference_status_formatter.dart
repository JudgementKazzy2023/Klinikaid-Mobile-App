import '../models/department_record.dart';

/// Returns the UI display label for a [ReferenceRangeStatus].
///
/// Valid values going forward:
///   normal    → "Normal"
///   flagged   → "Flagged"
///   inconclusive → "Inconclusive"
String referenceStatusDisplayLabel(ReferenceRangeStatus status) {
  switch (status) {
    case ReferenceRangeStatus.normal:
      return 'Normal';
    case ReferenceRangeStatus.flagged:
      return 'Flagged';
    case ReferenceRangeStatus.inconclusive:
      return 'Inconclusive';
  }
}

/// Convenience: returns true when the status indicates any abnormal result.
bool isStatusFlagged(ReferenceRangeStatus status) =>
    status == ReferenceRangeStatus.flagged;
