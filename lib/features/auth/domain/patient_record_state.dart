/// Outcome of the lookup for the patient record linked to the active account.
///
/// A failed read and a missing row are different states and must not be
/// collapsed into one. A failed read means the record may exist but could not
/// be retrieved, so the surface can offer a retry. A missing row means the
/// account has no patient record at all, so retrying the same read cannot
/// help and the surface has to offer a recovery instead.
enum PatientRecordState {
  /// No lookup has completed yet.
  unknown,

  /// The lookup is in flight.
  loading,

  /// A patient row exists for this account.
  loaded,

  /// The lookup succeeded but no patient row exists for this account.
  missing,

  /// The lookup failed (network, permission or parse error).
  failed,
}
