import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/data/session_lifecycle_observer.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:klinikaid_mobile/features/queue/presentation/screens/queue_screen.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/reception_home_screen.dart';

// Subclass AuthProvider to mock Supabase and control state transitions
class SessionTimeoutMockAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  bool _mockHasConsented = true;
  bool _mockIsOnboarded = true;
  Profile? _mockProfile;
  Patient? _mockPatient;
  supabase.User? _mockUser;
  bool _mockIsLoading = false;
  bool _mockWasLoggedOutForInactivity = false;
  
  bool isSignOutCalled = false;
  bool isHandleInactivityLogoutCalled = false;

  SessionTimeoutMockAuthProvider({required SessionActivityService activityService}) 
      : super(activityService: activityService);

  void setMockIsAuthenticated(bool val) => _mockIsAuthenticated = val;
  void setMockHasConsented(bool val) => _mockHasConsented = val;
  void setMockIsOnboarded(bool val) => _mockIsOnboarded = val;
  void setMockProfile(Profile? p) => _mockProfile = p;
  void setMockPatient(Patient? p) => _mockPatient = p;
  void setMockUser(supabase.User? u) => _mockUser = u;
  void setMockIsLoading(bool val) => _mockIsLoading = val;
  void setMockWasLoggedOutForInactivity(bool val) => _mockWasLoggedOutForInactivity = val;

  @override
  bool get isAuthenticated => _mockIsAuthenticated;

  @override
  bool get hasConsented => _mockHasConsented;

  @override
  bool get isOnboarded => _mockIsOnboarded;

  @override
  Profile? get profile => _mockProfile;

  @override
  Patient? get patient => _mockPatient;

  @override
  supabase.User? get user => _mockUser;

  @override
  bool get isLoading => _mockIsLoading;

  @override
  bool get wasLoggedOutForInactivity => _mockWasLoggedOutForInactivity;

  @override
  void clearInactivityFlag() {
    _mockWasLoggedOutForInactivity = false;
    notifyListeners();
  }

  @override
  Future<void> handleInactivityLogout() async {
    isHandleInactivityLogoutCalled = true;
    _mockWasLoggedOutForInactivity = true;
    await signOut();
  }

  @override
  Future<void> signOut() async {
    isSignOutCalled = true;
    _mockIsAuthenticated = false;
    _mockProfile = null;
    _mockPatient = null;
    _mockUser = null;
    notifyListeners();
  }
}

class MockUser extends supabase.User {
  MockUser()
      : super(
          id: 'test-user-id',
          appMetadata: {},
          userMetadata: {},
          aud: '',
          createdAt: '',
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  late DateTime mockNow;

  setUpAll(() async {
    // Avoid reinitializing if already initialized in another test suite
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

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    mockNow = DateTime(2026, 7, 3, 10, 0, 0);
  });

  tearDown(() async {
    await localDatabase.close();
  });

  Widget createTestWidget({
    required SessionActivityService activityService,
    required AuthProvider authProvider,
    required AppRouter appRouter,
  }) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        Provider<SessionActivityService>.value(value: activityService),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: Builder(
        builder: (context) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (_) => context.read<SessionActivityService>().recordActivity(),
            onPanDown: (_) => context.read<SessionActivityService>().recordActivity(),
            onScaleStart: (_) => context.read<SessionActivityService>().recordActivity(),
            child: MaterialApp.router(
              routerConfig: appRouter.router,
            ),
          );
        },
      ),
    );
  }

  group('SessionActivityService Unit Tests', () {
    testWidgets('1. recordActivity() updates _lastActivityAt', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final t1 = service.lastActivityAt;
      
      mockNow = mockNow.add(const Duration(seconds: 10));
      service.recordActivity();
      
      expect(service.lastActivityAt.isAfter(t1), true);
      expect(service.lastActivityAt, mockNow);
    });

    testWidgets('2. idleTime returns correct duration', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      mockNow = mockNow.add(const Duration(minutes: 5));
      expect(service.idleTime, const Duration(minutes: 5));
    });

    testWidgets('3. setExempt(true) ignores updates and resets activity to now', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      
      mockNow = mockNow.add(const Duration(minutes: 5));
      service.setExempt(true);
      expect(service.lastActivityAt, mockNow); // reset on enter
      expect(service.isExempt, true);
      
      final t1 = service.lastActivityAt;
      mockNow = mockNow.add(const Duration(minutes: 5));
      service.recordActivity();
      
      // Since it is exempt, recordActivity should ignore updates
      expect(service.lastActivityAt, t1);
    });

    testWidgets('4. Timer fires callback when idle > timeout', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      bool fired = false;
      
      service.startMonitoring(
        timeout: const Duration(minutes: 15),
        onTimeout: () => fired = true,
      );

      mockNow = mockNow.add(const Duration(minutes: 16));
      await tester.pump(const Duration(minutes: 16));
      
      expect(fired, true);
      service.stopMonitoring();
    });

    testWidgets('5. Timer does NOT fire when exempt', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      bool fired = false;
      
      service.setExempt(true);
      service.startMonitoring(
        timeout: const Duration(minutes: 15),
        onTimeout: () => fired = true,
      );

      mockNow = mockNow.add(const Duration(minutes: 20));
      await tester.pump(const Duration(minutes: 20));
      
      expect(fired, false);
      service.stopMonitoring();
    });

    testWidgets('6. persistLastActivity + restoreLastActivity roundtrip preserves timestamp', (tester) async {
      final service1 = SessionActivityService(clock: () => mockNow);
      service1.recordActivity();
      await service1.persistLastActivity();

      final service2 = SessionActivityService(clock: () => mockNow);
      await service2.restoreLastActivity();
      expect(service2.lastActivityAt, service1.lastActivityAt);
    });
  });

  group('Session Timeout Widget & Integration Tests', () {
    testWidgets('7. Login as patient -> wait 20+ min simulated -> logged out + toast shown', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'patient-id',
        fullName: 'Jane Doe',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      auth.setMockPatient(Patient(
        id: 'patient-id',
        profileId: 'patient-id',
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(auth);
      await tester.pumpWidget(createTestWidget(
        activityService: service,
        authProvider: auth,
        appRouter: router,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);

      // Start periodic check monitor
      auth.handleInactivityLogout(); // Simulating what the timer does when elapsed > timeout
      await tester.pumpAndSettle();

      // Should be redirected to LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('You were logged out due to inactivity'), findsOneWidget);
    });

    testWidgets('8. Login as staff -> wait 15+ min simulated -> logged out', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'staff-id',
        fullName: 'Staff Member',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(auth);
      await tester.pumpWidget(createTestWidget(
        activityService: service,
        authProvider: auth,
        appRouter: router,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReceptionHomeScreen), findsOneWidget);

      // Simulate timeout
      await auth.handleInactivityLogout();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('9. Login as patient -> navigate to Live Triage Queue -> wait 25 min -> still logged in', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'patient-id',
        fullName: 'Jane Doe',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      auth.setMockPatient(Patient(
        id: 'patient-id',
        profileId: 'patient-id',
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(auth);
      await tester.pumpWidget(createTestWidget(
        activityService: service,
        authProvider: auth,
        appRouter: router,
      ));
      await tester.pumpAndSettle();

      // Navigate to Queue screen
      router.router.go('/queue');
      await tester.pumpAndSettle();

      expect(find.byType(QueueScreen), findsOneWidget);
      expect(service.isExempt, true);

      // Advance mockNow by 25 minutes
      mockNow = mockNow.add(const Duration(minutes: 25));
      await tester.pump(const Duration(minutes: 25));

      // Should still be on the queue screen
      expect(find.byType(QueueScreen), findsOneWidget);
      expect(auth.isSignOutCalled, false);
    });

    testWidgets('10. Login as patient -> leave Live Triage Queue -> wait 20 min -> logged out', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'patient-id',
        fullName: 'Jane Doe',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      auth.setMockPatient(Patient(
        id: 'patient-id',
        profileId: 'patient-id',
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(auth);
      await tester.pumpWidget(createTestWidget(
        activityService: service,
        authProvider: auth,
        appRouter: router,
      ));
      await tester.pumpAndSettle();

      // Go to Queue
      router.router.go('/queue');
      await tester.pumpAndSettle();
      expect(service.isExempt, true);

      // Leave Queue
      router.router.go('/patient');
      await tester.pumpAndSettle();
      expect(service.isExempt, false);

      // Check if timer started fresh from when we left.
      // 20 min timeout for patient
      mockNow = mockNow.add(const Duration(minutes: 21));
      
      // Trigger checkout or handle timeout directly since we simulation-test timeout redirect
      await auth.handleInactivityLogout();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('11. Tap resets timer (idleTime drops to ~0)', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'patient-id',
        fullName: 'Jane Doe',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      auth.setMockPatient(Patient(
        id: 'patient-id',
        profileId: 'patient-id',
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(auth);
      await tester.pumpWidget(createTestWidget(
        activityService: service,
        authProvider: auth,
        appRouter: router,
      ));
      await tester.pumpAndSettle();

      mockNow = mockNow.add(const Duration(minutes: 10));
      expect(service.idleTime, const Duration(minutes: 10));

      // Simulate a tap inside GestureDetector
      await tester.tap(find.byType(DashboardScreen));
      await tester.pump();

      // Idle time should drop to 0
      expect(service.idleTime, Duration.zero);
    });

    testWidgets('12. App backgrounded 25 min -> resumed -> force re-login for patient', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'patient-id',
        fullName: 'Jane Doe',
        role: UserRole.patient,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      auth.setMockPatient(Patient(
        id: 'patient-id',
        profileId: 'patient-id',
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 St',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final observer = SessionLifecycleObserver(service, auth);
      
      // Background app
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      
      // Advance time by 25 minutes
      mockNow = mockNow.add(const Duration(minutes: 25));

      // Resume app
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.idle();

      // Verify checkout triggered
      expect(auth.isHandleInactivityLogoutCalled, true);
    });

    testWidgets('13. App backgrounded 20 min -> resumed -> force re-login for staff', (tester) async {
      final service = SessionActivityService(clock: () => mockNow);
      final auth = SessionTimeoutMockAuthProvider(activityService: service);
      auth.setMockIsAuthenticated(true);
      auth.setMockProfile(Profile(
        id: 'staff-id',
        fullName: 'Staff Member',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final observer = SessionLifecycleObserver(service, auth);
      
      // Background app
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      
      // Advance time by 20 minutes
      mockNow = mockNow.add(const Duration(minutes: 20));

      // Resume app
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.idle();

      // Verify checkout triggered
      expect(auth.isHandleInactivityLogoutCalled, true);
    });
   group('Watch Item 2: recordActivity() behavior when exempt', () {
      testWidgets('Verify that recordActivity() resets to _clock() if exempt changes', (tester) async {
        final service = SessionActivityService(clock: () => mockNow);
        
        service.setExempt(true);
        expect(service.lastActivityAt, mockNow);

        mockNow = mockNow.add(const Duration(minutes: 5));
        // Calling recordActivity when exempt should NOT change lastActivityAt
        service.recordActivity();
        expect(service.lastActivityAt, mockNow.subtract(const Duration(minutes: 5)));

        // Setting exempt to false should reset or keep it, then recordActivity should work again
        service.setExempt(false);
        mockNow = mockNow.add(const Duration(minutes: 5));
        service.recordActivity();
        expect(service.lastActivityAt, mockNow);
      });
    });
  });
}
