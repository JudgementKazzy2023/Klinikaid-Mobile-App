enum LoginOutcome {
  success,
  mfaRequired,
  invalidCredentials,

  /// Sign-in is locked after too many attempts (HTTP 429). The password was
  /// not checked, so this says nothing about the credentials themselves.
  rateLimited,
}
