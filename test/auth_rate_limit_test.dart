import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/domain/login_outcome.dart';
import 'package:klinikaid_mobile/features/auth/domain/password_change_result.dart';
import 'package:klinikaid_mobile/features/auth/domain/sign_in_rate_limit.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

// Sign-in and current-password lockout tests. Every backend call is a local
// fake: the password check throws the configured error and no account is used.

const _genericLockoutMessage = 'Too many sign-in attempts. Try again later.';

const _builtInLimit = AuthException(
  'Request rate limit reached',
  statusCode: '429',
  code: 'over_request_rate_limit',
);

const _wrongPassword = AuthException(
  'Invalid login credentials',
  statusCode: '400',
  code: 'invalid_credentials',
);

User _staff() => User(
      id: 'staff-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '',
      email: 'staff@test.com',
    );

class _PasswordCheckAuth extends GoTrueClient {
  _PasswordCheckAuth({this.signInError, this.signedInUser}) : super(autoRefreshToken: false);

  /// Thrown by every password check. The check never passes in these tests.
  final Object? signInError;
  final User? signedInUser;
  int updateUserCalls = 0;

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => signedInUser;

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async => AuthResponse();

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    throw signInError ?? StateError('No password check was configured.');
  }

  @override
  Future<UserResponse> updateUser(UserAttributes attributes, {String? emailRedirectTo}) async {
    updateUserCalls++;
    throw StateError('updateUser must not run after a refused check');
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

class _MockSupabaseClient extends SupabaseClient {
  final GoTrueClient _auth;

  _MockSupabaseClient(this._auth) : super('https://example.invalid', 'mock-anon-key');

  @override
  GoTrueClient get auth => _auth;
}

AuthProvider _buildProvider(_PasswordCheckAuth auth) {
  final client = _MockSupabaseClient(auth);
  SupabaseService.mockClient = client;
  addTearDown(() => SupabaseService.mockClient = null);
  final provider = AuthProvider(client: client);
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  group('signInRateLimitMessage', () {
    test('no wait given uses the generic wording', () {
      expect(signInRateLimitMessage(null), _genericLockoutMessage);
    });

    test('600 seconds reads as 10 minutes', () {
      expect(signInRateLimitMessage(600), 'Too many sign-in attempts. Try again in 10 minutes.');
    });

    test('60 seconds reads as 1 minute', () {
      expect(signInRateLimitMessage(60), 'Too many sign-in attempts. Try again in 1 minute.');
    });

    test('a partial minute rounds up', () {
      expect(signInRateLimitMessage(61), 'Too many sign-in attempts. Try again in 2 minutes.');
      expect(signInRateLimitMessage(1), 'Too many sign-in attempts. Try again in 1 minute.');
    });

    test('a zero or negative wait still reads as at least 1 minute', () {
      expect(signInRateLimitMessage(0), 'Too many sign-in attempts. Try again in 1 minute.');
      expect(signInRateLimitMessage(-5), 'Too many sign-in attempts. Try again in 1 minute.');
    });
  });

  group('signIn', () {
    test('a 429 from Supabase Auth is rate-limited, not wrong credentials', () async {
      final provider = _buildProvider(_PasswordCheckAuth(signInError: _builtInLimit));

      final outcome = await provider.signIn('jane@test.com', 'Password123!');

      expect(outcome, LoginOutcome.rateLimited);
      expect(provider.errorMessage, _genericLockoutMessage);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('a login_locked response with retry_after_seconds 600 says 10 minutes', () async {
      final provider = _buildProvider(_PasswordCheckAuth(
        signInError: const FunctionException(
          status: 429,
          reasonPhrase: 'Too Many Requests',
          details: {'code': 'login_locked', 'retry_after_seconds': 600},
        ),
      ));

      final outcome = await provider.signIn('jane@test.com', 'Password123!');

      expect(outcome, LoginOutcome.rateLimited);
      expect(provider.errorMessage, 'Too many sign-in attempts. Try again in 10 minutes.');
    });

    test('a login_locked response with retry_after_seconds 60 says 1 minute', () async {
      final provider = _buildProvider(_PasswordCheckAuth(
        signInError: const FunctionException(
          status: 429,
          reasonPhrase: 'Too Many Requests',
          details: {'code': 'login_locked', 'retry_after_seconds': 60},
        ),
      ));

      await provider.signIn('jane@test.com', 'Password123!');

      expect(provider.errorMessage, 'Too many sign-in attempts. Try again in 1 minute.');
    });

    test('a plain 400 invalid-credentials error stays invalidCredentials', () async {
      final provider = _buildProvider(_PasswordCheckAuth(signInError: _wrongPassword));

      final outcome = await provider.signIn('jane@test.com', 'wrong-pass');

      expect(outcome, LoginOutcome.invalidCredentials);
      expect(provider.errorMessage, 'Invalid login credentials');
    });
  });

  group('changePassword', () {
    test('a 429 on the current-password check is rate-limited and never updates', () async {
      final auth = _PasswordCheckAuth(signedInUser: _staff(), signInError: _builtInLimit);
      final provider = _buildProvider(auth);

      final result = await provider.changePassword(
        currentPassword: 'old-pass',
        newPassword: 'new-pass',
      );

      expect(result, PasswordChangeResult.rateLimited);
      expect(provider.errorMessage, _genericLockoutMessage);
      expect(auth.updateUserCalls, 0);
    });

    test('a wrong current password stays wrongCurrentPassword and never updates', () async {
      final auth = _PasswordCheckAuth(signedInUser: _staff(), signInError: _wrongPassword);
      final provider = _buildProvider(auth);

      final result = await provider.changePassword(
        currentPassword: 'old-pass',
        newPassword: 'new-pass',
      );

      expect(result, PasswordChangeResult.wrongCurrentPassword);
      expect(provider.errorMessage, 'Invalid login credentials');
      expect(auth.updateUserCalls, 0);
    });
  });
}
