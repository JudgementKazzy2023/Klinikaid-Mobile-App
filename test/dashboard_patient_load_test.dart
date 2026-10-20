import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/domain/patient_record_state.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';

/// Patient repository whose lookup outcome the test controls.
class FakePatientsRepository extends PatientsRepository {
  /// When set, the lookup throws this instead of returning a row.
  Object? failure;

  /// The row the lookup returns when [failure] is null.
  Patient? row;

  int calls = 0;

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return row;
  }
}

/// Patients repository whose lookup for a given profile id can be held open
/// until the test releases it.
class ControllablePatientsRepository extends PatientsRepository {
  /// Rows returned by a lookup that is not held open.
  final Map<String, Patient?> rows = <String, Patient?>{};

  /// Number of lookups started, per profile id.
  final Map<String, int> calls = <String, int>{};

  final Map<String, Completer<Patient?>> _held = <String, Completer<Patient?>>{};

  /// Holds the next lookup for [profileId] open.
  void hold(String profileId) {
    _held[profileId] = Completer<Patient?>();
  }

  /// Releases the held lookup for [profileId] with [row].
  void release(String profileId, {Patient? row}) {
    _held.remove(profileId)!.complete(row);
  }

  /// Releases the held lookup for [profileId] with a failure.
  void releaseWithFailure(String profileId, Object error) {
    _held.remove(profileId)!.completeError(error);
  }

  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    calls[profileId] = (calls[profileId] ?? 0) + 1;
    final held = _held[profileId];
    if (held != null) return held.future;
    return rows[profileId];
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
          'https://example.supabase.co',
          'mock-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );

  @override
  GoTrueClient get auth => mockAuth;
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

AuthProvider buildAuthProvider(
  PatientsRepository patientsRepo, {
  MockGoTrueClient? goTrue,
}) {
  return AuthProvider(
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

  late LocalDatabase localDb;
  late MockGoTrueClient goTrue;
  late List<String> requestPaths;

  setUpAll(() {
    localDb = LocalDatabase(NativeDatabase.memory());
  });

  setUp(() {
    // Every repository read is intercepted: no request leaves the test.
    requestPaths = <String>[];
    SupabaseService.mockClient = SupabaseClient(
      'https://example.invalid',
      'fake-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requestPaths.add(request.url.path);
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

  group('AuthProvider patient record lookup', () {
    test('a failed read is recorded as failed, with the reason', () async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure('Connection failed: Please check your internet connection.');
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      await provider.retryPatientLookup();

      expect(provider.patientRecordState, PatientRecordState.failed);
      expect(provider.patientRecordError, contains('Connection failed'));
      expect(provider.patient, isNull);
    });

    test('a read that finds no row is recorded as missing, not as failed', () async {
      final repo = FakePatientsRepository();
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      await provider.retryPatientLookup();

      expect(provider.patientRecordState, PatientRecordState.missing);
      expect(provider.patientRecordError, isNull);
      expect(provider.patient, isNull);
    });

    test('a read that finds a row is recorded as loaded', () async {
      final repo = FakePatientsRepository()..row = testPatient();
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      await provider.retryPatientLookup();

      expect(provider.patientRecordState, PatientRecordState.loaded);
      expect(provider.patientRecordError, isNull);
      expect(provider.patient?.id, 'patient-row-1');
    });

    test('a retry after a failed read recovers when the read succeeds', () async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure('Connection failed: Please check your internet connection.');
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      await provider.retryPatientLookup();
      expect(provider.patientRecordState, PatientRecordState.failed);

      repo.failure = null;
      repo.row = testPatient();
      await provider.retryPatientLookup();

      expect(provider.patientRecordState, PatientRecordState.loaded);
      expect(provider.patientRecordError, isNull);
      expect(provider.patient?.id, 'patient-row-1');
    });

    test('the session load records a failed patient read', () async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure('Connection failed: Please check your internet connection.');
      final provider = buildAuthProvider(repo, goTrue: goTrue);
      goTrue.signedInUser = testUser();

      await provider.signIn('jane@example.com', 'Password123!');

      expect(provider.patientRecordState, PatientRecordState.failed);
      expect(provider.patientRecordError, contains('Connection failed'));
      expect(provider.patient, isNull);
      provider.dispose();
    });
  });

  group('AuthProvider patient record lookup isolation', () {
    test('a lookup that completes after the session ended is discarded',
        () async {
      final repo = ControllablePatientsRepository();
      repo.hold('auth-user-1');
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      final pending = provider.retryPatientLookup();
      expect(provider.patientRecordState, PatientRecordState.loading);

      // The account signs out while its lookup is still in flight.
      await provider.signOut();

      // The late result of the ended session arrives.
      repo.release('auth-user-1', row: testPatient());
      await pending;

      expect(provider.patient, isNull);
      expect(provider.isOnboarded, isFalse);
      expect(provider.patientRecordState, isNot(PatientRecordState.loaded));
      expect(provider.patientRecordError, isNull);
    });

    test('a late result does not overwrite the patient of the new account',
        () async {
      final repo = ControllablePatientsRepository();
      repo.hold('auth-user-1');
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      final pending = provider.retryPatientLookup();

      // Another account takes over the session and loads its own patient row.
      provider.setMockState(user: testUser(id: 'auth-user-2'));
      repo.rows['auth-user-2'] =
          testPatient(id: 'patient-row-2', profileId: 'auth-user-2');
      await provider.retryPatientLookup();
      expect(provider.patient?.id, 'patient-row-2');

      // The late result of the previous account arrives.
      repo.release('auth-user-1', row: testPatient());
      await pending;

      expect(provider.patient?.id, 'patient-row-2');
      expect(provider.patientRecordState, PatientRecordState.loaded);
    });

    test('a late failure does not mark the new session as failed', () async {
      final repo = ControllablePatientsRepository();
      repo.hold('auth-user-1');
      final provider = buildAuthProvider(repo);
      provider.setMockState(user: testUser());

      final pending = provider.retryPatientLookup();

      // The account signs out while its lookup is still in flight.
      await provider.signOut();

      // The late failure of the ended session arrives.
      repo.releaseWithFailure(
        'auth-user-1',
        const NetworkFailure(
          'Connection failed: Please check your internet connection.',
        ),
      );
      await pending;

      expect(provider.patientRecordState, isNot(PatientRecordState.failed));
      expect(provider.patientRecordError, isNull);
      expect(provider.patient, isNull);
    });
  });

  group('DashboardScreen patient record states', () {
    Future<void> pumpDashboard(
      WidgetTester tester,
      AuthProvider auth,
      DashboardProvider dashboard,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<DashboardProvider>.value(value: dashboard),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets('a failed lookup shows an error with a retry, never a spinner',
        (tester) async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure('Connection failed: Please check your internet connection.');
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser());
      await auth.retryPatientLookup();

      final dashboard = DashboardProvider(localDb);
      await pumpDashboard(tester, auth, dashboard);

      expect(find.text('Could not load your patient record'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Status Summary'), findsNothing);
    });

    testWidgets('a lookup that finds no row shows the recovery state, never a spinner',
        (tester) async {
      final repo = FakePatientsRepository();
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser());
      await auth.retryPatientLookup();

      final dashboard = DashboardProvider(localDb);
      await pumpDashboard(tester, auth, dashboard);

      expect(find.text('Patient record not found'), findsOneWidget);
      expect(find.textContaining('contact clinic staff'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Status Summary'), findsNothing);
    });

    testWidgets('a retry after a failed lookup shows the dashboard and clears loading',
        (tester) async {
      final repo = FakePatientsRepository()
        ..failure = const NetworkFailure('Connection failed: Please check your internet connection.');
      final auth = buildAuthProvider(repo);
      auth.setMockState(user: testUser());
      await auth.retryPatientLookup();

      final dashboard = DashboardProvider(localDb);
      await pumpDashboard(tester, auth, dashboard);
      expect(find.text('Could not load your patient record'), findsOneWidget);

      repo.failure = null;
      repo.row = testPatient();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(auth.patientRecordState, PatientRecordState.loaded);
      expect(find.text('Could not load your patient record'), findsNothing);
      expect(find.text('Status Summary'), findsOneWidget);
      expect(find.text('Jane Patient'), findsOneWidget);
      expect(find.text('Document Templates'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The dashboard data was fetched and the loading state was cleared.
      expect(dashboard.isLoading, isFalse);
      expect(
        requestPaths.where((path) => path.endsWith('documents')).isNotEmpty,
        isTrue,
      );
    });

    testWidgets('the recovery state can end the session', (tester) async {
      final repo = FakePatientsRepository();
      final auth = buildAuthProvider(repo, goTrue: goTrue);
      auth.setMockState(user: testUser());
      await auth.retryPatientLookup();

      final dashboard = DashboardProvider(localDb);
      await pumpDashboard(tester, auth, dashboard);

      await tester.tap(find.text('Sign Out'));
      await tester.pump();

      expect(goTrue.signOutCalled, isTrue);
      expect(auth.isAuthenticated, isFalse);
    });
  });
}
