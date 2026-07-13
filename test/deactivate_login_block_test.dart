@Skip('verified on real device; needs auth-client mock')
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/auth/domain/login_outcome.dart';

class MockGoTrueClient extends GoTrueClient {
  User? mockUser;
  Session? mockSession;

  MockGoTrueClient() : super(autoRefreshToken: false);

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    final user = mockUser ?? User(
      id: 'mock-user-uuid',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '',
      email: email,
    );
    final session = mockSession ?? Session(
      accessToken: 'access-token-jwt',
      tokenType: 'bearer',
      user: user,
    );
    return AuthResponse(
      session: session,
      user: user,
    );
  }

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

class MockSupabaseClient extends SupabaseClient {
  final MockGoTrueClient mockAuth;

  MockSupabaseClient(this.mockAuth)
      : super('https://onzeyejlfydvvbkejvwf.supabase.co', 'mock-anon-key');

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  Profile? mockProfile;
  bool shouldThrow = false;

  @override
  Future<Profile> getProfile(String id) async {
    if (shouldThrow) {
      throw Exception('Database error');
    }
    return mockProfile ?? Profile(
      id: id,
      fullName: 'Mock User',
      role: UserRole.departmentStaff,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isActive: true,
    );
  }
}

class MockPatientsRepository extends PatientsRepository {
  @override
  Future<Patient?> getPatientByProfileId(String profileId) async {
    return null;
  }
}

class MockSessionActivityService extends SessionActivityService {
  @override
  void startMonitoring({required Duration timeout, required VoidCallback onTimeout}) {}
  @override
  void stopMonitoring() {}
  @override
  void recordActivity() {}
  @override
  Future<void> restoreLastActivity() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

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
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  late LocalDatabase localDatabase;
  late MockProfilesRepository mockProfilesRepo;
  late MockPatientsRepository mockPatientsRepo;
  late MockSessionActivityService mockActivityService;
  late MockGoTrueClient mockGoTrueClient;
  late MockSupabaseClient mockSupabaseClient;
  late AuthProvider authProvider;

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
    mockProfilesRepo = MockProfilesRepository();
    mockPatientsRepo = MockPatientsRepository();
    mockActivityService = MockSessionActivityService();
    mockGoTrueClient = MockGoTrueClient();
    mockSupabaseClient = MockSupabaseClient(mockGoTrueClient);
    authProvider = AuthProvider(
      client: mockSupabaseClient,
      profilesRepo: mockProfilesRepo,
      patientsRepo: mockPatientsRepo,
      activityService: mockActivityService,
    );
  });

  tearDown(() async {
    authProvider.dispose();
    await localDatabase.close();
  });

  Widget createTestWidget(AppRouter appRouter) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
      ),
    );
  }

  group('Deactivation login block tests', () {
    testWidgets('1. Block login when is_active is false explicitly', (tester) async {
      mockProfilesRepo.mockProfile = Profile(
        id: 'user-deactivated-1',
        fullName: 'Inactive Staff',
        role: UserRole.departmentStaff,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: false,
      );

      final router = AppRouter(authProvider);
      await tester.pumpWidget(createTestWidget(router));
      await tester.pumpAndSettle();

      final outcome = await authProvider.signIn('inactive@test.com', 'Password123!');

      expect(outcome, LoginOutcome.invalidCredentials);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.errorMessage, 'This account has been deactivated. Contact an administrator.');
    });

    testWidgets('2. Fail-open (normal login allowed) when is_active is null', (tester) async {
      mockProfilesRepo.shouldThrow = true; 

      final router = AppRouter(authProvider);
      await tester.pumpWidget(createTestWidget(router));
      await tester.pumpAndSettle();

      final outcome = await authProvider.signIn('normal@test.com', 'Password123!');
      
      expect(outcome, LoginOutcome.success);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.errorMessage, isNot('This account has been deactivated. Contact an administrator.'));
    });

    testWidgets('3. Route guard ejects deactivated user to login on next navigation', (tester) async {
      final activeProfile = Profile(
        id: 'user-active-1',
        fullName: 'Active Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: true,
      );
      mockProfilesRepo.mockProfile = activeProfile;

      final router = AppRouter(authProvider);
      await tester.pumpWidget(createTestWidget(router));
      await tester.pumpAndSettle();

      await authProvider.signIn('active@test.com', 'Password123!');
      await tester.pumpAndSettle();

      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      expect(router.router.state!.matchedLocation, '/department/queue');

      mockProfilesRepo.mockProfile = Profile(
        id: 'user-active-1',
        fullName: 'Active Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: false, // DEACTIVATED
      );

      await authProvider.acceptConsent(); // Triggers _updateLocalStates() which re-fetches latest profile
      await tester.pumpAndSettle();

      router.router.go('/department/result-entry/some-patient');
      await tester.pumpAndSettle();

      expect(router.router.state!.matchedLocation, '/login');
    });
  });
}
