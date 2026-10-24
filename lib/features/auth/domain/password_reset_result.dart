/// What the user is told after asking for a password reset link.
///
/// [success] is returned for a known and an unknown address alike: the server
/// answers both the same way, so the client never learns which one it was.
/// [retryableFailure] is only for a failure that says nothing about the address
/// (no answer at all, or a server error), so it is the same for every address.
enum PasswordResetResult {
  success,
  retryableFailure,
}

/// Shown when the reset request could not be sent. Deliberately free of any
/// account detail.
const kPasswordResetRetryMessage =
    'We could not send the reset link. Check your connection and try again.';
