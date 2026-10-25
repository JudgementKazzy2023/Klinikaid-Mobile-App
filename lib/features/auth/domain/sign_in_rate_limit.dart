/// What the user is told when sign-in is locked after too many attempts.
///
/// [retryAfterSeconds] is the wait the server gave. Supabase Auth's built-in
/// limiter gives none, so pass null and the wording omits the time. Matches
/// the web portal's sign-in lockout message.
String signInRateLimitMessage(int? retryAfterSeconds) {
  if (retryAfterSeconds == null) {
    return 'Too many sign-in attempts. Try again later.';
  }
  final minutes = retryAfterSeconds > 0 ? (retryAfterSeconds + 59) ~/ 60 : 1;
  final unit = minutes == 1 ? 'minute' : 'minutes';
  return 'Too many sign-in attempts. Try again in $minutes $unit.';
}
