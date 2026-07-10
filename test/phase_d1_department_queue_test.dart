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
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/totp_verify_screen.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/screens/department_queue_screen.dart';

class MockAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  bool _mockHasConsented = false;
  bool _mockIsOnboarded = false;
  bool _mockIsLoading = false;
  Profile? _mockProfile;
  Patient? _mockPatient;
  supabase.User? _mockUser;
  bool _mockIsAal1Pending = false;
  bool isSignOutCalled = false;

  MockAuthProvider() : super();

  void setMockIsAuthenticated(bool val) {
    _mockIsAuthenticated = val;
    notifyListeners();
  }

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  void setMockHasConsented(bool val) {
    _mockHasConsented = val;
    notifyListeners();
  }

  void setMockIsOnboarded(bool val) {
    _mockIsOnboarded = val;
    notifyListeners();
  }

  void setMockPatient(Patient? p) {
    _mockPatient = p;
    notifyListeners();
  }

  void setMockIsAal1Pending(bool val) {
    _mockIsAal1Pending = val;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => _mockIsAuthenticated;

  @override
  bool get hasConsented => _mockHasConsented;

  @override
  bool get isOnboarded => _mockIsOnboarded;

  @override
  bool get isLoading => _mockIsLoading;

  @override
  Profile? get profile => _mockProfile;

  @override
  Patient? get patient => _mockPatient;

  @override
  supabase.User? get user => _mockUser;

  @override
  bool get isAal1Pending => _mockIsAal1Pending;

  @override
  Future<void> signOut() async {
    isSignOutCalled = true;
    _mockIsAuthenticated = false;
    _mockProfile = null;
    notifyListeners();
  }
}

class MockDepartmentProvider extends DepartmentProvider {
  final List<PatientQueue> mockQueueEntries;
  final bool mockIsLoading;

  MockDepartmentProvider(super.department, this.mockQueueEntries, {this.mockIsLoading = false});

  @override
  bool get isLoading => mockIsLoading;

  @override
  List<PatientQueue> get queueEntries => mockQueueEntries;

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

  Widget createTestWidget(AuthProvider authProvider, AppRouter appRouter, {DepartmentProvider? deptProvider}) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        if (deptProvider != null)
          ChangeNotifierProvider<DepartmentProvider>.value(value: deptProvider),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
      ),
    );
  }

  group('Department Queue Screen Routing & Guards Tests', () {
    testWidgets('1. Authorized lab staff login → lands on `/department/queue`', (tester) async {
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

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider: deptProvider));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.byType(DepartmentQueueScreen), findsOneWidget);
      expect(find.text('Laboratory Queue'), findsOneWidget);
    });

    testWidgets('2. AAL1 session (MFA pending) → redirected to `/mfa-verify` challenge', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsAal1Pending(true);
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

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider: deptProvider));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.byType(TotpVerifyScreen), findsOneWidget);
      expect(find.byType(DepartmentQueueScreen), findsNothing);
    });

    testWidgets('3. DepartmentUnassignedException (department is null) → redirects to login & logs out', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Unassigned Staff',
        role: UserRole.departmentStaff,
        department: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(authProvider.isSignOutCalled, isTrue);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('4. Patient role cannot reach department queue (route guard)', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(true);
      authProvider.setMockIsOnboarded(true);
      authProvider.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      authProvider.setMockPatient(Patient(
        id: 'patient-uuid',
        profileId: 'patient-uuid',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@patient.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pumpAndSettle();

      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(DepartmentQueueScreen), findsNothing);
    });
  });

  group('Department Queue Screen Display & Filters Tests', () {
    testWidgets('5. Queue card renders patient info and defensive triage/vitals summary', (tester) async {
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

      final mockQueueEntries = [
        PatientQueue(
          id: 1,
          patientId: 'patient-uuid-1',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          triageNotes: '{"queue_number":"LAB-001","vitals":{"blood_pressure":"120/80","weight_kg":72.5,"temperature_c":36.7},"notes":"Routine lab test request"}',
          priorityLevel: PriorityLevel.routine,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-uuid-1',
            firstName: 'John',
            lastName: 'Doe',
            dateOfBirth: DateTime(1985, 5, 5),
            gender: Gender.male,
            contactNumber: '09123456789',
            address: 'City A',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final deptProvider = MockDepartmentProvider('laboratory', mockQueueEntries);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider: deptProvider));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('LAB-001'), findsOneWidget);
      expect(find.text('BP: 120/80 | Wt: 72.5kg | Temp: 36.7°C'), findsOneWidget);
      expect(find.text('Triage Note: Routine lab test request'), findsOneWidget);
      
      // Verify Enter Results button is disabled
      final buttonFinder = find.widgetWithText(TextButton, 'Enter Results (Coming soon)');
      expect(buttonFinder, findsOneWidget);
      final textButton = tester.widget<TextButton>(buttonFinder);
      expect(textButton.onPressed, isNull);
    });

    testWidgets('6. Empty queue shows correct placeholder text', (tester) async {
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

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider: deptProvider));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.text("No patients queued. Today's queue is empty."), findsOneWidget);
    });

    testWidgets('7. Search filters queue entries by patient name client-side', (tester) async {
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

      final mockQueueEntries = [
        PatientQueue(
          id: 1,
          patientId: 'p1',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          triageNotes: '{"queue_number":"LAB-001"}',
          priorityLevel: PriorityLevel.routine,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'p1',
            firstName: 'John',
            lastName: 'Doe',
            dateOfBirth: DateTime(1985, 5, 5),
            gender: Gender.male,
            contactNumber: '09123456789',
            address: 'City A',
            createdAt: now,
            updatedAt: now,
          ),
        ),
        PatientQueue(
          id: 2,
          patientId: 'p2',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          triageNotes: '{"queue_number":"LAB-002"}',
          priorityLevel: PriorityLevel.routine,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'p2',
            firstName: 'Alice',
            lastName: 'Smith',
            dateOfBirth: DateTime(1990, 6, 6),
            gender: Gender.female,
            contactNumber: '09123456780',
            address: 'City B',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final deptProvider = MockDepartmentProvider('laboratory', mockQueueEntries);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter, deptProvider: deptProvider));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Alice Smith'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'John');
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Alice Smith'), findsNothing);
    });
  });
}
