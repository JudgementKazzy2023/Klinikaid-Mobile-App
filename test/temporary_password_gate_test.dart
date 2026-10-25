import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_service.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/domain/temporary_password.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';

/// A receptionist-created account holds `app_metadata.must_change_password`
/// until the patient replaces the password on web (#17). Mobile cannot clear
/// the flag, so it must not open any screen for such an account.
class MockAuthProvider extends AuthProvider {
  MockAuthProvider({
    required this.mockProfile,
    required this.mockMustChange,
    this.mockPermissions = const <String>{},
  }) : super();

  final Profile mockProfile;
  final bool mockMustChange;
  final Set<String> mockPermissions;
  int signOutCalls = 0;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  bool get hasConsented => true;

  @override
  bool get isAal1Pending => false;

  @override
  bool get isAal2 => true;

  @override
  Profile? get profile => mockProfile;

  @override
  bool get mustChangePassword => mockMustChange;

  @override
  Set<String> get permissions => mockPermissions;

  @override
  bool hasPermission(String permission) => mockPermissions.contains(permission);

  @override
  bool hasAllPermissions(List<String> permissions) =>
      permissions.every(mockPermissions.contains);

  @override
  bool hasAnyPermission(List<String> permissions) =>
      permissions.any(mockPermissions.contains);

  @override
  PermissionLoadState get permissionLoadState => PermissionLoadState.loaded;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

class SilentReceptionRepository extends ReceptionRepository {
  SilentReceptionRepository(supabase.SupabaseClient client)
      : super(client: client);

  @override
  Stream<void> documentChanges() => const Stream<void>.empty();
}

supabase.User userWith(Map<String, dynamic> appMetadata) => supabase.User(
      id: 'user-1',
      appMetadata: appMetadata,
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-10-25T00:00:00Z',
    );

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
      await supabase.Supabase.initialize(
        url: 'https://example.invalid',
        anonKey: 'test-anon-key',
        httpClient: MockClient((request) async => http.Response(
              '[]',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            )),
        authOptions: const supabase.FlutterAuthClientOptions(
          localStorage: supabase.EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  group('mustChangePassword matches web', () {
    test('only a literal true flags the account', () {
      expect(mustChangePassword(userWith({kMustChangePasswordKey: true})), isTrue);
      expect(mustChangePassword(userWith({kMustChangePasswordKey: 'true'})), isFalse);
      expect(mustChangePassword(userWith({kMustChangePasswordKey: false})), isFalse);
      expect(mustChangePassword(userWith({kMustChangePasswordKey: null})), isFalse);
      expect(mustChangePassword(userWith(const {})), isFalse);
      expect(mustChangePassword(null), isFalse);
    });
  });

  group('temporary password gate', () {
    late LocalDatabase localDatabase;

    setUp(() {
      localDatabase = LocalDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await localDatabase.close();
    });

    Profile profileFor(UserRole role) => Profile(
          id: '${role.name}-uuid',
          fullName: 'Test ${role.displayName}',
          role: role,
          emailVerifiedAt: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    const receptionGrants = {
      PermissionConstants.documentsManage,
      PermissionConstants.queueManage,
    };

    Future<AppRouter> pumpRouter(WidgetTester tester, MockAuthProvider auth) async {
      final router = AppRouter(auth);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LocalDatabase>.value(value: localDatabase),
            Provider<ReceptionRepository>.value(
              value: SilentReceptionRepository(supabase.Supabase.instance.client),
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: MaterialApp.router(routerConfig: router.router),
        ),
      );
      await tester.pump();
      return router;
    }

    Future<void> go(WidgetTester tester, AppRouter router, String path) async {
      router.router.go(path);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a flagged patient reaches no patient screen', (tester) async {
      final auth = MockAuthProvider(
        mockProfile: profileFor(UserRole.patient),
        mockMustChange: true,
      );
      final router = await pumpRouter(tester, auth);

      for (final path in ['/', '/patient', '/records', '/consent', '/verify']) {
        await go(tester, router, path);
        expect(router.router.state.matchedLocation, kTemporaryPasswordRoute,
            reason: 'opening $path');
      }
      expect(find.byKey(const Key('temporary_password_message')), findsOneWidget);
    });

    testWidgets('a flagged staff account reaches no staff screen', (tester) async {
      final auth = MockAuthProvider(
        mockProfile: profileFor(UserRole.receptionist),
        mockMustChange: true,
        mockPermissions: receptionGrants,
      );
      final router = await pumpRouter(tester, auth);

      await go(tester, router, '/reception/queue');
      expect(router.router.state.matchedLocation, kTemporaryPasswordRoute);
    });

    testWidgets('an account without the flag is sent home from the gate', (tester) async {
      final auth = MockAuthProvider(
        mockProfile: profileFor(UserRole.receptionist),
        mockMustChange: false,
        mockPermissions: receptionGrants,
      );
      final router = await pumpRouter(tester, auth);

      await go(tester, router, kTemporaryPasswordRoute);
      expect(router.router.state.matchedLocation, '/reception/queue');
    });

    testWidgets('sign out on the gate signs the account out', (tester) async {
      final auth = MockAuthProvider(
        mockProfile: profileFor(UserRole.patient),
        mockMustChange: true,
      );
      final router = await pumpRouter(tester, auth);
      await go(tester, router, '/patient');

      await tester.tap(find.byKey(const Key('temporary_password_sign_out_button')));
      await tester.pump();

      expect(auth.signOutCalls, 1);
    });
  });
}
