import 'package:flutter/foundation.dart';

/// Lift only after the server contract and owner-aware draft reconciliation
/// are verified. Lifecycle replay must not be restored automatically.
class PatientSubmissionContainment {
  static bool _active = true;

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
