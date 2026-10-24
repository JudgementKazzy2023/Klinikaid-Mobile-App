/// What the user is told after asking for a password reset link.
///
/// The deployed `request-password-reset` function always answers HTTP 200
/// `{success:true}`: bad input, a lookup error, an unknown address, a staff
/// address and a thrown error all look the same. So a non-2xx status the client
/// sees comes from the gateway or the transport, never from the account.
///
/// [success] means the server answered and the request was accepted. It is
/// returned for a known and an unknown address alike.
/// [retryableFailure] means no answer arrived, or the server failed (5xx).
/// [rateLimited] means the gateway refused the request for too many attempts (429).
/// Both failures say nothing about the address, so they are the same for every address.
enum PasswordResetResult {
  success,
  retryableFailure,
  rateLimited,
}

/// Shown when the reset request could not be sent. Deliberately free of any
/// account detail.
const kPasswordResetRetryMessage =
    'We could not send the reset link. Check your connection and try again.';

/// Shown when the gateway refuses the request as too frequent. Free of any
/// account detail.
const kPasswordResetRateLimitMessage =
    'Too many reset requests. Wait a minute and try again.';
