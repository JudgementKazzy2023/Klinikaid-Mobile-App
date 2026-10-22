import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/data/mfa_service.dart';
import 'package:klinikaid_mobile/features/auth/domain/login_outcome.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EventAuth extends GoTrueClient {
  EventAuth() : super(autoRefreshToken: false);
  final events = StreamController<AuthState>.broadcast(sync: true);
  bool failSignOut = false;
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
    final user = User(
      id: email!.split('@').first,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );
    return AuthResponse(
      user: user,
      session: Session(
        accessToken: 'fake-token',
        tokenType: 'bearer',
        user: user,
      ),
    );
  }

  @override
  Stream<AuthState> get onAuthStateChange => events.stream;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {
    await signOutGate?.future;
    if (failSignOut) throw const AuthException('Offline');
  }
}

class TestClient extends SupabaseClient {
  TestClient(this.testAuth) : super('https://example.supabase.co', 'fake-key');
  final EventAuth testAuth;
  @override
  GoTrueClient get auth => testAuth;
}

class TestProfiles extends ProfilesRepository {
  @override
  Future<Profile> getProfile(String id) async => Profile(
    id: id,
    fullName: 'Staff $id',
    role: UserRole.receptionist,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    isActive: true,
  );
}

class TestActivity extends SessionActivityService {
  @override
  Future<void> restoreLastActivity() async {}
}

class TestMfa extends MfaService {
  TestMfa(super.client);
  @override
  bool requiresStepUp() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase db;
  late EventAuth auth;
  late AuthProvider provider;

  Future<void> seed() async {
    await db.customStatement(
      '''INSERT INTO cached_patients
      (id, first_name, last_name, date_of_birth, gender, contact_number,
       address, created_at, updated_at)
      VALUES ('patient', 'Test', 'Patient', 0, 'other', '000', 'Clinic', 0, 0)''',
    );
    await db.customStatement(
      '''INSERT INTO cached_documents
      (id, uploader_id, file_name, file_path, file_type, status, ocr_text,
       created_at, updated_at)
      VALUES ('doc', 'a', 'lab.pdf', '/lab.pdf', 'pdf', 'pending', 'private', 0, 0)''',
    );
    await db.customStatement('''INSERT INTO cached_patient_queues
      (id, patient_id, status, department, priority_level, created_at, updated_at)
      VALUES (1, 'patient', 'waiting', 'lab', 'routine', 0, 0)''');
    await db.customStatement(
      '''INSERT INTO cached_department_records
      (id, patient_id, recorder_id, department, test_type, test_results,
       reference_range_status, created_at, updated_at)
      VALUES ('record', 'patient', 'staff', 'lab', 'test', '{}', 'normal', 0, 0)''',
    );
  }

  Future<void> expectCacheCount(int count) async {
    for (final table in [
      'cached_patients',
      'cached_documents',
      'cached_patient_queues',
      'cached_department_records',
    ]) {
      final result = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      expect(result.read<int>('n'), count, reason: table);
    }
    expect(await db.getQueuedDocuments('a'), hasLength(1));
    expect(await db.getQueuedDocuments('b'), hasLength(1));
  }

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    auth = EventAuth();
    final client = TestClient(auth);
    SupabaseService.mockClient = client;
    for (final id in ['a', 'b']) {
      await db.queueOfflineDocument(
        OfflineDocument(
          id: 'draft-$id',
          uploaderId: id,
          fileName: 'draft.pdf',
          localFilePath: '/draft-$id.pdf',
          fileType: 'pdf',
          createdAt: DateTime(2026),
        ),
      );
    }
    provider = AuthProvider(
      client: client,
      localDatabase: db,
      profilesRepo: TestProfiles(),
      verificationService: SupabaseVerificationService(),
      activityService: TestActivity(),
      mfaService: TestMfa(client),
    );
    // Finish initialization before installing a test identity.
    await Future<void>.delayed(Duration.zero);
    expect(
      await provider.signIn('a@clinic.test', 'password'),
      LoginOutcome.success,
    );
    await seed();
  });

  tearDown(() async {
    provider.dispose();
    await auth.events.close();
    await db.close();
    SupabaseService.mockClient = null;
  });

  test(
    'manual sign-out empties four caches and preserves both owners drafts',
    () async {
      await provider.signOut();
      await expectCacheCount(0);
    },
  );

  test('offline sign-out still clears caches', () async {
    auth.failSignOut = true;
    await expectLater(provider.signOut(), throwsA(isA<AuthException>()));
    await expectCacheCount(0);
  });

  test('inactivity sign-out clears caches and keeps drafts', () async {
    await provider.handleInactivityLogout();
    expect(provider.wasLoggedOutForInactivity, isTrue);
    await expectCacheCount(0);
  });

  test('SDK session expiry clears caches without a manual sign-out', () async {
    final finished = Completer<void>();
    provider.addListener(() {
      if (!provider.isLoading &&
          !provider.isAuthenticated &&
          !finished.isCompleted) {
        finished.complete();
      }
    });
    auth.events.add(AuthState(AuthChangeEvent.signedOut, null));
    await finished.future;
    await expectCacheCount(0);
  });

  test('stale sign-out preserves a newer sign-in and its cache', () async {
    final gate = Completer<void>();
    auth.signOutGate = gate;
    final signingOut = provider.signOut();
    expect(
      await provider.signIn('b@clinic.test', 'password'),
      LoginOutcome.success,
    );
    gate.complete();
    await signingOut;
    expect(provider.user?.id, 'b');
    await expectCacheCount(1);
  });
}
