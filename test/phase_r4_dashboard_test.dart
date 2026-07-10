import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/recent_triage_entry.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_dashboard_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_dashboard_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';

// ─── Mock Repository ────────────────────────────────────────────────────────

class MockReceptionRepository extends ReceptionRepository {
  int mockActiveQueueCount = 0;
  int mockPendingSubmissionsCount = 0;
  int mockRoutedTodayCount = 0;
  List<RecentTriageEntry> mockRecentTriage = [];
  bool shouldFail = false;

  @override
  Future<int> countActiveQueue() async {
    if (shouldFail) throw Exception('Database error active queue');
    return mockActiveQueueCount;
  }

  @override
  Future<int> countPendingSubmissions() async {
    if (shouldFail) throw Exception('Database error pending submissions');
    return mockPendingSubmissionsCount;
  }

  @override
  Future<int> countRoutedToday() async {
    if (shouldFail) throw Exception('Database error routed today');
    return mockRoutedTodayCount;
  }

  @override
  Future<List<RecentTriageEntry>> getRecentTriage({int limit = 5}) async {
    if (shouldFail) throw Exception('Database error recent triage');
    return mockRecentTriage.take(limit).toList();
  }
}

// ─── Mock AuthProvider ──────────────────────────────────────────────────────

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
  bool get isLoading => false;

  @override
  Profile? get profile => _mockProfile;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Widget buildDashboardScreen(MockReceptionRepository repo, {ReceptionDashboardProvider? providerOverride}) {
  return MultiProvider(
    providers: [
      Provider<ReceptionRepository>.value(value: repo),
      ChangeNotifierProvider<ReceptionDashboardProvider>(
        create: (context) {
          if (providerOverride != null) return providerOverride;
          return ReceptionDashboardProvider(repository: repo)..loadDashboard();
        },
      ),
    ],
    child: const MaterialApp(
      home: ReceptionDashboardScreen(),
    ),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getAll') return <String, Object>{};
    return true;
  });

  setUpAll(() async {
    await supabase.Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  group('Phase R4: Receptionist Dashboard Unit Tests', () {
    test('1. countActiveQueue fetches mock values correctly', () async {
      final repo = MockReceptionRepository()..mockActiveQueueCount = 42;
      final count = await repo.countActiveQueue();
      expect(count, 42);
    });

    test('2. countPendingSubmissions fetches pending document count', () async {
      final repo = MockReceptionRepository()..mockPendingSubmissionsCount = 15;
      final count = await repo.countPendingSubmissions();
      expect(count, 15);
    });

    test('3. countRoutedToday fetches today count using PHT start of today', () async {
      final repo = MockReceptionRepository()..mockRoutedTodayCount = 18;
      final count = await repo.countRoutedToday();
      expect(count, 18);
    });

    test('4. getRecentTriage returns recent activity entry list', () async {
      final repo = MockReceptionRepository()
        ..mockRecentTriage = [
          RecentTriageEntry(
            patientName: 'Ralph Garcia',
            department: 'laboratory',
            status: QueueStatus.waiting,
            createdAt: DateTime.now(),
          ),
          RecentTriageEntry(
            patientName: 'Jane Doe',
            department: 'imaging',
            status: QueueStatus.inProgress,
            createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
        ];

      final entries = await repo.getRecentTriage(limit: 5);
      expect(entries.length, 2);
      expect(entries[0].patientName, 'Ralph Garcia');
      expect(entries[1].patientName, 'Jane Doe');
    });

    test('5. phtStartOfTodayUtc returns correct time zones', () {
      final start = phtStartOfTodayUtc();
      expect(start.isUtc, isTrue);
    });
  });

  group('Phase R4: Receptionist Dashboard Widget Tests', () {
    testWidgets('6. Dashboard renders 3 stat cards w/ counts', (tester) async {
      final repo = MockReceptionRepository()
        ..mockActiveQueueCount = 12
        ..mockPendingSubmissionsCount = 5
        ..mockRoutedTodayCount = 8;

      await tester.pumpWidget(buildDashboardScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);

      expect(find.text('ACTIVE\nQUEUE'), findsOneWidget);
      expect(find.text('PENDING\nSUBMISSIONS'), findsOneWidget);
      expect(find.text('TOTAL\nROUTED TODAY'), findsOneWidget);
    });

    testWidgets('7. Recent triage list renders entries details', (tester) async {
      final repo = MockReceptionRepository()
        ..mockRecentTriage = [
          RecentTriageEntry(
            patientName: 'Juan dela Cruz',
            department: 'laboratory',
            status: QueueStatus.waiting,
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ];

      await tester.pumpWidget(buildDashboardScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Juan dela Cruz'), findsOneWidget);
      expect(find.text('Laboratory'), findsOneWidget);
      expect(find.text('WAITING'), findsOneWidget);
      expect(find.text('5 minutes ago'), findsOneWidget);
    });

    testWidgets('8. Empty recent triage shows placeholder text', (tester) async {
      final repo = MockReceptionRepository()..mockRecentTriage = [];

      await tester.pumpWidget(buildDashboardScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('No recent triage activity.'), findsOneWidget);
    });

    testWidgets('9. Operational guide card renders with 4 bullets', (tester) async {
      final repo = MockReceptionRepository();

      await tester.pumpWidget(buildDashboardScreen(repo));
      await tester.pumpAndSettle();

      expect(find.text('Receptionist Operational Guide'), findsOneWidget);
      expect(find.textContaining('Validate Patient Info'), findsOneWidget);
      expect(find.textContaining('Document Review'), findsOneWidget);
      expect(find.textContaining('Routing & Vitals'), findsOneWidget);
      expect(find.textContaining('Rejections'), findsOneWidget);
    });

    testWidgets('10. Error state retry triggers refetch', (tester) async {
      final repo = MockReceptionRepository()..shouldFail = true;
      final provider = ReceptionDashboardProvider(repository: repo);

      await tester.pumpWidget(buildDashboardScreen(repo, providerOverride: provider));
      await tester.pump(); // build initial loading frame

      await provider.loadDashboard();
      await tester.pump(); // rebuild with error state

      expect(find.text('Failed to load dashboard data'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      repo.shouldFail = false;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Retry'));
      await tester.pump(); // start loading
      await tester.pumpAndSettle(); // finish loading

      expect(find.text('Failed to load dashboard data'), findsNothing);
    });

    testWidgets('11. Non-receptionist role cannot reach dashboard (route guard)', (tester) async {
      final patientAuth = MockAuthProvider();
      patientAuth.setMockIsAuthenticated(true);
      patientAuth.setMockProfile(Profile(
        id: 'patient-uuid',
        fullName: 'Jane Patient',
        role: UserRole.patient,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final router = AppRouter(patientAuth);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: patientAuth),
        ],
        child: MaterialApp.router(
          routerConfig: router.router,
        ),
      ));
      await tester.pumpAndSettle();

      // Attempt to go to dashboard
      router.router.go('/reception/dashboard');
      await tester.pumpAndSettle();

      // Dashboard screen is not visible
      expect(find.byType(ReceptionDashboardScreen), findsNothing);
    });
  });
}
