import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
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
  final credentialGates = <String, Completer<void>>{};
  final credentialStarted = <String, Completer<void>>{};
  int signOutCalls = 0;
  Completer<void>? signOutGate;

  @override
  Session? get currentSession => null;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    credentialStarted[email]?.complete();
    final gate = credentialGates[email];
    if (gate != null) await gate.future;
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
    signOutCalls++;
    activeUser = null;
    final gate = signOutGate;
    if (gate != null) {
      signOutGate = null;
      return gate.future;
    }
  }
}

class MockSupabaseClient extends SupabaseClient {
  final MockGoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth)
      : super('https://example.invalid', 'mock-anon-key');

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  final Map<String, Profile> profilesById = {};
  Completer<Profile>? profileGate;
  final gatesById = <String, Completer<Profile>>{};
  final startedById = <String, Completer<void>>{};

  @override
  Future<Profile> getProfile(String id) async {
    startedById[id]?.complete();
    final gate = gatesById[id] ?? profileGate;
    if (gate != null) return gate.future;
    return profilesById[id]!;
  }
}

class MockPatientsRepository extends PatientsRepository {
  final Map<String, Patient> patientsByProfileId = {};
  Completer<Patient?>? patientGate;

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    final gate = patientGate;
    if (gate != null) return gate.future;
    return patientsByProfileId[profileId];
  }
}

class MockSessionActivityService extends SessionActivityService {
  Duration idleOverride = Duration.zero;
  Completer<void>? restoreGate;

  @override
  Duration get idleTime => idleOverride;

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
  Future<void> restoreLastActivity() async {
    final gate = restoreGate;
    if (gate != null) {
      restoreGate = null;
      return gate.future;
    }
  }
}

class MockPermissionService implements PermissionService {
  MockPermissionService({this.permissions = const <String>{}});

  Set<String> permissions;
  bool shouldFail = false;
  Completer<Set<String>>? gate;

  @override
  Future<Set<String>> loadPermissions() async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }
    if (shouldFail) {
      throw const PermissionLoadException('Mock permission load failed');
    }
    return permissions;
  }
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
        url: 'https://example.invalid',
        anonKey: 'synthetic-test-key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  late MockGoTrueClient mockAuth;
  late MockSupabaseClient mockClient;
  late MockProfilesRepository profilesRepo;
  late MockPatientsRepository patientsRepo;
  late MockMfaService mfaService;
  late MockPermissionService permissionService;
  late MockSessionActivityService activityService;
  late AuthProvider provider;

  /// Lets pending microtask-driven async chains advance to their next await.
  Future<void> pumpAsync([int turns = 8]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

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

  Profile staffProfile({String id = 'user-a', String? roleId}) => Profile(
        id: id,
        fullName: 'Staff $id',
        role: UserRole.receptionist,
        roleId: roleId,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );

  Patient patientRecord(String profileId) => Patient(
        id: profileId,
        profileId: profileId,
        firstName: 'Pat',
        lastName: 'IENT',
        dateOfBirth: DateTime(1990),
        gender: Gender.other,
        contactNumber: '000',
        address: 'Addr',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockClient = MockSupabaseClient(mockAuth);
    profilesRepo = MockProfilesRepository();
    patientsRepo = MockPatientsRepository();
    mfaService = MockMfaService(mockAuth, mockClient);
    permissionService = MockPermissionService();
    activityService = MockSessionActivityService();
    provider = AuthProvider(
      client: mockClient,
      profilesRepo: profilesRepo,
      patientsRepo: patientsRepo,
      verificationService: MockVerificationService(),
      permissionService: permissionService,
      activityService: activityService,
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

  for (final role in UserRole.values.where(
    (role) => role != UserRole.patient,
  )) {
    test('${role.name} without a factor must enroll at AAL1', () async {
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = Profile(
        id: 'user-a',
        fullName: 'Staff',
        role: role,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await provider.signIn('a@clinic.test', 'password');
      expect(provider.needsMfaEnrollment, isTrue);
      expect(provider.isAal1Pending, isTrue);
      expect(provider.pendingMfaFactorId, isNull);
    });
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
      expect(provider.needsMfaEnrollment, isTrue);
      expect(provider.isAal1Pending, isTrue);
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

  group('AUTH-03 round 3: late async completions cannot mutate a newer identity', () {
    test('late permission load success after sign-out cannot repopulate permissions',
        () async {
      final permGate = Completer<Set<String>>();
      permissionService.gate = permGate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] =
          staffProfile(roleId: 'role-reception');

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await pumpAsync(); // run reaches the permission await
      await provider.signOut();
      permGate.complete(const {'patients:read'});
      await loginFuture;

      expect(provider.user, isNull);
      expect(provider.permissions, isEmpty);
      expect(provider.permissionLoadState, PermissionLoadState.idle);
    });

    test('late permission load failure after sign-out cannot leave a failure state',
        () async {
      final permGate = Completer<Set<String>>();
      permissionService.gate = permGate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] =
          staffProfile(roleId: 'role-reception');

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await pumpAsync();
      await provider.signOut();
      permGate.completeError(Exception('late permission failure'));
      await loginFuture;

      expect(provider.user, isNull);
      expect(provider.permissions, isEmpty);
      expect(provider.permissionLoadState, PermissionLoadState.idle);
    });

    test('late activity restore cannot log out a newer signed-in identity',
        () async {
      final restoreGate = Completer<void>();
      activityService.restoreGate = restoreGate;
      activityService.idleOverride = const Duration(minutes: 30);
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = staffProfile();
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = staffProfile(id: 'user-b');

      final aLogin = provider.signIn('a@clinic.test', 'password');
      await pumpAsync(); // A's run reaches the activity restore await
      final bLogin = provider.signIn('b@clinic.test', 'password');
      await pumpAsync(); // B becomes the active identity mid-restore
      restoreGate.complete();
      await aLogin;
      await bLogin;

      expect(mockAuth.signOutCalls, 0);
      expect(provider.wasLoggedOutForInactivity, isFalse);
      expect(provider.user?.id, 'user-b');
      expect(provider.profile?.id, 'user-b');
    });

    test('sign-in interrupted during the profile wait cannot return a pending factor',
        () async {
      final gate = Completer<Profile>();
      profilesRepo.profileGate = gate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = adminProfile();
      mfaService.stepUpRequired = true;
      mfaService.verifiedFactorsByUserId['user-a'] = [makeFactor('factor-a1')];

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await pumpAsync();
      await provider.signOut();
      final pending = profilesRepo.profileGate!;
      profilesRepo.profileGate = null;
      pending.complete(adminProfile());
      final outcome = await loginFuture;

      expect(outcome, LoginOutcome.invalidCredentials);
      expect(provider.user, isNull);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('sign-in interrupted during the profile wait cannot return success',
        () async {
      final gate = Completer<Profile>();
      profilesRepo.profileGate = gate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = receptionistProfile();
      mfaService.stepUpRequired = false;

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await pumpAsync();
      await provider.signOut();
      final pending = profilesRepo.profileGate!;
      profilesRepo.profileGate = null;
      pending.complete(receptionistProfile());
      final outcome = await loginFuture;

      expect(outcome, LoginOutcome.invalidCredentials);
      expect(provider.user, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('delayed sign-out completion cannot clear a newer signed-in identity',
        () async {
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = staffProfile();
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = staffProfile(id: 'user-b');
      expect(
          await provider.signIn('a@clinic.test', 'password'),
          LoginOutcome.success);

      final signOutGate = Completer<void>();
      mockAuth.signOutGate = signOutGate;
      final signOutFuture = provider.signOut();
      await pumpAsync();

      expect(
          await provider.signIn('b@clinic.test', 'password'),
          LoginOutcome.success);
      expect(provider.user?.id, 'user-b');

      signOutGate.complete();
      await signOutFuture;

      expect(provider.user?.id, 'user-b');
      expect(provider.session, isNotNull);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.profile?.id, 'user-b');
    });

    test('delayed MFA verify completion cannot clear a newer flow\'s loading state',
        () async {
      provider.setMockState(user: userA, pendingMfaFactorId: 'factor-a1');
      final verifyGate = Completer<MfaVerifyResult>();
      mfaService.verifyGate = verifyGate;
      final verifyFuture = provider.verifyMfa('123456');
      await provider.signOut();

      final profileGate = Completer<Profile>();
      profilesRepo.profileGate = profileGate;
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = staffProfile(id: 'user-b');
      final bLogin = provider.signIn('b@clinic.test', 'password');
      await pumpAsync();
      expect(provider.isLoading, isTrue); // B's sign-in is mid-flight

      verifyGate.complete(MfaVerifyResult.success);
      final result = await verifyFuture;
      await pumpAsync(2);

      expect(result, MfaVerifyResult.error);
      expect(provider.isLoading, isTrue); // B's loading survives A's completion

      final pending = profilesRepo.profileGate!;
      profilesRepo.profileGate = null;
      pending.complete(staffProfile(id: 'user-b'));
      expect(await bLogin, LoginOutcome.success);
      expect(provider.isLoading, isFalse);
    });

    test('sign-out requested during the login network wait wins over the late response',
        () async {
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = adminProfile();
      mfaService.stepUpRequired = true;
      mfaService.verifiedFactorsByUserId['user-a'] = [makeFactor('factor-a1')];

      final loginFuture = provider.signIn('a@clinic.test', 'password');
      await provider.signOut(); // newer intent, before the response installs A
      final outcome = await loginFuture;

      expect(outcome, LoginOutcome.invalidCredentials);
      expect(provider.user, isNull);
      expect(provider.profile, isNull);
      expect(provider.pendingMfaFactorId, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('late profile failure for a signed-out identity cannot clear B (serialized guard)',
        () async {
      final gate = Completer<Profile>();
      profilesRepo.profileGate = gate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = staffProfile();
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = staffProfile(id: 'user-b');

      final aLogin = provider.signIn('a@clinic.test', 'password');
      await pumpAsync();
      await provider.signOut();
      final bLogin = provider.signIn('b@clinic.test', 'password');
      await pumpAsync();
      final pending = profilesRepo.profileGate!;
      profilesRepo.profileGate = null;
      pending.completeError(Exception('late profile failure'));
      await aLogin;

      expect(await bLogin, LoginOutcome.success);
      expect(provider.user?.id, 'user-b');
      expect(provider.profile?.id, 'user-b');
    });

    test('late patient failure for a signed-out identity cannot clear B (serialized guard)',
        () async {
      final patientGate = Completer<Patient?>();
      patientsRepo.patientGate = patientGate;
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      profilesRepo.profilesById['user-a'] = patientProfile();
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = Profile(
        id: 'user-b',
        fullName: 'Patient B',
        role: UserRole.patient,
        acceptedPrivacyAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isActive: true,
      );
      patientsRepo.patientsByProfileId['user-b'] = patientRecord('user-b');

      final aLogin = provider.signIn('a@clinic.test', 'password');
      await pumpAsync();
      await provider.signOut();
      final bLogin = provider.signIn('b@clinic.test', 'password');
      await pumpAsync();
      final pending = patientsRepo.patientGate!;
      patientsRepo.patientGate = null;
      pending.completeError(Exception('late patient failure'));
      await aLogin;

      expect(await bLogin, LoginOutcome.success);
      expect(provider.user?.id, 'user-b');
      expect(provider.patient?.profileId, 'user-b');
      expect(provider.isOnboarded, isTrue);
    });
  });

  group('interrupted login preserves the newer request', () {
    for (final failCredentials in [false, true]) {
      test(
        'late credentials (failure=$failCredentials) preserve B loading',
        () async {
          final aGate = Completer<void>();
          final aStarted = Completer<void>();
          final bGate = Completer<Profile>();
          final bStarted = Completer<void>();
          mockAuth.usersByEmail['a@clinic.test'] = userA;
          mockAuth.usersByEmail['b@clinic.test'] = userB;
          mockAuth.credentialGates['a@clinic.test'] = aGate;
          mockAuth.credentialStarted['a@clinic.test'] = aStarted;
          profilesRepo.gatesById['user-b'] = bGate;
          profilesRepo.startedById['user-b'] = bStarted;
          final aLogin = provider.signIn('a@clinic.test', 'password');
          await aStarted.future;
          await provider.signOut();
          final bLogin = provider.signIn('b@clinic.test', 'password');
          await bStarted.future;
          expect(provider.isLoading, isTrue);
          if (failCredentials) {
            aGate.completeError(const AuthException('old login failure'));
          } else {
            aGate.complete();
          }
          expect(await aLogin, LoginOutcome.invalidCredentials);
          expect(provider.isLoading, isTrue);
          expect(provider.errorMessage, isNull);
          bGate.complete(staffProfile(id: 'user-b'));
          expect(await bLogin, LoginOutcome.success);
          expect(provider.user?.id, 'user-b');
          expect(provider.isLoading, isFalse);
        },
      );
    }

    test('late profile completion preserves B loading', () async {
      final aGate = Completer<Profile>();
      final aStarted = Completer<void>();
      final bGate = Completer<Profile>();
      final bStarted = Completer<void>();
      mockAuth.usersByEmail['a@clinic.test'] = userA;
      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.gatesById['user-a'] = aGate;
      profilesRepo.startedById['user-a'] = aStarted;
      profilesRepo.gatesById['user-b'] = bGate;
      profilesRepo.startedById['user-b'] = bStarted;
      final aLogin = provider.signIn('a@clinic.test', 'password');
      await aStarted.future;
      await provider.signOut();
      final bLogin = provider.signIn('b@clinic.test', 'password');
      aGate.complete(staffProfile());
      expect(await aLogin, LoginOutcome.invalidCredentials);
      await bStarted.future;
      expect(provider.isLoading, isTrue);
      bGate.complete(staffProfile(id: 'user-b'));
      expect(await bLogin, LoginOutcome.success);
      expect(provider.user?.id, 'user-b');
      expect(provider.isLoading, isFalse);
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

    testWidgets('staff B verifies its own MFA after A signs out',
        (tester) async {
      expect(await signInAdminAPending('factor-a1'), LoginOutcome.mfaRequired);
      await provider.signOut();

      mockAuth.usersByEmail['b@clinic.test'] = userB;
      profilesRepo.profilesById['user-b'] = receptionistProfile();
      mfaService.stepUpRequired = true;
      mfaService.verifiedFactorsByUserId['user-b'] = [makeFactor('factor-b2')];
      // The screen B lands on is the one its permissions open, not the one
      // its role text names: the receptionist holds the reception queue
      // permissions.
      permissionService.permissions = {
        PermissionConstants.documentsManage,
        PermissionConstants.queueManage,
      };
      expect(await provider.signIn('b@clinic.test', 'password'),
          LoginOutcome.mfaRequired);

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
      expect(provider.pendingMfaFactorId, 'factor-b2');
      expect(provider.needsMfaEnrollment, isFalse);
      expect(router.router.state.matchedLocation, '/mfa-verify');
    });
  });
}
