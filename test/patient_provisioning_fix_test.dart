import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/features/auth/data/patient_provisioning_service.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/domain/verification_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

class MockGoTrueClient extends GoTrueClient {
  bool signOutCalled = false;

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
    final user = User(
      id: 'auth-user-1',
      appMetadata: const {},
      userMetadata: data ?? const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
      email: email,
    );
    final session = Session(
      accessToken: 'access-token',
      tokenType: 'bearer',
      user: user,
    );
    return AuthResponse(user: user, session: session);
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    signOutCalled = true;
  }
}

class MockSupabaseClient extends SupabaseClient {
  final MockGoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth) : super('https://example.supabase.co', 'mock-anon-key');

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  @override
  Future<Profile> getProfile(String id) async {
    return Profile(
      id: id,
      fullName: 'Jane Patient',
      role: UserRole.patient,
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

class FakeVerificationService implements VerificationService {
  bool sendCodeCalled = false;
  bool deletePendingUserCalled = false;

  @override
  Future<bool> deletePendingUser() async {
    deletePendingUserCalled = true;
    return true;
  }

  @override
  Future<VerificationResult> sendCode({required String email}) async {
    sendCodeCalled = true;
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
  required ThrowingPatientsRepository patientsRepo,
  required FakeVerificationService verificationService,
  required PatientProvisioningService provisioningService,
}) {
  return AuthProvider(
    client: MockSupabaseClient(auth),
    patientsRepo: patientsRepo,
    profilesRepo: MockProfilesRepository(),
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
        url: 'https://example.supabase.co',
        anonKey: 'mock-anon-key',
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

      final success = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(success, true);
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
        ..functionRan = true;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final success = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(success, false);
      expect(auth.signOutCalled, true);
      expect(verificationService.deletePendingUserCalled, false);
      expect(patientsRepo.createPatientCalls, 0);
    });

    test('invoke network failure calls deletePendingUser before local sign out', () async {
      final auth = MockGoTrueClient();
      final patientsRepo = ThrowingPatientsRepository();
      final verificationService = FakeVerificationService();
      final provisioningService = MockPatientProvisioningService()
        ..shouldFail = true
        ..functionRan = false;
      final provider = buildProvider(
        auth: auth,
        patientsRepo: patientsRepo,
        verificationService: verificationService,
        provisioningService: provisioningService,
      );

      final success = await provider.signUp(
        email: 'jane@example.com',
        password: 'Password123!',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: '123 Test St',
      );

      expect(success, false);
      expect(verificationService.deletePendingUserCalled, true);
      expect(auth.signOutCalled, true);
      expect(patientsRepo.createPatientCalls, 0);
    });
  });
}
