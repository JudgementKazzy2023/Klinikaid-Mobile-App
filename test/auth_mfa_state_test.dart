import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_service.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/data/mfa_service.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/domain/login_outcome.dart';
import 'package:klinikaid_mobile/features/auth/domain/verification_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

User makeUser(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
      email: email,
    );

Factor makeFactor(String id) => Factor(
      id: id,
      friendlyName: null,
      factorType: FactorType.totp,
      status: FactorStatus.verified,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class MockGoTrueClient extends GoTrueClient {
  MockGoTrueClient() : super(autoRefreshToken: false);

  final Map<String, User> usersByEmail = {};
  User? activeUser;

  @override
  Session? get currentSession => null;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    final user = usersByEmail[email]!;
    activeUser = user;
    final session = Session(
      accessToken: 'access-token-jwt',
      tokenType: 'bearer',
      user: user,
    );
    return AuthResponse(session: session, user: user);
  }

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async =>
      AuthResponse();

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    activeUser = null;
  }
}

class MockSupabaseClient extends SupabaseClient {
  final MockGoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth)
      : super('https://example.supabase.co', 'mock-anon-key');

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  final Map<String, Profile> profilesById = {};
  Completer<Profile>? profileGate;

  @override
  Future<Profile> getProfile(String id) async {
    final gate = profileGate;
    if (gate != null) return gate.future;
    return profilesById[id]!;
  }
}

class MockPatientsRepository extends PatientsRepository {
  @override
  Future<Patient?> getPatientByProfileId(String profileId) async => null;
}

class MockSessionActivityService extends SessionActivityService {
  @override
  void startMonitoring({
    required Duration timeout,
    required VoidCallback onTimeout,
  }) {}

  @override
  void stopMonitoring() {}

  @override
  void recordActivity() {}

  @override
  Future<void> restoreLastActivity() async {}
}

class MockPermissionService implements PermissionService {
  @override
  Future<Set<String>> loadPermissionsForRole(String roleId) async =>
      const <String>{};
}

class MockMfaService extends MfaService {
  MockMfaService(this.authClient, SupabaseClient client) : super(client);

  final MockGoTrueClient authClient;
  bool stepUpRequired = false;
  final Map<String, List<Factor>> verifiedFactorsByUserId = {};
  MfaVerifyResult verifyResult = MfaVerifyResult.success;
  Completer<MfaVerifyResult>? verifyGate;
  String? lastVerifiedFactorId;

  @override
  bool requiresStepUp() => stepUpRequired;

  @override
  Future<List<Factor>> listVerifiedFactors() async =>
      verifiedFactorsByUserId[authClient.activeUser?.id] ?? const <Factor>[];

  @override
  Future<MfaVerifyResult> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    lastVerifiedFactorId = factorId;
    final gate = verifyGate;
    if (gate != null) return gate.future;
    return verifyResult;
  }
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
        url: 'https://example.supabase.co',
        anonKey: 'mock-anon-key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  late MockGoTrueClient mockAuth;
  late MockSupabaseClient mockClient;
  late MockProfilesRepository profilesRepo;
  late MockMfaService mfaService;
  late AuthProvider provider;

  final userA = makeUser('user-a', 'a@clinic.test');
  final userB = makeUser('user-b', 'b@clinic.test');

  Profile adminProfile() => Profile(
        id: 'user-a',
        fullName: 'Admin A',
        role: UserRole.admin,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

  Profile receptionistProfile() => Profile(
        id: 'user-b',
        fullName: 'Staff B',
        role: UserRole.receptionist,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

  Profile patientProfile({DateTime? acceptedPrivacyAt}) => Profile(
        id: 'user-a',
        fullName: 'Patient A',
        role: UserRole.patient,
        acceptedPrivacyAt: acceptedPrivacyAt,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockClient = MockSupabaseClient(mockAuth);
    profilesRepo = MockProfilesRepository();
    mfaService = MockMfaService(mockAuth, mockClient);
    provider = AuthProvider(
      client: mockClient,
      profilesRepo: profilesRepo,
      patientsRepo: MockPatientsRepository(),
      verificationService: MockVerificationService(),
      permissionService: MockPermissionService(),
      activityService: MockSessionActivityService(),
      mfaService: mfaService,
    );
  });

  tearDown(() => provider.dispose());

  /// Signs in admin A with a pending MFA challenge on [factorId].
  Future<LoginOutcome> signInAdminAPending(String factorId) async {
    mockAuth.usersByEmail['a@clinic.test'] = userA;
    profilesRepo.profilesById['user-a'] = adminProfile();
    mfaService.stepUpRequired = true;
    mfaService.verifiedFactorsByUserId['user-a'] = [makeFactor(factorId)];
    return provider.signIn('a@clinic.test', 'password');
  }

  group('AUTH-03: MFA/verification state is scoped to the active identity', () {
    test('signOut clears a pending MFA factor (original failure)', () async {
      final outcome = await signInAdminAPending('factor-a1');
      expect(outcome, LoginOutcome.mfaRequired);
      expect(provider.pendingMfaFactorId, 'factor-a1');
      expect(provider.isAal1Pending, isTrue);

      await provider.signOut();

      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.needsMfaEnrollment, isFalse);
      expect(provider.isAal1Pending, isFalse);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.verificationState.status, VerificationStatus.idle);
    });

    test('signOut clears a pending MFA enrollment', () async {
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = adminProfile();
      mfaService.stepUpRequired = true;
      mfaService.verifiedFactorsByUserId['user-a'] = const <Factor>[];

      await provider.signIn('a@clinic.test', 'password');
      expect(provider.needsMfaEnrollment, isTrue);
      expect(provider.isAal1Pending, isTrue);

      await provider.signOut();

      expect(provider.needsMfaEnrollment, isFalse);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.isAal1Pending, isFalse);
    });

    test('account B cannot inherit A\'s pending factor after sign-out',
        () async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);
      await provider.signOut();

      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = receptionistProfile();
      mfaService.stepUpRequired = false;

      final outcome = await provider.signIn('b@clinic.test', 'password');

      expect(outcome, LoginOutcome.success);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.needsMfaEnrollment, isFalse);
      expect(provider.isAal1Pending, isFalse);
      expect(provider.verificationState.status, VerificationStatus.idle);
    });

    test('admin B with a step-up gets B\'s own factor, never A\'s', () async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);

      // Direct switch without an intervening explicit signOut (session expiry).
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = Profile(
        id: 'user-b',
        fullName: 'Admin B',
        role: UserRole.admin,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );
      mfaService.verifiedFactorsByUserId['user-b'] = [makeFactor('factor-b2')];

      final outcome = await provider.signIn('b@clinic.test', 'password');

      expect(outcome, LoginOutcome.mfaRequired);
      expect(provider.pendingMfaFactorId, 'factor-b2');
    });

    test('failed MFA retry on the same account preserves its factor',
        () async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);
      mfaService.verifyResult = MfaVerifyResult.invalidCode;

      final result = await provider.verifyMfa('000000');

      expect(result, MfaVerifyResult.invalidCode);
      expect(provider.pendingMfaFactorId, 'factor-a1');
      expect(provider.isAal1Pending, isTrue);
    });

    test('signOut after a successful MFA verify also clears the state',
        () async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);
      mfaService.verifyResult = MfaVerifyResult.success;

      final result = await provider.verifyMfa('123456');
      expect(result, MfaVerifyResult.success);
      expect(mfaService.lastVerifiedFactorId, 'factor-a1');

      // Note: the mock client can never reach AAL2, so _updateLocalStates may
      // legitimately re-pend the still-listed verified factor mid-session;
      // the acceptance observable is that logout clears it either way.
      await provider.signOut();

      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.needsMfaEnrollment, isFalse);
      expect(provider.isAal1Pending, isFalse);
    });

    test('stale profile load for a captured user is dropped after sign-out',
        () async {
      final gate = Completer<Profile>();
      profilesRepo.profileGate = gate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = adminProfile();
      mfaService.stepUpRequired = true;
      mfaService.verifiedFactorsByUserId['user-a'] = [makeFactor('factor-a1')];

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await provider.signOut();
      gate.complete(adminProfile());
      await loginFuture;

      expect(provider.profile, isNull);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.needsMfaEnrollment, isFalse);
    });

    test('stale MFA verify completion cannot mutate post-switch state',
        () async {
      provider.setMockState(user: userA, pendingMfaFactorId: 'factor-a1');
      final verifyGate = Completer<MfaVerifyResult>();
      mfaService.verifyGate = verifyGate;

      final verifyFuture = provider.verifyMfa('123456');
      await provider.signOut();
      verifyGate.complete(MfaVerifyResult.success);
      final result = await verifyFuture;

      expect(result, MfaVerifyResult.error);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.isAal1Pending, isFalse);
    });

    test('consent recorded for A does not carry over to B', () async {
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] =
          patientProfile(acceptedPrivacyAt: DateTime(2026));

      await provider.signIn('a@clinic.test', 'password');
      expect(provider.hasConsented, isTrue);

      await provider.signOut();

      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = Profile(
        id: 'user-b',
        fullName: 'Patient B',
        role: UserRole.patient,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

      await provider.signIn('b@clinic.test', 'password');
      expect(provider.hasConsented, isFalse);
    });
  });

  group('router never routes an inherited identity to MFA', () {
    testWidgets(
        'pending A stays on /mfa-verify, then after sign-out the route ejects to /login',
        (tester) async {
      await signInAdminAPending('factor-a1');
      final router = AppRouter(provider);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: provider),
        ],
        child: MaterialApp.router(routerConfig: router.router),
      ));
      await tester.pumpAndSettle();

      router.router.go('/mfa-verify');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, '/mfa-verify');

      await provider.signOut();
      await tester.pumpAndSettle();

      router.router.go('/mfa-verify');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, '/login');
    });

    testWidgets('signed-in B without pending MFA is sent home, not to MFA',
        (tester) async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);
      await provider.signOut();

      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = receptionistProfile();
      mfaService.stepUpRequired = false;
      expect(await provider.signIn('b@clinic.test', 'password'),
          LoginOutcome.success);

      final router = AppRouter(provider);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: provider),
        ],
        child: MaterialApp.router(routerConfig: router.router),
      ));
      await tester.pumpAndSettle();

      router.router.go('/mfa-verify');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, '/reception/queue');
    });
  });
}
