enum VerificationStatus {
  idle,
  codeSent,
  verifying,
  verified,
  wrongCode,
  tooManyAttempts,
  codeExpired,
  rateLimited,
  networkError,
}

class VerificationState {
  final VerificationStatus status;
  final int? attemptsRemaining;
  final DateTime? cooldownUntil;
  final String? errorMessage;

  VerificationState({
    this.status = VerificationStatus.idle,
    this.attemptsRemaining,
    this.cooldownUntil,
    this.errorMessage,
  });

  VerificationState copyWith({
    VerificationStatus? status,
    int? attemptsRemaining,
    DateTime? cooldownUntil,
    String? errorMessage,
  }) {
    return VerificationState(
      status: status ?? this.status,
      attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
