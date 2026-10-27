import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/features/auth/data/patient_provisioning_service.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/domain/signup_outcome.dart';
import 'package:klinikaid_mobile/features/auth/domain/verification_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

class MockGoTrueClient extends GoTrueClient {
  bool signOutCalled = false;

  /// Auth returns no session, as when email confirmation is required.
  bool confirmationRequired = false;

  /// Auth refuses the sign-up because the address already has an account.
  bool alreadyRegistered = false;

  /// Announces the new session to listeners, as the SDK does.
  bool emitSignedIn = false;
  int signUpCalls = 0;

  MockGoTrueClient() : super(autoRefreshToken: false);

  @override
  Session? get currentSession => null;

  @override
  Future<AuthResponse> signUp({
    String? email,
    String? phone,
    required String password,
    String? emailRedirectTo,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    signUpCalls++;
    if (alreadyRegistered) {
      throw const AuthException('User already registered');
    }
    final user = User(
      id: 'auth-user-1',
      appMetadata: const {},
      userMetadata: data ?? const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
      email: email,
    );
    if (confirmationRequired) {
      return AuthResponse(user: user);
    }
    final session = Session(
      accessToken: 'access-token',
      tokenType: 'bearer',
      user: user,
    );
    // Like the SDK: listeners hear about the new session as sign-up returns,
    // while the caller carries on.
    if (emitSignedIn) events.add(AuthState(AuthChangeEvent.signedIn, session));
    return AuthResponse(user: user, session: session);
  }

  final events = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    signOutCalled = true;
    // Like the SDK: listeners hear about the sign-out after the caller has
    // moved on.
    Future(() => events.add(const AuthState(AuthChangeEvent.signedOut, null)));
  }
}

class MockSupabaseClient extends SupabaseClient {
  final MockGoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth) : super('https://example.invalid', 'mock-anon-key');

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  bool failConsentWrite = false;
  int consentWrites = 0;
  DateTime? savedConsentAt;

  @override
  Future<Profile> getProfile(String id) async {
    return Profile(
      id: id,
      fullName: 'Jane Patient',
      role: UserRole.patient,
      acceptedPrivacyAt: savedConsentAt,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<Profile> recordPrivacyAcceptance(String id, DateTime acceptedAt) async {
    consentWrites++;
    if (failConsentWrite) {
      throw const DatabaseFailure('Could not record consent.');
    }
    savedConsentAt = acceptedAt;
    return Profile(
      id: id,
      fullName: 'Jane Patient',
      role: UserRole.patient,
      acceptedPrivacyAt: acceptedAt,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<Profile> updateProfile(Profile profile) async => profile;
}

class ThrowingPatientsRepository extends PatientsRepository {
  int createPatientCalls = 0;

  @override
  Future<Patient> createPatient(Patient patient) async {
    createPatientCalls++;
    throw StateError('Direct patients insert should not be called from registration.');
  }

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async => null;
}

/// Simulates a device that cannot read the patients table at all.
class OfflinePatientsRepository extends PatientsRepository {
  int createPatientCalls = 0;
  int lookupCalls = 0;

  @override
  Future<Patient> createPatient(Patient patient) async {
    createPatientCalls++;
    throw StateError('Direct patients insert should not be called from registration.');
  }

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    lookupCalls++;
    throw StateError('Lookup failed: device is offline.');
  }
}

/// Fails every provisioning call with the outcome of its call index
/// (the last one repeats), so a first attempt and its retry can differ.
class SequencedProvisioningService implements PatientProvisioningService {
  SequencedProvisioningService(this.outcomes);

  final List<PatientProvisioningOutcome> outcomes;
  int callCount = 0;

  @override
  Future<Patient?> createPatientRecord({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    final outcome = outcomes[callCount < outcomes.length ? callCount : outcomes.length - 1];
    callCount++;
    throw PatientProvisioningException(
      outcome == PatientProvisioningOutcome.rejected
          ? 'Patient provisioning failed.'
          : 'Network failure.',
      outcome: outcome,
    );
  }
}

class FakePatientsRepository extends PatientsRepository {
  final Patient? patient;

  FakePatientsRepository(this.patient);

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async => patient;
}

class FakeVerificationService implements VerificationService {
  bool sendCodeCalled = false;
  bool deletePendingUserCalled = false;
  bool sendFails = false;

  @override
  Future<bool> deletePendingUser() async {
    deletePendingUserCalled = true;
    return true;
  }

  @override
  Future<VerificationResult> sendCode({required String email}) async {
    sendCodeCalled = true;
    if (sendFails) {
      return VerificationResult(
        status: VerificationStatus.networkError,
        errorMessage: 'Code not sent.',
      );
    }
    return VerificationResult(
      status: VerificationStatus.codeSent,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<VerificationResult> verifyCode({required String email, required String code}) async {
    return VerificationResult(status: VerificationStatus.verified);
  }
}

AuthProvider buildProvider({
  required MockGoTrueClient auth,
  required PatientsRepository patientsRepo,
  required FakeVerificationService verificationService,
  required PatientProvisioningService provisioningService,
  MockProfilesRepository? profilesRepo,
}) {
  return AuthProvider(
    client: MockSupabaseClient(auth),
    patientsRepo: patientsRepo,
    profilesRepo: profilesRepo ?? MockProfilesRepository(),
    verificationService: verificationService,
    patientProvisioningService: provisioningService,
  );
}

Patient patient() {
  return Patient(
    id: 'patient-row-1',
    profileId: 'auth-user-1',
    firstName: 'Jane',
    lastName: 'Patient',
    dateOfBirth: DateTime(1990, 1, 1),
    gender: Gender.female,
    contactNumber: '09123456789',
    email: 'jane@example.com',
    address: '123 Test St',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
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

  group('patient provisioning registration fix', () {
    test('success calls create-patient-record flow and never direct patients insert', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.registered);
      expect(provisioningService.wasCalled, true);
      expect(patientsRepo.createPatientCalls, 0);
      expect(verificationService.sendCodeCalled, true);
      expect(verificationService.deletePendingUserCalled, false);
      expect(provider.patient?.profileId, 'auth-user-1');
    });

    test('function-ran failure signs out without fallback deletePendingUser', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..shouldFail = true
        ..outcome = PatientProvisioningOutcome.rejected;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(auth.signOutCalled, true);
      expect(verificationService.deletePendingUserCalled, false);
      expect(patientsRepo.createPatientCalls, 0);
      expect(provider.errorMessage, 'Patient provisioning failed.');
    });

    test('a 400 field rejection deletes the pending user and shows the error', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..shouldFail = true
        ..outcome = PatientProvisioningOutcome.rejected
        ..status = 400;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(verificationService.deletePendingUserCalled, true);
      expect(auth.signOutCalled, true);
      expect(provisioningService.callCount, 1);
      expect(provider.errorMessage, 'Patient provisioning failed.');
    });

    test('uncertain outcome keeps the account and uses the existing patient row', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = FakePatientsRepository(patient());
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..shouldFail = true
        ..outcome = PatientProvisioningOutcome.uncertain;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.registered);
      expect(verificationService.deletePendingUserCalled, false);
      expect(provider.patient?.profileId, 'auth-user-1');
      expect(provisioningService.callCount, 1);
      expect(auth.signOutCalled, false);
    });

    test('uncertain outcome retries the idempotent function when no row exists', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..outcome = PatientProvisioningOutcome.uncertain
        ..failFirstCalls = 1
        ..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.registered);
      expect(provisioningService.callCount, 2);
      expect(verificationService.deletePendingUserCalled, false);
      expect(provider.patient?.profileId, 'auth-user-1');
    });

    test('invoke network failure never deletes the pending user', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..shouldFail = true
        ..outcome = PatientProvisioningOutcome.uncertain;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(verificationService.deletePendingUserCalled, false);
      expect(auth.signOutCalled, true);
      expect(patientsRepo.createPatientCalls, 0);
      expect(provisioningService.callCount, 2);      expect(provider.errorMessage, isNotNull);
    });

    test('known rejection after a clean lookup deletes the pending user', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = SequencedProvisioningService([
        PatientProvisioningOutcome.uncertain,
        PatientProvisioningOutcome.rejected,
      ]);
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(provisioningService.callCount, 2);
      expect(verificationService.deletePendingUserCalled, true);
      expect(auth.signOutCalled, true);
      expect(patientsRepo.createPatientCalls, 0);
    });

    test('failed lookup with an uncertain retry keeps the account', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = OfflinePatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = SequencedProvisioningService([
        PatientProvisioningOutcome.uncertain,
        PatientProvisioningOutcome.uncertain,
      ]);
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(provisioningService.callCount, 2);
      expect(patientsRepo.lookupCalls, 1);
      expect(verificationService.deletePendingUserCalled, false);
      expect(auth.signOutCalled, true);
      expect(patientsRepo.createPatientCalls, 0);
    });

    test('no session (confirmation required) provisions nothing and says to contact reception', () async {
      final auth = MockGoTrueClient()..confirmationRequired = true;
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.noSession);
      expect(provisioningService.wasCalled, false);
      expect(patientsRepo.createPatientCalls, 0);
      expect(verificationService.sendCodeCalled, false);
      expect(provider.isAuthenticated, false);
      expect(provider.user, isNull);
      expect(auth.signOutCalled, true);
      expect(provider.errorMessage, kSignUpNoSessionMessage);
    });

    test('a refused sign-up keeps the reason on screen and provisions nothing', () async {
      final auth = MockGoTrueClient()..alreadyRegistered = true;
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.failed);
      expect(provisioningService.wasCalled, false);
      expect(verificationService.sendCodeCalled, false);
      // Assigning `_user` clears the error message, so the reason must be set
      // after that reset for it to reach the screen.
      expect(provider.errorMessage, 'User already registered');
    });

    test('a consent write that fails after provisioning keeps the record and says to sign in', () async {
      final auth = MockGoTrueClient();
      final profilesRepo = MockProfilesRepository()..failConsentWrite = true;
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: ThrowingPatientsRepository(),
        verificationService: verificationService,
        provisioningService: provisioningService,
        profilesRepo: profilesRepo,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.setupIncomplete);
      expect(provisioningService.callCount, 1);
      expect(verificationService.sendCodeCalled, false);
      expect(provider.errorMessage, kSignUpSetupIncompleteMessage);
      expect(provider.isAuthenticated, false);

      // The signed-out event that follows must leave the message on screen.
      await pumpEventQueue();
      expect(provider.errorMessage, kSignUpSetupIncompleteMessage);

      // The retry is refused by Auth before any provisioning call, so the
      // patient row is not duplicated.
      auth.alreadyRegistered = true;
      final retry = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(retry, SignUpOutcome.failed);
      expect(provisioningService.callCount, 1);
      expect(provider.errorMessage, 'User already registered');
    });

    test('a fresh sign-up is not signed out for an idle time saved long ago', () async {
      // The last activity the phone saved is days old, from an earlier session.
      SharedPreferences.setMockInitialValues({'last_activity_ms': 0});
      final auth = MockGoTrueClient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: ThrowingPatientsRepository(),
        verificationService: FakeVerificationService(),
        provisioningService: MockPatientProvisioningService()..patient = patient(),
      );
      await pumpEventQueue();

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );
      expect(outcome, SignUpOutcome.registered);

      // Entering the code re-reads the account, which is where the idle check ran.
      expect(await provider.verifyCode('123456'), true);
      expect(auth.signOutCalled, false);
      expect(provider.isAuthenticated, true);
      expect(provider.wasLoggedOutForInactivity, false);
    });

    test('sign-up stays loading until the consent is saved, so no consent screen flashes', () async {
      SharedPreferences.setMockInitialValues({});
      final gate = Completer<void>();
      final provider = buildProvider(
        auth: MockGoTrueClient()..emitSignedIn = true,
        patientsRepo: ThrowingPatientsRepository(),
        verificationService: FakeVerificationService(),
        provisioningService: _GatedProvisioningService(gate.future)..patient = patient(),
      );
      await pumpEventQueue();

      final signUp = provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );
      // The signed-in event has refreshed the account; the consent is not saved.
      await pumpEventQueue();
      expect(provider.isLoading, true);

      gate.complete();
      expect(await signUp, SignUpOutcome.registered);
      expect(provider.isLoading, false);
      expect(provider.hasConsented, true);
    });

    test('a verification code that fails to send after provisioning says to sign in', () async {
      final auth = MockGoTrueClient();
      final verificationService = FakeVerificationService()..sendFails = true;
      final profilesRepo = MockProfilesRepository();
      final provisioningService = MockPatientProvisioningService()..patient = patient();
      final provider = buildProvider(
        auth: auth,
        patientsRepo: ThrowingPatientsRepository(),
        verificationService: verificationService,
        provisioningService: provisioningService,
        profilesRepo: profilesRepo,
      );

      final outcome = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(outcome, SignUpOutcome.setupIncomplete);
      expect(provisioningService.callCount, 1);
      expect(profilesRepo.consentWrites, 1);
      expect(verificationService.deletePendingUserCalled, false);
      expect(auth.signOutCalled, true);
      expect(provider.errorMessage, kSignUpSetupIncompleteMessage);
    });
  });
}

/// Holds provisioning until [gate] completes, as a slow network would.
class _GatedProvisioningService extends MockPatientProvisioningService {
  _GatedProvisioningService(this.gate);
  final Future<void> gate;

  @override
  Future<Patient?> createPatientRecord({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    await gate;
    return super.createPatientRecord(
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: dateOfBirth,
      gender: gender,
      contactNumber: contactNumber,
      email: email,
      address: address,
    );
  }
}
