import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/features/auth/data/password_reset_service.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/domain/password_reset_result.dart';
import 'package:klinikaid_mobile/features/auth/domain/verification_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/forgot_password_screen.dart';

// Contract and account-state tests for the recovery, consent and sign-up
// transitions. Every backend call is a local fake: no live account is used.

class _MockGoTrueClient extends GoTrueClient {
  _MockGoTrueClient() : super(autoRefreshToken: false);

  @override
  Session? get currentSession => null;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

class _MockSupabaseClient extends SupabaseClient {
  final GoTrueClient _auth;

  _MockSupabaseClient(this._auth) : super('https://example.invalid', 'mock-anon-key');

  @override
  GoTrueClient get auth => _auth;
}

class _FakePasswordResetService implements PasswordResetService {
  _FakePasswordResetService({this.error});

  /// Thrown for every request when set; the request then never reached a server.
  final Object? error;
  final requested = <String>[];

  @override
  Future<void> requestReset(String email) async {
    requested.add(email);
    if (error != null) throw error!;
  }
}

class _FakeConsentProfilesRepository extends ProfilesRepository {
  bool failWrite = false;
  final consentWrites = <String>[];

  @override
  Future<Profile> recordPrivacyAcceptance(String id, DateTime acceptedAt) async {
    if (failWrite) {
      throw const DatabaseFailure('Could not record consent.');
    }
    consentWrites.add(id);
    return _profile(id, acceptedPrivacyAt: acceptedAt);
  }

  @override
  Future<Profile> updateProfile(Profile profile) {
    // Consent must not send the whole row back: it could overwrite role or
    // active status with a stale copy.
    throw StateError('Consent must not write the whole profile row.');
  }

  @override
  Future<Profile> getProfile(String id) async => _profile(id);
}

class _IdleVerificationService implements VerificationService {
  @override
  Future<VerificationResult> sendCode({required String email}) async =>
      VerificationResult(status: VerificationStatus.codeSent);

  @override
  Future<VerificationResult> verifyCode({required String email, required String code}) async =>
      VerificationResult(status: VerificationStatus.verified);

  @override
  Future<bool> deletePendingUser() async => true;
}

Profile _profile(String id, {DateTime? acceptedPrivacyAt}) {
  return Profile(
    id: id,
    fullName: 'Jane Patient',
    role: UserRole.patient,
    acceptedPrivacyAt: acceptedPrivacyAt,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

AuthProvider _buildProvider({
  PasswordResetService? passwordResetService,
  _FakeConsentProfilesRepository? profilesRepo,
}) {
  final client = _MockSupabaseClient(_MockGoTrueClient());
  return AuthProvider(
    client: client,
    patientsRepo: _NoPatientRepository(),
    profilesRepo: profilesRepo ?? _FakeConsentProfilesRepository(),
    verificationService: _IdleVerificationService(),
    passwordResetService: passwordResetService ?? _FakePasswordResetService(),
  );
}

class _NoPatientRepository extends PatientsRepository {
  @override
  Future<Patient?> getPatientByProfileId(String profileId) async => null;
}

class _ResetAuth extends ChangeNotifier implements AuthProvider {
  _ResetAuth(this.outcomes);

  /// One outcome per request, in order; the last one repeats.
  final List<PasswordResetResult> outcomes;
  final requested = <String>[];

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  void clearError() {}

  @override
  Future<PasswordResetResult> sendPasswordReset(String email) async {
    requested.add(email);
    final index = requested.length - 1 < outcomes.length ? requested.length - 1 : outcomes.length - 1;
    return outcomes[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://example.invalid',
        anonKey: 'synthetic-test-key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  group('password reset request', () {
    test('an accepted request reports success', () async {
      final provider = _buildProvider();

      expect(
        await provider.sendPasswordReset('jane@example.com'),
        PasswordResetResult.success,
      );
    });

    test('a 4xx answer is reported as success, the same as an accepted request', () async {
      final provider = _buildProvider(
        passwordResetService: _FakePasswordResetService(
          error: const FunctionException(status: 400, reasonPhrase: 'Bad Request'),
        ),
      );

      expect(
        await provider.sendPasswordReset('unknown@example.com'),
        PasswordResetResult.success,
      );
    });

    test('a 5xx answer is retryable and does not claim a link was sent', () async {
      final provider = _buildProvider(
        passwordResetService: _FakePasswordResetService(
          error: const FunctionException(status: 503, reasonPhrase: 'Service Unavailable'),
        ),
      );

      expect(
        await provider.sendPasswordReset('jane@example.com'),
        PasswordResetResult.retryableFailure,
      );
      expect(provider.errorMessage, isNull);
    });

    test('a 429 from the gateway is rate-limited, with no account detail', () async {
      final provider = _buildProvider(
        passwordResetService: _FakePasswordResetService(
          error: const FunctionException(status: 429, reasonPhrase: 'Too Many Requests'),
        ),
      );

      expect(
        await provider.sendPasswordReset('jane@example.com'),
        PasswordResetResult.rateLimited,
      );
      expect(provider.errorMessage, isNull);
    });

    test('no answer from the server (transport failure) is retryable', () async {
      final provider = _buildProvider(
        passwordResetService: _FakePasswordResetService(
          error: const SocketException('Connection refused'),
        ),
      );

      expect(
        await provider.sendPasswordReset('jane@example.com'),
        PasswordResetResult.retryableFailure,
      );
    });

    test('the request carries the address only: the server picks the reset destination', () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final service = SupabasePasswordResetService((name, body) async {
        calls.add((name, body));
      });
      final provider = _buildProvider(passwordResetService: service);

      await provider.sendPasswordReset('jane@example.com');

      expect(calls.length, 1);
      expect(calls.single.$1, 'request-password-reset');
      expect(calls.single.$2, {'email': 'jane@example.com'});
    });
  });

  group('privacy consent', () {
    test('with no signed-in account, consent is refused and nothing is written', () async {
      final profilesRepo = _FakeConsentProfilesRepository();
      final provider = _buildProvider(profilesRepo: profilesRepo);
      await Future<void>.delayed(Duration.zero);

      final accepted = await provider.acceptConsent();

      expect(accepted, false);
      expect(profilesRepo.consentWrites, isEmpty);
      expect(provider.hasConsented, false);
      expect(provider.errorMessage, contains('Sign in again'));
    });

    test('accepting records the timestamp for the signed-in patient only', () async {
      final profilesRepo = _FakeConsentProfilesRepository();
      final provider = _buildProvider(profilesRepo: profilesRepo);
      await Future<void>.delayed(Duration.zero);
      provider.setMockState(
        user: User(
          id: 'auth-user-1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime(2026, 1, 1).toIso8601String(),
          email: 'jane@example.com',
        ),
        profile: _profile('auth-user-1'),
      );

      final accepted = await provider.acceptConsent();

      expect(accepted, true);
      expect(profilesRepo.consentWrites, ['auth-user-1']);
      expect(provider.hasConsented, true);
      expect(provider.profile?.acceptedPrivacyAt, isNotNull);
      expect(provider.errorMessage, isNull);
    });

    test('a failed consent write leaves the patient on the agreement with the reason', () async {
      final profilesRepo = _FakeConsentProfilesRepository()..failWrite = true;
      final provider = _buildProvider(profilesRepo: profilesRepo);
      await Future<void>.delayed(Duration.zero);
      provider.setMockState(
        user: User(
          id: 'auth-user-1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime(2026, 1, 1).toIso8601String(),
          email: 'jane@example.com',
        ),
        profile: _profile('auth-user-1'),
      );

      final accepted = await provider.acceptConsent();

      expect(accepted, false);
      expect(provider.hasConsented, false);
      expect(provider.errorMessage, 'Could not record consent.');
    });
  });

  group('forgot password screen', () {
    Widget app(AuthProvider auth) => MaterialApp(
          home: ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: const ForgotPasswordScreen(),
          ),
        );

    Future<void> submit(WidgetTester tester, String email) async {
      await tester.enterText(find.byType(TextFormField), email);
      await tester.pumpAndSettle();
      final button = find.text('Send Reset Link');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('a failed request keeps the form open with the retry message', (tester) async {
      final auth = _ResetAuth([PasswordResetResult.retryableFailure]);
      await tester.pumpWidget(app(auth));

      await submit(tester, 'jane@example.com');

      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('Check Your Email'), findsNothing);
      expect(find.text(kPasswordResetRetryMessage), findsOneWidget);
    });

    testWidgets('a rate-limited request shows the wait message, not the retry message', (tester) async {
      final auth = _ResetAuth([PasswordResetResult.rateLimited]);
      await tester.pumpWidget(app(auth));

      await submit(tester, 'jane@example.com');

      expect(find.text('Send Reset Link'), findsOneWidget);
      expect(find.text('Check Your Email'), findsNothing);
      expect(find.text(kPasswordResetRateLimitMessage), findsOneWidget);
      expect(find.text(kPasswordResetRetryMessage), findsNothing);
    });

    testWidgets('a retry after a failed request can reach the sent state', (tester) async {
      final auth = _ResetAuth([
        PasswordResetResult.retryableFailure,
        PasswordResetResult.success,
      ]);
      await tester.pumpWidget(app(auth));

      await submit(tester, 'jane@example.com');
      await submit(tester, 'jane@example.com');

      expect(auth.requested, ['jane@example.com', 'jane@example.com']);
      expect(find.text('Check Your Email'), findsOneWidget);
      expect(find.text(kPasswordResetRetryMessage), findsNothing);
    });

    testWidgets('known and unknown addresses get the same sent state', (tester) async {
      for (final email in ['jane@example.com', 'nobody@example.com']) {
        final auth = _ResetAuth([PasswordResetResult.success]);
        await tester.pumpWidget(app(auth));

        await submit(tester, email);

        expect(find.text('Check Your Email'), findsOneWidget, reason: email);
        expect(find.textContaining('If an account exists for $email'), findsOneWidget, reason: email);
        expect(find.text(kPasswordResetRetryMessage), findsNothing, reason: email);
        // Replace the screen so the next address starts from the entry form.
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
