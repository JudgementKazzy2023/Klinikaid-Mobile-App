import 'package:flutter/foundation.dart';

/// Patient submissions are live: the shared backend (migrations 41/42 and
/// patient-document-submission) is deployed and both flows passed the device
/// check (#36). Kept as a kill switch: set `_active = true` to stop every
/// patient write again, keeping drafts. Lifecycle replay must never return.
class PatientSubmissionContainment {
  static bool _active = false;

  static bool get isActive => _active;

  /// Tests of the underlying submit flows switch containment off, and must
  /// restore it in tearDown. Production code never calls this.
  @visibleForTesting
  static set activeForTesting(bool value) => _active = value;

  static const message =
      'Submission temporarily unavailable. This draft has not been submitted.';

  static void requireAvailable() {
    if (isActive) throw StateError(message);
  }
}
