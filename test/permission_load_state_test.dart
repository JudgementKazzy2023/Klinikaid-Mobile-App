import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_service.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/data/mfa_service.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/data/verification_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

/// An account whose permission read ended in a known state.
class RouterAuthProvider extends AuthProvider {
  RouterAuthProvider({
    required this.state,
    this.grants = const <String>{},
    this.role = UserRole.receptionist,
  });

  PermissionLoadState state;
  Set<String> grants;
  UserRole role;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  Profile? get profile => Profile(
        id: 'staff-uuid',
        fullName: 'Staff Under Test',
        role: role,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  @override
  Set<String> get permissions => grants;

  @override
  PermissionLoadState get permissionLoadState => state;

  // Staff already past MFA: these tests are about the permission answer.
  @override
  bool get isAal2 => true;
}

class MockGoTrueClient extends GoTrueClient {
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
    return AuthResponse(
      session: Session(
        accessToken: 'access-token-jwt',
        tokenType: 'bearer',
        user: User(
          id: 'staff-uuid',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
          email: email ?? 'staff@clinic.test',
        ),
      ),
      user: null,
    );
  }

  @override
  Future<AuthResponse> refreshSession([String? refreshToken]) async =>
      AuthResponse();

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

class MockSupabaseClient extends SupabaseClient {
  MockSupabaseClient(this.mockAuth)
      : super('https://example.supabase.co', 'mock-anon-key');

  final MockGoTrueClient mockAuth;

  @override
  GoTrueClient get auth => mockAuth;
}

class MockProfilesRepository extends ProfilesRepository {
  Profile? profile;

  @override
  Future<Profile> getProfile(String id) async => profile!;
}

class MockActivityService extends SessionActivityService {
  @override
  Duration get idleTime => Duration.zero;

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

class MockMfaService extends MfaService {
  MockMfaService(this.authClient, SupabaseClient client) : super(client);

  final GoTrueClient authClient;

  @override
  bool requiresStepUp() => false;

  @override
  Future<List<Factor>> listVerifiedFactors() async => const <Factor>[];
}

/// A permission read that answers what the test tells it to answer.
class ControllablePermissionService implements PermissionService {
  Set<String> grants = const <String>{};
  bool shouldFail = false;

  @override
  Future<Set<String>> loadPermissions() async {
    if (shouldFail) {
      throw const PermissionLoadException('Mock permission load failed');
    }
    return grants;
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

  group('the permission read keeps a failure apart from an empty answer', () {
    late MockGoTrueClient mockAuth;
    late MockSupabaseClient mockClient;
    late MockProfilesRepository profilesRepo;
    late ControllablePermissionService permissionService;
    late AuthProvider provider;

    setUp(() {
      mockAuth = MockGoTrueClient();
      mockClient = MockSupabaseClient(mockAuth);
      profilesRepo = MockProfilesRepository()
        ..profile = Profile(
          id: 'staff-uuid',
          fullName: 'Staff Under Test',
          role: UserRole.receptionist,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
      permissionService = ControllablePermissionService();
      provider = AuthProvider(
        client: mockClient,
        profilesRepo: profilesRepo,
        verificationService: MockVerificationService(),
        permissionService: permissionService,
        activityService: MockActivityService(),
        mfaService: MockMfaService(mockAuth, mockClient),
      );
    });

    tearDown(() => provider.dispose());

    test('a failed read leaves the grants unknown and offers a retry',
        () async {
      permissionService.shouldFail = true;

      await provider.signIn('staff@clinic.test', 'password');

      expect(provider.permissionLoadState, PermissionLoadState.failed);
      expect(provider.permissionLoadError, isNotNull);
      // The grants are unknown, not empty: the read never answered.
      expect(provider.permissions, isEmpty);
      expect(provider.hasNoPermissions, isFalse);
      expect(provider.permissionLoadFailed, isTrue);
    });

    test('a read that answers with nothing is a denial, not a failure',
        () async {
      permissionService.grants = const <String>{};

      await provider.signIn('staff@clinic.test', 'password');

      expect(provider.permissionLoadState, PermissionLoadState.loaded);
      expect(provider.permissionLoadError, isNull);
      expect(provider.hasNoPermissions, isTrue);
      expect(provider.permissionLoadFailed, isFalse);
    });

    test('the retry asks the server again and takes the answer', () async {
      permissionService.shouldFail = true;
      await provider.signIn('staff@clinic.test', 'password');
      expect(provider.permissionLoadState, PermissionLoadState.failed);

      permissionService.shouldFail = false;
      permissionService.grants = <String>{
        PermissionConstants.documentsManage,
        PermissionConstants.queueManage,
      };
      await provider.retryPermissionLoad();

      expect(provider.permissionLoadState, PermissionLoadState.loaded);
      expect(provider.permissionLoadError, isNull);
      expect(
        provider.hasAllPermissions(PermissionConstants.receptionQueue),
        isTrue,
      );
    });
  });

  group('the router answers a failed read and an empty answer differently', () {
    Widget app(AuthProvider auth, AppRouter router) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp.router(routerConfig: router.router),
        );

    testWidgets('a failed read shows the retry state, not a denial',
        (tester) async {
      final auth = RouterAuthProvider(state: PermissionLoadState.failed);
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/reception/queue');
      await tester.pumpAndSettle();

      // The account is not routed as if it held nothing, and not as if it
      // held the permissions of its role: the read failed, so the app says
      // so and offers a retry.
      expect(router.router.state.matchedLocation, kPermissionAccessRoute);
      expect(
        find.byKey(const Key('permission_access_retry_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('permission_access_sign_out_button')),
        findsNothing,
      );
    });

    testWidgets('a read that answered with nothing shows the denial',
        (tester) async {
      final auth = RouterAuthProvider(state: PermissionLoadState.loaded);
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/reception/queue');
      await tester.pumpAndSettle();

      expect(router.router.state.matchedLocation, kPermissionAccessRoute);
      expect(
        find.byKey(const Key('permission_access_sign_out_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('permission_access_retry_button')),
        findsNothing,
      );
    });

    testWidgets('a read with grants opens the screens the grants allow',
        (tester) async {
      final auth = RouterAuthProvider(
        state: PermissionLoadState.loaded,
        grants: <String>{
          PermissionConstants.documentsManage,
          PermissionConstants.queueManage,
        },
      );
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/reception/queue');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, '/reception/queue');

      // A screen the grants do not open is turned away, and the account lands
      // on the screen its grants do open.
      router.router.go('/admin/staff');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, '/reception/queue');
    });

    testWidgets(
        'a landing route the gate rejects is refused, not bypassed',
        (tester) async {
      // `roles.read` alone does not open the admin area, so `/admin/rbac` is
      // rejected by the same gate the router consults. The redirect must not
      // treat "redirect to the rejected home" as "no change" and leave the
      // account on the screen.
      final auth = RouterAuthProvider(
        state: PermissionLoadState.loaded,
        grants: <String>{PermissionConstants.rolesRead},
      );
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/admin/rbac');
      await tester.pumpAndSettle();
      expect(router.router.state.matchedLocation, kPermissionAccessRoute);

      // The same holds for the landing route itself: a grant set whose home
      // candidate the gate rejects ends on the denial, not on the rejected
      // screen.
      final queueOnly = RouterAuthProvider(
        state: PermissionLoadState.loaded,
        grants: <String>{PermissionConstants.queueManage},
      );
      final queueRouter = AppRouter(queueOnly);
      await tester.pumpWidget(app(queueOnly, queueRouter));
      queueRouter.router.go('/department/records');
      await tester.pumpAndSettle();
      expect(queueRouter.router.state.matchedLocation, kPermissionAccessRoute);
    });

    testWidgets(
        'grants with no mobile screen say so instead of claiming no permission',
        (tester) async {
      // `chat.access` holds a permission the server resolved, but it opens no
      // screen of the mobile app. The access screen must say that, not that
      // the account holds no permission.
      final auth = RouterAuthProvider(
        state: PermissionLoadState.loaded,
        grants: <String>{PermissionConstants.chatAccess},
      );
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/reception/queue');
      await tester.pumpAndSettle();

      expect(router.router.state.matchedLocation, kPermissionAccessRoute);
      expect(
        find.text(
            "Your account's permissions don't include a screen available in the mobile app. "
            'Your access is unchanged; an administrator can assign a role that opens a screen.'),
        findsOneWidget,
      );
      // It is not the empty-grant denial.
      expect(
        find.textContaining('does not hold any permission'),
        findsNothing,
      );
      expect(
        find.byKey(const Key('permission_access_sign_out_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('permission_access_retry_button')),
        findsNothing,
      );
    });

    testWidgets('an empty grant set keeps the empty-grant copy',
        (tester) async {
      final auth = RouterAuthProvider(
        state: PermissionLoadState.loaded,
        grants: const <String>{},
      );
      final router = AppRouter(auth);

      await tester.pumpWidget(app(auth, router));
      router.router.go('/reception/queue');
      await tester.pumpAndSettle();

      expect(router.router.state.matchedLocation, kPermissionAccessRoute);
      expect(
        find.textContaining('does not hold any permission'),
        findsOneWidget,
      );
      expect(
        find.textContaining("don't include a screen available"),
        findsNothing,
      );
    });
  });
}
