import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/domain/patient_record_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/profile_screen.dart';

/// Patient repository whose lookup outcome the test controls.
class FakePatientsRepository extends PatientsRepository {
  /// When set, the lookup throws this instead of returning a row.
  Object? failure;

  /// The row the lookup returns when [failure] is null.
  Patient? row;

  /// Number of lookups started.
  int calls = 0;

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return row;
  }
}

class FakeProfilesRepository extends ProfilesRepository {
  @override
  Future<Profile> getProfile(String id) async {
    return Profile(
      id: id,
      fullName: 'Jane Patient',
      role: UserRole.patient,
      acceptedPrivacyAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<Profile> updateProfile(Profile profile) async => profile;
}

class MockGoTrueClient extends GoTrueClient {
  bool signOutCalled = false;
  User? signedInUser;

  MockGoTrueClient() : super(autoRefreshToken: false);

  @override
  Session? get currentSession => null;

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    final user = signedInUser!;
    return AuthResponse(
      user: user,
      session: Session(accessToken: 'access-token', tokenType: 'bearer', user: user),
    );
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    signOutCalled = true;
  }
}

class MockSupabaseClient extends SupabaseClient {
  final GoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth)
      : super(
          'https://example.invalid',
          'mock-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );

  @override
  GoTrueClient get auth => mockAuth;
}

/// Auth provider that counts how often the patient lookup was retried.
class CountingAuthProvider extends AuthProvider {
  int retryCalls = 0;

  CountingAuthProvider({
    required super.client,
    required super.patientsRepo,
    required super.profilesRepo,
  });

  @override
  Future<void> retryPatientLookup() async {
    retryCalls++;
    await super.retryPatientLookup();
  }
}

User testUser({String id = 'auth-user-1'}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
    email: 'jane@example.com',
  );
}

Profile patientProfile({String id = 'auth-user-1'}) {
  return Profile(
    id: id,
    fullName: 'Jane Patient',
    role: UserRole.patient,
    acceptedPrivacyAt: DateTime.now(),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

Patient testPatient({
  String id = 'patient-row-1',
  String profileId = 'auth-user-1',
}) {
  return Patient(
    id: id,
    profileId: profileId,
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

CountingAuthProvider buildAuthProvider(
  PatientsRepository patientsRepo, {
  MockGoTrueClient? goTrue,
}) {
  return CountingAuthProvider(
    client: MockSupabaseClient(goTrue ?? MockGoTrueClient()),
    patientsRepo: patientsRepo,
    profilesRepo: FakeProfilesRepository(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getAll') return <String, Object>{};
    return true;
  });

  late MockGoTrueClient goTrue;

  setUp(() {
    // Every repository read is intercepted: no request leaves the test.
    SupabaseService.mockClient = SupabaseClient(
      'https://example.invalid',
      'fake-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode(<Object>[]),
          200,
          request: request,
          headers: const {
            'content-type': 'application/json',
            'content-range': '0-0/0',
          },
        );
      }),
    );
    goTrue = MockGoTrueClient();
  });

  tearDown(() {
    SupabaseService.mockClient = null;
  });

  group('ProfileScreen patient record states', () {
    Future<void> pumpProfile(WidgetTester tester, AuthProvider auth) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('a failed lookup shows an error with a retry, never a spinner',
        (tester) async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure(
          'Connection failed: Please check your internet connection.',
        );
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser(), profile: patientProfile());
      await auth.retryPatientLookup();
      expect(auth.patientRecordState, PatientRecordState.failed);

      await pumpProfile(tester, auth);

      expect(find.text('Could not load your patient record'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Clinical Demographic Details'), findsNothing);

      // Tapping Retry re-runs the patient lookup.
      final callsBefore = repo.calls;
      final retriesBefore = auth.retryCalls;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(auth.retryCalls, retriesBefore + 1);
      expect(repo.calls, callsBefore + 1);
      expect(find.text('Could not load your patient record'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a lookup that finds no row shows the recovery state, never a spinner',
        (tester) async {
      final repo = FakePatientsRepository();
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser(), profile: patientProfile());
      await auth.retryPatientLookup();
      expect(auth.patientRecordState, PatientRecordState.missing);

      await pumpProfile(tester, auth);

      expect(find.text('Patient record not found'), findsOneWidget);
      expect(find.textContaining('contact clinic staff'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Clinical Demographic Details'), findsNothing);
    });

    testWidgets('a loaded record shows the profile', (tester) async {
      final repo = FakePatientsRepository()..row = testPatient();
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser(), profile: patientProfile());
      await auth.retryPatientLookup();
      expect(auth.patientRecordState, PatientRecordState.loaded);

      await pumpProfile(tester, auth);

      expect(find.text('Jane Patient'), findsOneWidget);
      expect(find.text('Clinical Demographic Details'), findsOneWidget);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Could not load your patient record'), findsNothing);
      expect(find.text('Patient record not found'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a retry that succeeds shows the profile with the record',
        (tester) async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure(
          'Connection failed: Please check your internet connection.',
        );
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser(), profile: patientProfile());
      await auth.retryPatientLookup();

      await pumpProfile(tester, auth);
      expect(find.text('Could not load your patient record'), findsOneWidget);

      repo.failure = null;
      repo.row = testPatient();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(auth.patientRecordState, PatientRecordState.loaded);
      expect(find.text('Could not load your patient record'), findsNothing);
      expect(find.text('Jane Patient'), findsOneWidget);
      expect(find.text('Clinical Demographic Details'), findsOneWidget);
      // The form was filled with the record that arrived after the first
      // build, instead of being left blank.
      expect(find.text('Jane'), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the recovery state can end the session', (tester) async {
      final repo = FakePatientsRepository();
      final auth = buildAuthProvider(repo, goTrue: goTrue);
      auth.setMockState(user: testUser(), profile: patientProfile());
      await auth.retryPatientLookup();

      await pumpProfile(tester, auth);

      await tester.tap(find.text('Sign Out'));
      await tester.pump();

      expect(goTrue.signOutCalled, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });
  });
}
