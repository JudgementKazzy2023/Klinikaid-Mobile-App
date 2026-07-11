import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';
import 'package:klinikaid_mobile/features/records/presentation/widgets/grouped_record_detail_modal.dart';

class MockAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  Profile? _mockProfile;

  MockAuthProvider() : super();

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
}

class MockDepartmentProvider extends DepartmentProvider {
  final List<DepartmentRecord> mockRecentRecords;
  final bool mockIsLoading;

  MockDepartmentProvider(super.department, this.mockRecentRecords, {this.mockIsLoading = false});

  @override
  bool get isLoading => mockIsLoading;

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
      await supabase.Supabase.initialize(
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const supabase.FlutterAuthClientOptions(
          localStorage: supabase.EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  Widget createTestWidget(AuthProvider authProvider, AppRouter appRouter, DepartmentProvider deptProvider) {
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

  group('Department Records Screen Tests', () {
    testWidgets('1. Lists past completed reports with correct details and search filter', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final now = DateTime.now();

      final mockRecords = [
        DepartmentRecord(
          id: 'rec-1',
          patientId: 'patient-1',
          recorderId: 'recorder-1',
          testType: 'CBC',
          department: Department.laboratory,
          testResults: {
            'test_name': 'hemoglobin',
            'test_value': '14.2',
            'unit': 'g/dL',
          },
          referenceRangeStatus: ReferenceRangeStatus.normal,
          notes: 'Routine CBC check',
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-1',
            firstName: 'John',
            lastName: 'Doe',
            dateOfBirth: DateTime(1985, 5, 5),
            gender: Gender.male,
            contactNumber: '09123456789',
            address: 'City A',
            createdAt: now,
            updatedAt: now,
          ),
          recorder: Profile(
            id: 'recorder-1',
            fullName: 'Technician Alice',
            role: UserRole.departmentStaff,
            department: Department.laboratory,
            createdAt: now,
            updatedAt: now,
          ),
        ),
        DepartmentRecord(
          id: 'rec-2',
          patientId: 'patient-2',
          recorderId: 'recorder-2',
          testType: 'Urinalysis',
          department: Department.laboratory,
          testResults: {
            'test_name': 'protein',
            'test_value': '3+',
            'unit': '',
          },
          referenceRangeStatus: ReferenceRangeStatus.flagged,
          notes: 'Proteinuria detected',
          createdAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now.subtract(const Duration(hours: 1)),
          patient: Patient(
            id: 'patient-2',
            firstName: 'Jane',
            lastName: 'Smith',
            dateOfBirth: DateTime(1990, 6, 6),
            gender: Gender.female,
            contactNumber: '09123456780',
            address: 'City B',
            createdAt: now,
            updatedAt: now,
          ),
          recorder: Profile(
            id: 'recorder-2',
            fullName: '', // empty name profile
            role: UserRole.departmentStaff,
            department: Department.laboratory,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final deptProvider = MockDepartmentProvider('laboratory', mockRecords);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      // Verify list items and detailed parameters
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('NORMAL'), findsOneWidget);
      expect(find.text('FLAGGED'), findsOneWidget);

      // Verify recorder name displaying and fallback to Unknown for empty recorder fullName
      expect(find.textContaining('Entered by Technician Alice'), findsOneWidget);
      expect(find.textContaining('Entered by Unknown'), findsOneWidget);

      // Verify search query filters list
      await tester.enterText(find.byType(TextField), 'Jane');
      await tester.pumpAndSettle();

      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('John Doe'), findsNothing);
    });

    testWidgets('2. Tapping a record card opens GroupedRecordDetailModal', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final now = DateTime.now();

      final mockRecords = [
        DepartmentRecord(
          id: 'rec-1',
          patientId: 'patient-1',
          recorderId: 'recorder-1',
          testType: 'CBC',
          department: Department.laboratory,
          testResults: {
            'test_name': 'hemoglobin',
            'test_value': '14.2',
            'unit': 'g/dL',
          },
          referenceRangeStatus: ReferenceRangeStatus.normal,
          notes: 'Routine CBC check',
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-1',
            firstName: 'John',
            lastName: 'Doe',
            dateOfBirth: DateTime(1985, 5, 5),
            gender: Gender.male,
            contactNumber: '09123456789',
            address: 'City A',
            createdAt: now,
            updatedAt: now,
          ),
          recorder: Profile(
            id: 'recorder-1',
            fullName: 'Technician Alice',
            role: UserRole.departmentStaff,
            department: Department.laboratory,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final deptProvider = MockDepartmentProvider('laboratory', mockRecords);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      // Tap on card
      await tester.tap(find.text('John Doe'));
      await tester.pumpAndSettle();

      // Verify modal is open
      expect(find.byType(GroupedRecordDetailModal), findsOneWidget);
    });

    testWidgets('3. Empty records view displays correct empty state message', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final deptProvider = MockDepartmentProvider('laboratory', []);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      expect(find.text('No historical department records found.'), findsOneWidget);
    });

    testWidgets('4. Long Impression text does not cause overflow errors on records card', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final now = DateTime.now();
      
      final longImpression = 'A very long clinical impression value that exceeds the width of standard mobile layouts '
          'by containing a large volume of descriptive text. ' * 5; // ~500 chars

      final mockRecords = [
        DepartmentRecord(
          id: 'rec-long',
          patientId: 'patient-long',
          recorderId: 'recorder-long',
          testType: 'Imaging Report',
          department: Department.imaging,
          testResults: {
            'test_name': 'Impression',
            'test_value': longImpression,
            'unit': '',
          },
          referenceRangeStatus: ReferenceRangeStatus.normal,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-long',
            firstName: 'Victor',
            lastName: 'Wembanyama',
            dateOfBirth: DateTime(2004, 1, 4),
            gender: Gender.male,
            contactNumber: '09123456789',
            address: 'San Antonio',
            createdAt: now,
            updatedAt: now,
          ),
          recorder: Profile(
            id: 'recorder-long',
            fullName: 'Dr. Jane Smith',
            role: UserRole.departmentStaff,
            department: Department.imaging,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final deptProvider = MockDepartmentProvider('imaging', mockRecords);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider));
      appRouter.router.go('/department/records');
      await tester.pumpAndSettle();

      expect(find.text('Victor Wembanyama'), findsOneWidget);
      expect(find.textContaining('A very long clinical impression'), findsOneWidget);
      
      await tester.tap(find.text('Victor Wembanyama'));
      await tester.pumpAndSettle();
      expect(find.byType(GroupedRecordDetailModal), findsOneWidget);
    });
  });
}
