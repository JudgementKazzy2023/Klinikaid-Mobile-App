/// Result codes for the self-service staff password change flow.
///
/// The flow: reauthenticate with current password via [signInWithPassword],
/// then call [updateUser] with the new password. This enum captures every
/// outcome so the UI can display the correct message without catching raw
/// exceptions.
enum PasswordChangeResult {
  /// Reauthentication succeeded and the password was updated.
  success,

  /// The current password supplied failed reauthentication.
  wrongCurrentPassword,

  /// No authenticated session was found (should not happen in normal flow).
  notAuthenticated,

  /// An unexpected error occurred during reauth or update.
  error,
}
