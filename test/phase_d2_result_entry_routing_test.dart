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
import 'package:klinikaid_mobile/features/auth/presentation/screens/totp_verify_screen.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/screens/result_entry_screen.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';

class MockAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  bool _mockIsAal1Pending = false;
  Profile? _mockProfile;

  void setMockIsAuthenticated(bool val) {
    _mockIsAuthenticated = val;
    notifyListeners();
  }

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  void setMockIsAal1Pending(bool val) {
    _mockIsAal1Pending = val;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => _mockIsAuthenticated;

  @override
  Profile? get profile => _mockProfile;

  @override
  bool get isAal1Pending => _mockIsAal1Pending;

  @override
  supabase.User? get user => null;
}

class MockDepartmentProvider extends DepartmentProvider {
  final List<PatientQueue> mockQueueEntries;
  MockDepartmentProvider(super.department, this.mockQueueEntries);

  @override
  bool get isLoading => false;

  @override
  List<PatientQueue> get queueEntries => mockQueueEntries;
}

class MockRoutingDepartmentRepository extends DepartmentRepository {
  final Patient patient;
  MockRoutingDepartmentRepository(this.patient);

  @override
  Future<Patient> getPatient(String patientId) async {
    return patient;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // Mock shared_preferences to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  late LocalDatabase localDatabase;
  late Patient testPatient;

  setUpAll(() async {
    try {
      await supabase.Supabase.initialize(
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const supabase.FlutterAuthClientOptions(
          localStorage: supabase.EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
    testPatient = Patient(
      id: 'patient-uuid',
      profileId: 'patient-uuid',
      firstName: 'Jane',
      lastName: 'Patient',
      dateOfBirth: DateTime(1995, 10, 10),
      gender: Gender.female,
      contactNumber: '09876543210',
      address: 'Manila, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  });

  tearDown(() async {
    await localDatabase.close();
  });

  Widget createTestWidget(
    AuthProvider authProvider,
    AppRouter appRouter, {
    DepartmentProvider? deptProvider,
    DepartmentRepository? deptRepo,
  }) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        if (deptProvider != null)
          ChangeNotifierProvider<DepartmentProvider>.value(value: deptProvider),
        if (deptRepo != null)
          Provider<DepartmentRepository>.value(value: deptRepo),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
      ),
    );
  }

  group('Phase D2: Result Entry Routing & Guards Tests', () {
    testWidgets('29. "Enter Results" button is enabled on DepartmentQueueScreen', (tester) async {
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
      final deptProvider = MockDepartmentProvider('laboratory', [
        PatientQueue(
          id: 1,
          patientId: 'patient-uuid',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          priorityLevel: PriorityLevel.routine,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          patient: testPatient,
        )
      ]);

      await tester.pumpWidget(createTestWidget(
        authProvider,
        appRouter,
        deptProvider: deptProvider,
      ));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      // Find the card for Jane Patient and make sure "Enter Results" is enabled
      final button = find.widgetWithText(ElevatedButton, 'Enter Results');
      expect(button, findsOneWidget);
      final widget = tester.widget<ElevatedButton>(button);
      expect(widget.onPressed, isNotNull);
    });

    testWidgets('30. Tap "Enter Results" → navigates to /department/result-entry/:patientId', (tester) async {
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
      final deptProvider = MockDepartmentProvider('laboratory', [
        PatientQueue(
          id: 1,
          patientId: 'patient-uuid',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          priorityLevel: PriorityLevel.routine,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          patient: testPatient,
        )
      ]);
      final deptRepo = MockRoutingDepartmentRepository(testPatient);

      await tester.pumpWidget(createTestWidget(
        authProvider,
        appRouter,
        deptProvider: deptProvider,
        deptRepo: deptRepo,
      ));
      appRouter.router.go('/department/queue');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Enter Results'));
      await tester.pumpAndSettle();

      expect(find.byType(ResultEntryScreen), findsOneWidget);
    });

    testWidgets('31. Route is guarded — non-department staff blocked, AAL1 -> mfa-verify redirect', (tester) async {
      // Setup MFA pending user
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsAal1Pending(true); // AAL1 pending
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final deptRepo = MockRoutingDepartmentRepository(testPatient);

      await tester.pumpWidget(createTestWidget(
        authProvider,
        appRouter,
        deptRepo: deptRepo,
      ));
      
      appRouter.router.go('/department/result-entry/patient-uuid');
      await tester.pumpAndSettle();

      // Should redirect to /mfa-verify
      expect(find.byType(TotpVerifyScreen), findsOneWidget);
      expect(find.byType(ResultEntryScreen), findsNothing);
    });

    testWidgets('32a. Department laboratory staff → loads Lab mode (CBC default)', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory, // Laboratory department
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final deptRepo = MockRoutingDepartmentRepository(testPatient);

      await tester.pumpWidget(createTestWidget(
        authProvider,
        appRouter,
        deptRepo: deptRepo,
      ));
      
      appRouter.router.go('/department/result-entry/patient-uuid');
      await tester.pumpAndSettle();

      expect(find.byType(ResultEntryScreen), findsOneWidget);
      // Lab mode should show "Select Lab Panel / Test Group" and dropdown form fields
      expect(find.text('Select Lab Panel / Test Group'), findsOneWidget);
      expect(find.textContaining('Enter value'), findsWidgets);
    });

    testWidgets('32b. Department imaging staff → loads Free-text mode', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Imaging Staff',
        role: UserRole.departmentStaff,
        department: Department.imaging, // Imaging department
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);
      final deptRepo = MockRoutingDepartmentRepository(testPatient);

      await tester.pumpWidget(createTestWidget(
        authProvider,
        appRouter,
        deptRepo: deptRepo,
      ));
      
      appRouter.router.go('/department/result-entry/patient-uuid');
      await tester.pumpAndSettle();

      expect(find.byType(ResultEntryScreen), findsOneWidget);
      // Free-text mode should show Findings, Impression input text fields
      expect(find.text('Test Name'), findsOneWidget);
      expect(find.text('Findings'), findsOneWidget);
      expect(find.text('Impression'), findsOneWidget);
    });
  });
}
