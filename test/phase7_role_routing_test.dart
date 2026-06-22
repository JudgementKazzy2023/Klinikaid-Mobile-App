import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/consent_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/onboarding_screen.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/reception_home_screen.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/department_home_screen.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/specialist_home_screen.dart';

// Mock AuthProvider subclass to allow getter overrides for tests
class MockAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  bool _mockHasConsented = false;
  bool _mockIsOnboarded = false;
  bool _mockIsLoading = false;
  Profile? _mockProfile;
  Patient? _mockPatient;
  User? _mockUser;
  String? _mockErrorMessage;

  MockAuthProvider() : super();

  void setMockIsAuthenticated(bool val) {
    _mockIsAuthenticated = val;
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

  void setMockIsLoading(bool val) {
    _mockIsLoading = val;
    notifyListeners();
  }

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  void setMockPatient(Patient? p) {
    _mockPatient = p;
    notifyListeners();
  }

  void setMockUser(User? u) {
    _mockUser = u;
    notifyListeners();
  }

  void setMockErrorMessage(String? err) {
    _mockErrorMessage = err;
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
  User? get user => _mockUser;

  @override
  String get errorMessage => _mockErrorMessage ?? '';
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
    // Initialize Supabase Service with dummy endpoint for test env
    await Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Widget createTestWidget(AuthProvider authProvider, AppRouter appRouter) {
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

  group('Phase 7: Role-Aware Routing & Guards Tests', () {
    testWidgets('Unauthenticated user is redirected to LoginScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(false);
      authProvider.setMockIsLoading(false);
      
      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Patient role (consented + onboarded) is routed to DashboardScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(true);
      authProvider.setMockIsOnboarded(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
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

      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('Patient role (not consented) is routed to ConsentScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(false);
      authProvider.setMockIsOnboarded(false);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pumpAndSettle();

      expect(find.byType(ConsentScreen), findsOneWidget);
    });

    testWidgets('Patient role (consented, not onboarded) is routed to OnboardingScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(true);
      authProvider.setMockIsOnboarded(false);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('Receptionist role bypasses consent/onboarding and is routed to ReceptionHomeScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(false);
      authProvider.setMockIsOnboarded(false);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'receptionist-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReceptionHomeScreen), findsOneWidget);
    });

    testWidgets('Department Staff role bypasses consent/onboarding and is routed to DepartmentHomeScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(false);
      authProvider.setMockIsOnboarded(false);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Laboratory Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(DepartmentHomeScreen), findsOneWidget);
      expect(find.text('LABORATORY Portal'), findsOneWidget);
    });

    testWidgets('Medical Specialist role bypasses consent/onboarding and is routed to SpecialistHomeScreen', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(false);
      authProvider.setMockIsOnboarded(false);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'specialist-uuid',
        fullName: 'Charlie Specialist',
        role: UserRole.medicalSpecialist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SpecialistHomeScreen), findsOneWidget);
    });

    testWidgets('Admin role redirects to LoginScreen due to blocking gate', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'admin-uuid',
        fullName: 'Super Admin',
        role: UserRole.admin,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Cross-role isolation: Patient cannot access staff routes', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockHasConsented(true);
      authProvider.setMockIsOnboarded(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
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

      // Attempt manual navigation to /staff/reception
      appRouter.router.go('/staff/reception');
      await tester.pumpAndSettle();

      // Enforced guard redirects patient back to /patient (DashboardScreen)
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(ReceptionHomeScreen), findsNothing);
    });

    testWidgets('Cross-role isolation: Staff cannot access patient routes', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'receptionist-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Attempt manual navigation to patient home /patient
      appRouter.router.go('/patient');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Enforced guard redirects staff back to /staff/reception
      expect(find.byType(ReceptionHomeScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('Cross-role isolation: Receptionist cannot access other staff routes', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'receptionist-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Attempt manual navigation to department staff route
      appRouter.router.go('/staff/department/laboratory');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Redirected back to /staff/reception
      expect(find.byType(ReceptionHomeScreen), findsOneWidget);
      expect(find.byType(DepartmentHomeScreen), findsNothing);
    });

    testWidgets('Cross-role isolation: Department staff cannot access other departments or roles', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockIsAuthenticated(true);
      authProvider.setMockIsLoading(false);
      authProvider.setMockProfile(Profile(
        id: 'staff-uuid',
        fullName: 'Alice Laboratory Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final appRouter = AppRouter(authProvider);

      await tester.pumpWidget(createTestWidget(authProvider, appRouter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Attempt manual navigation to imaging department
      appRouter.router.go('/staff/department/imaging');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Redirected back to /staff/department/laboratory
      expect(find.byType(DepartmentHomeScreen), findsOneWidget);
      expect(find.text('LABORATORY Portal'), findsOneWidget);
      expect(find.text('IMAGING Portal'), findsNothing);
    });
  });
}
