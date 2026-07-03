import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/verification_state.dart';
import '../../../../core/supabase/supabase_client.dart';

class VerificationResult {
  final VerificationStatus status;
  final int? attemptsRemaining;
  final DateTime? expiresAt;
  final String? errorMessage;

  VerificationResult({
    required this.status,
    this.attemptsRemaining,
    this.expiresAt,
    this.errorMessage,
  });
}

abstract class VerificationService {
  Future<VerificationResult> sendCode({required String email});
  Future<VerificationResult> verifyCode({required String email, required String code});
  Future<bool> deletePendingUser();
}

class SupabaseVerificationService implements VerificationService {
  final _client = SupabaseService.client;

  @override
  Future<VerificationResult> sendCode({required String email}) async {
    try {
      final response = await _client.functions.invoke(
        'send-verification-code',
        method: HttpMethod.post,
        body: {'email': email},
      );

      final data = response.data;
      final Map<String, dynamic> json = data is Map<String, dynamic> ? data : {};

      if (response.status == 200) {
        final expiresAtStr = json['expires_at'] as String?;
        final expiresAt = expiresAtStr != null ? DateTime.parse(expiresAtStr) : null;
        return VerificationResult(status: VerificationStatus.codeSent, expiresAt: expiresAt);
      } else {
        final error = json['error'] as String?;
        final message = json['message'] as String? ?? 'Failed to send code';
        if (error == 'rate_limit_exceeded') {
          return VerificationResult(
            status: VerificationStatus.rateLimited,
            errorMessage: message,
          );
        }
        return VerificationResult(
          status: VerificationStatus.networkError,
          errorMessage: message,
        );
      }
    } on SocketException {
      return VerificationResult(
        status: VerificationStatus.networkError,
        errorMessage: 'You are currently offline. Please check your network connection.',
      );
    } catch (e) {
      return VerificationResult(
        status: VerificationStatus.networkError,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<VerificationResult> verifyCode({required String email, required String code}) async {
    try {
      final response = await _client.functions.invoke(
        'verify-registration-code',
        method: HttpMethod.post,
        body: {'email': email, 'code': code},
      );

      final data = response.data;
      final Map<String, dynamic> json = data is Map<String, dynamic> ? data : {};

      if (response.status == 200) {
        return VerificationResult(status: VerificationStatus.verified);
      } else {
        final error = json['error'] as String?;
        final message = json['message'] as String? ?? 'Verification failed';
        final attemptsRemaining = json['attempts_remaining'] as int?;
        if (error == 'wrong_code') {
          final attemptsMsg = attemptsRemaining != null
              ? (attemptsRemaining == 1
                  ? '1 attempt remaining.'
                  : '$attemptsRemaining attempts remaining.')
              : '';
          return VerificationResult(
            status: VerificationStatus.wrongCode,
            attemptsRemaining: attemptsRemaining,
            errorMessage: 'Incorrect code. $attemptsMsg'.trim(),
          );
        } else if (error == 'too_many_attempts') {
          return VerificationResult(
            status: VerificationStatus.tooManyAttempts,
            errorMessage: message,
          );
        } else if (error == 'code_expired') {
          return VerificationResult(
            status: VerificationStatus.codeExpired,
            errorMessage: message,
          );
        }
        return VerificationResult(
          status: VerificationStatus.networkError,
          errorMessage: message,
        );
      }
    } on SocketException {
      return VerificationResult(
        status: VerificationStatus.networkError,
        errorMessage: 'You are currently offline. Please check your network connection.',
      );
    } catch (e) {
      return VerificationResult(
        status: VerificationStatus.networkError,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  Future<bool> deletePendingUser() async {
    try {
      final response = await _client.functions.invoke(
        'send-verification-code',
        method: HttpMethod.delete,
      );
      return response.status == 200;
    } catch (e) {
      return false;
    }
  }
}

class MockVerificationService implements VerificationService {
  bool isDeleteCalled = false;
  bool shouldFail = false;
  bool shouldFailDelete = false;

  @override
  Future<VerificationResult> sendCode({required String email}) async {
    if (shouldFail) {
      return VerificationResult(
        status: VerificationStatus.rateLimited,
        errorMessage: 'Rate limit exceeded mock error.',
      );
    }
    return VerificationResult(
      status: VerificationStatus.codeSent,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<VerificationResult> verifyCode({required String email, required String code}) async {
    if (shouldFail) {
      return VerificationResult(
        status: VerificationStatus.wrongCode,
        attemptsRemaining: 3,
        errorMessage: 'Incorrect code. 3 attempts remaining.',
      );
    }
    if (code == '123456') {
      return VerificationResult(status: VerificationStatus.verified);
    }
    return VerificationResult(
      status: VerificationStatus.wrongCode,
      attemptsRemaining: 4,
      errorMessage: 'Incorrect code. 4 attempts remaining.',
    );
  }

  @override
  Future<bool> deletePendingUser() async {
    isDeleteCalled = true;
    if (shouldFailDelete) {
      return false;
    }
    return true;
  }
}
