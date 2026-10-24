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
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_service.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';

/// The staff module was removed together with its two routes
/// (`/staff/reception` and `/staff/specialist`). The paths are not routes any
/// more, so the router has to send every role to the home it owns instead of
/// rendering a screen that can no longer be reached.
class MockAuthProvider extends AuthProvider {
  MockAuthProvider({
    required this.mockProfile,
    this.mockPermissions = const <String>{},
  }) : super();

  final Profile mockProfile;
  final Set<String> mockPermissions;

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
}

/// The department shell would otherwise open a realtime channel, so the
/// provider is stubbed and never subscribes.
class MockDepartmentProvider extends DepartmentProvider {
  MockDepartmentProvider(super.department);

  @override
  bool get isLoading => false;

  @override
  List<DepartmentRecord> get recentRecords => const [];

  @override
  List<GroupedRecord> get groupedRecords => const [];

  @override
  Future<void> loadDashboard() async {
    // No-op
  }
}

/// The reception shell subscribes to document changes once it is built. The
/// stub keeps that subscription off the Realtime socket, so the test never
/// opens a channel or leaves a reconnect timer behind.
class SilentReceptionRepository extends ReceptionRepository {
  SilentReceptionRepository(supabase.SupabaseClient client)
      : super(client: client);

  @override
  Stream<void> documentChanges() => const Stream<void>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
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
      // A dead host with an in-process transport: the router only needs a
      // client, this test must never reach the shared backend.
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
        department:
            role == UserRole.departmentStaff ? Department.laboratory : null,
        emailVerifiedAt: role == UserRole.patient ? DateTime.now() : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

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
          ChangeNotifierProvider<DepartmentProvider>(
            create: (_) => MockDepartmentProvider('laboratory'),
          ),
        ],
        child: MaterialApp.router(routerConfig: router.router),
      ),
    );
    await tester.pump();
    return router;
  }

  group('the removed staff routes', () {
    const legacyPaths = ['/staff/reception', '/staff/specialist'];

    // Since #53 the landing screen comes from the loaded grants, not the role.
    final staffHomes = <UserRole, (Set<String>, String)>{
      UserRole.receptionist: (
        const {
          PermissionConstants.documentsManage,
          PermissionConstants.queueManage,
        },
        '/reception/queue',
      ),
      UserRole.departmentStaff: (
        const {PermissionConstants.recordsManageOwnDept},
        '/department/records',
      ),
      UserRole.medicalSpecialist: (
        const {
          PermissionConstants.specialistAnalytics,
          PermissionConstants.specialistPatients,
        },
        '/specialist/dashboard',
      ),
      UserRole.admin: (
        const {PermissionConstants.staffManage},
        '/admin/staff',
      ),
    };

    staffHomes.forEach((role, entry) {
      final (grants, home) = entry;
      testWidgets('$role lands on $home from the old staff paths',
          (tester) async {
        final auth = MockAuthProvider(
          mockProfile: profileFor(role),
          mockPermissions: grants,
        );
        final router = await pumpRouter(tester, auth);

        for (final path in legacyPaths) {
          router.router.go(path);
          await tester.pump();
          await tester.pump();

          expect(
            router.router.state.matchedLocation,
            home,
            reason: '$role must land on $home when opening $path',
          );
        }
      });
    });

    testWidgets('the old staff paths are no longer routes for a patient',
        (tester) async {
      final auth = MockAuthProvider(mockProfile: profileFor(UserRole.patient));
      final router = await pumpRouter(tester, auth);

      for (final path in legacyPaths) {
        router.router.go(path);
        await tester.pump();
        await tester.pump();

        // The path is unknown to the router now, so the router reports it as
        // a missing page instead of opening a staff screen.
        expect(find.text('Page Not Found'), findsWidgets);
        expect(
          find.textContaining('no routes for location: $path'),
          findsOneWidget,
        );
      }
    });
  });
}
