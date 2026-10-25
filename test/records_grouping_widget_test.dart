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
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';
import 'package:klinikaid_mobile/features/records/presentation/widgets/grouped_record_detail_modal.dart';

// The grouped-record card behaviour of the live records screens.
//
// The specialist timeline screen that used to own this behaviour went away
// with the unreachable staff module. The grouping itself is still live (the
// patient records screen, the department records screen and the admin records
// screen all render [GroupedRecord] cards), so it is covered here against the
// live [DepartmentRecordsScreen].

class MockAuthProvider extends AuthProvider {
  MockAuthProvider() : super();

  bool _mockIsAuthenticated = false;
  Profile? _mockProfile;

  void setMockIsAuthenticated(bool val) {
    _mockIsAuthenticated = val;
    notifyListeners();
  }

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => _mockIsAuthenticated;

  @override
  Profile? get profile => _mockProfile;

  // Staff routes require AAL2 since #49; this screen test starts past MFA.
  @override
  bool get isAal2 => true;
}

class MockDepartmentProvider extends DepartmentProvider {
  MockDepartmentProvider(super.department, this.mockRecentRecords);

  final List<DepartmentRecord> mockRecentRecords;

  @override
  bool get isLoading => false;

  @override
  List<DepartmentRecord> get recentRecords => mockRecentRecords;

  @override
  List<GroupedRecord> get groupedRecords => groupRecords(mockRecentRecords);

  @override
  Future<void> loadDashboard() async {
    // No-op
  }
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

  late LocalDatabase localDatabase;

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await localDatabase.close();
  });

  setUpAll(() async {
    try {
      // A dead host with an in-process transport: this test must never reach
      // the shared backend.
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

  Widget createTestWidget(
    AuthProvider authProvider,
    AppRouter appRouter,
    DepartmentProvider deptProvider,
  ) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<DepartmentProvider>.value(value: deptProvider),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
      ),
    );
  }

  Profile departmentStaffProfile() => Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  Patient testPatient() => Patient(
        id: 'patient-1',
        firstName: 'Victor',
        lastName: 'Wembanyama',
        dateOfBirth: DateTime(2004, 1, 4),
        gender: Gender.male,
        contactNumber: '1234567890',
        address: 'France',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  group('Grouped record cards on the live department records screen', () {
    final now = DateTime.utc(2026, 6, 23, 9, 22, 13);

    DepartmentRecord record({
      required String id,
      required Department department,
      required String testType,
      required ReferenceRangeStatus status,
      required DateTime createdAt,
      Map<String, dynamic>? testResults,
    }) {
      return DepartmentRecord(
        id: id,
        patientId: 'patient-1',
        recorderId: 'tech-123',
        department: department,
        testType: testType,
        testResults: testResults ?? {},
        referenceRangeStatus: status,
        createdAt: createdAt,
        updatedAt: createdAt,
        patient: testPatient(),
        recorder: Profile(
          id: 'tech-123',
          fullName: 'Technician Alice',
          role: UserRole.departmentStaff,
          department: Department.laboratory,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    testWidgets('1. Two same-bucket records render as ONE grouped card',
        (tester) async {
      final rec1 = record(
        id: 'rec-1',
        department: Department.imaging,
        testType: 'Leg X-ray',
        status: ReferenceRangeStatus.normal,
        createdAt: now,
        testResults: {
          'test_name': 'Findings',
          'test_value': 'Torn Achilles Tendon',
        },
      );
      final rec2 = record(
        id: 'rec-2',
        department: Department.imaging,
        testType: 'Leg X-ray',
        status: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 5)),
        testResults: {
          'test_name': 'Impression',
          'test_value': 'Weak plantar flexion',
        },
      );

      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(departmentStaffProfile());

      final appRouter = AppRouter(authProvider);
      final deptProvider =
          MockDepartmentProvider('laboratory', [rec1, rec2]);

      await tester.pumpWidget(
          createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      // Both rows share one 5-minute bucket, so the list holds a single card.
      expect(find.text('1 Reports'), findsOneWidget);
      expect(find.text('LEG X-RAY'), findsOneWidget);
      expect(find.text('Findings'), findsOneWidget);
      expect(find.text('Impression'), findsOneWidget);
    });

    testWidgets('2. Tapping the grouped card opens the modal with the stacked '
        'parameters', (tester) async {
      final rec1 = record(
        id: 'rec-1',
        department: Department.imaging,
        testType: 'Leg X-ray',
        status: ReferenceRangeStatus.normal,
        createdAt: now,
        testResults: {
          'test_name': 'Findings',
          'test_value': 'Torn Achilles Tendon',
        },
      );
      final rec2 = record(
        id: 'rec-2',
        department: Department.imaging,
        testType: 'Leg X-ray',
        status: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 5)),
        testResults: {
          'test_name': 'Impression',
          'test_value': 'Weak plantar flexion',
        },
      );

      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(departmentStaffProfile());

      final appRouter = AppRouter(authProvider);
      final deptProvider =
          MockDepartmentProvider('laboratory', [rec1, rec2]);

      await tester.pumpWidget(
          createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      await tester.tap(find.text('LEG X-RAY'));
      await tester.pumpAndSettle();

      expect(find.byType(GroupedRecordDetailModal), findsOneWidget);
      expect(find.text('Torn Achilles Tendon'), findsOneWidget);
      expect(find.text('Weak plantar flexion'), findsOneWidget);
    });

    testWidgets('3. Long clinical text wraps without overflow',
        (tester) async {
      const longValue =
          'Weak Plantar Flexion: Significant weakness in plantar flexion, with visual presentation of torn achilles tendon tissue. Severe pain on manipulation and loading. The patient was instructed to rest immediately and seek surgical consult. Surgical repair recommended.';

      final rec1 = record(
        id: 'rec-1',
        department: Department.imaging,
        testType: 'Leg X-ray',
        status: ReferenceRangeStatus.flagged,
        createdAt: now,
        testResults: {
          'test_name': 'Impression',
          'test_value': longValue,
        },
      );

      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(departmentStaffProfile());

      final appRouter = AppRouter(authProvider);
      final deptProvider = MockDepartmentProvider('laboratory', [rec1]);

      await tester.pumpWidget(
          createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.tap(find.text('LEG X-RAY'));
      await tester.pumpAndSettle();

      // The full clinical text stays readable in the detail modal.
      expect(
        find.descendant(
          of: find.byType(GroupedRecordDetailModal),
          matching:
              find.textContaining('Weak Plantar Flexion: Significant weakness'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Single-parameter records render unchanged',
        (tester) async {
      final rec1 = record(
        id: 'rec-1',
        department: Department.laboratory,
        testType: 'Hemoglobin',
        status: ReferenceRangeStatus.normal,
        createdAt: now,
        testResults: {
          'test_name': 'Hgb',
          'test_value': '14.5',
          'unit': 'g/dL',
        },
      );

      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(departmentStaffProfile());

      final appRouter = AppRouter(authProvider);
      final deptProvider = MockDepartmentProvider('laboratory', [rec1]);

      await tester.pumpWidget(
          createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      expect(find.text('1 Reports'), findsOneWidget);
      expect(find.text('HEMOGLOBIN'), findsOneWidget);
      expect(find.text('Hgb'), findsOneWidget);
      expect(find.textContaining('14.5'), findsOneWidget);
    });
  });
}
