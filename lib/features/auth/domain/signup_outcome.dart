/// How a self-registration ended. Each value that is not [registered] leaves
/// the user with a message that says what to do next, and nothing is signed in.
enum SignUpOutcome {
  /// The account, its single patient record and the verification code all
  /// exist. The user continues with the email code.
  registered,

  /// Auth created the account but returned no session, which means email
  /// confirmation is required. The patient record is written by an
  /// authenticated call, so it cannot be made from here. No record was
  /// written, and the user is told to contact reception.
  noSession,

  /// The patient record exists, but a later step (recording consent or sending
  /// the code) did not finish. The account is kept, and the user is told to
  /// sign in to finish. Retrying sign-up with the same email is refused by
  /// Auth, so it cannot create a second record.
  setupIncomplete,

  /// No patient record was confirmed. Auth refused the sign-up, or the
  /// patient record was refused or its outcome could not be confirmed. The
  /// message carries the reason from the server or the connection.
  failed,
}

/// Shown for [SignUpOutcome.noSession].
const kSignUpNoSessionMessage =
    'Registration is not complete. Please contact reception to finish setting up your patient record.';

/// Shown for [SignUpOutcome.setupIncomplete].
const kSignUpSetupIncompleteMessage =
    'Your account was created, but setup did not finish. Sign in with the same email and password to finish setting up.';
