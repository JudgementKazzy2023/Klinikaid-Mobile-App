import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:go_router/go_router.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_detail.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/domain/recent_triage_entry.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_dashboard_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_queue_screen.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_dashboard_screen.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/document_validation_screen.dart';
import 'package:klinikaid_mobile/features/reception/presentation/reception_shell.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/profile_screen.dart';

// ─── Journey Mock Repository ────────────────────────────────────────────────

class MockReceptionJourneyRepository extends ReceptionRepository {
  final List<Submission> mockSubmissions = [];
  final Map<String, SubmissionDetail> mockDetails = {};

  int mockActiveQueue = 5;
  int mockRoutedToday = 10;

  MockReceptionJourneyRepository() {
    // Document 1: Linked patient, pending
    final doc1 = makeDetail(
      id: 'doc-1',
      patientId: 'patient-1',
      patientName: 'Alice Smith',
      status: SubmissionStatus.submitted,
    );
    mockSubmissions.add(doc1.submission);
    mockDetails['doc-1'] = doc1;

    // Document 2: Unlinked patient, pending
    final doc2 = makeDetail(
      id: 'doc-2',
      patientId: null,
      patientName: 'Unknown Patient',
      status: SubmissionStatus.submitted,
    );
    mockSubmissions.add(doc2.submission);
    mockDetails['doc-2'] = doc2;
  }

  SubmissionDetail makeDetail({
    required String id,
    required String? patientId,
    required String patientName,
    required SubmissionStatus status,
  }) {
    return SubmissionDetail(
      submission: Submission(
        id: id,
        patientId: patientId,
        patientName: patientName,
        fileName: '$id.pdf',
        fileType: 'pdf',
        uploadedAt: DateTime.now().subtract(const Duration(hours: 1)),
        uploadedBy: 'uploader-id',
        status: status,
      ),
      ocrText: 'Mock OCR content for $id',
      storagePath: 'documents/$id.pdf',
      patientDob: '1995-05-15',
      patientGender: 'female',
      patientContact: '09171234567',
      patientEmail: 'patient@example.com',
      patientAddress: 'Manila, Philippines',
    );
  }

  @override
  Future<List<Submission>> getSubmissions({SubmissionStatus? status}) async {
    if (status == null) return mockSubmissions;
    return mockSubmissions.where((s) => s.status == status).toList();
  }

  @override
  Future<SubmissionDetail> getSubmissionDetail(String id) async {
    if (mockDetails.containsKey(id)) {
      return mockDetails[id]!;
    }
    throw Exception('Submission detail not found');
  }

  @override
  Future<String> getOriginalDocumentUrl(String id) async {
    return 'https://example.com/documents/$id.pdf';
  }

  @override
  Future<int> countActiveQueue() async => mockActiveQueue;

  @override
  Future<int> countPendingSubmissions() async {
    return mockSubmissions.where((s) => s.status == SubmissionStatus.submitted).length;
  }

  @override
  Future<int> countRoutedToday() async => mockRoutedToday;

  @override
  Future<List<RecentTriageEntry>> getRecentTriage({int limit = 5}) async {
    // Generate recent triage based on mockRoutedToday
    return [
      RecentTriageEntry(
        patientName: 'Recent Patient 1',
        department: 'laboratory',
        status: QueueStatus.waiting,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ];
  }

  @override
  Future<void> approveAndRoute({
    required String documentId,
    required String patientId,
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) async {
    // Update document status
    final idx = mockSubmissions.indexWhere((s) => s.id == documentId);
    if (idx != -1) {
      final old = mockSubmissions[idx];
      mockSubmissions[idx] = Submission(
        id: old.id,
        patientId: old.patientId,
        patientName: old.patientName,
        fileName: old.fileName,
        fileType: old.fileType,
        uploadedAt: old.uploadedAt,
        uploadedBy: old.uploadedBy,
        status: SubmissionStatus.approved,
      );
      mockDetails[documentId] = makeDetail(
        id: old.id,
        patientId: old.patientId,
        patientName: old.patientName,
        status: SubmissionStatus.approved,
      );
    }
    mockActiveQueue += 1;
    mockRoutedToday += 1;
  }

  @override
  Future<void> rejectDocument({
    required String documentId,
    required String reason,
  }) async {
    final idx = mockSubmissions.indexWhere((s) => s.id == documentId);
    if (idx != -1) {
      final old = mockSubmissions[idx];
      mockSubmissions[idx] = Submission(
        id: old.id,
        patientId: old.patientId,
        patientName: old.patientName,
        fileName: old.fileName,
        fileType: old.fileType,
        uploadedAt: old.uploadedAt,
        uploadedBy: old.uploadedBy,
        status: SubmissionStatus.rejected,
      );
      mockDetails[documentId] = makeDetail(
        id: old.id,
        patientId: old.patientId,
        patientName: old.patientName,
        status: SubmissionStatus.rejected,
      );
    }
  }
}

// ─── Journey Mock AuthProvider ──────────────────────────────────────────────

class MockJourneyAuthProvider extends AuthProvider {
  bool _mockIsAuthenticated = false;
  Profile? _mockProfile;

  MockJourneyAuthProvider() : super();

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

  testWidgets('Phase R5: Receptionist Workstation End-to-End Capstone Journey', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 1. Setup Auth and Repository
    final authProvider = MockJourneyAuthProvider();
    authProvider.setMockIsAuthenticated(true);
    authProvider.setMockProfile(Profile(
      id: 'receptionist-id',
      fullName: 'Bob Receptionist',
      role: UserRole.receptionist,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    final repo = MockReceptionJourneyRepository();
    final appRouter = AppRouter(authProvider);

    // Build App with routing config pointing to receptionist path shell
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          Provider<ReceptionRepository>.value(value: repo),
          ChangeNotifierProvider<ReceptionQueueProvider>(
            create: (context) => ReceptionQueueProvider(repository: repo)..loadSubmissions(),
          ),
          ChangeNotifierProvider<ReceptionDashboardProvider>(
            create: (context) => ReceptionDashboardProvider(repository: repo)..loadDashboard(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: appRouter.router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verification 1: Routed initially to Dashboard or Queue (Bob is receptionist)
    // Go directly to receptionist dashboard
    appRouter.router.go('/reception/dashboard');
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionDashboardScreen), findsOneWidget);

    // Verify initial dashboard stats
    expect(find.text('5'), findsOneWidget); // Active Queue
    expect(find.text('2'), findsOneWidget); // Pending Submissions (doc-1 and doc-2 are submitted)
    expect(find.text('10'), findsOneWidget); // Total Routed Today

    // 2. Navigate to Queue
    appRouter.router.go('/reception/queue');
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionQueueScreen), findsOneWidget);

    // Verify pending tab cards
    expect(find.text('Alice Smith'), findsOneWidget);
    expect(find.text('Unknown Patient'), findsOneWidget);

    // 3. Open doc-1 (Alice Smith - linked patient)
    appRouter.router.go('/reception/document/doc-1');
    await tester.pumpAndSettle();
    expect(find.byType(DocumentValidationScreen), findsOneWidget);
    expect(find.text('Alice Smith'), findsWidgets);

    // Approve & Route button is enabled (since pending + patientId is not null)
    final routeBtnFinder = find.widgetWithText(ElevatedButton, 'Approve & Route Patient');
    expect(tester.widget<ElevatedButton>(routeBtnFinder).onPressed, isNotNull);

    // Tap Approve & Route to open sheet
    await tester.tap(routeBtnFinder);
    await tester.pumpAndSettle();
    expect(find.text('Triage & Department Routing'), findsOneWidget);

    // Select Department (Laboratory)
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laboratory').last);
    await tester.pumpAndSettle();

    // Confirm Routing
    final confirmRouteBtn = find.widgetWithText(ElevatedButton, 'Confirm Routing');
    await tester.tap(confirmRouteBtn);
    await tester.pumpAndSettle(); // Complete route write operations

    // Redirected back to queue screen, Pending count decremented, Approved incremented
    expect(find.byType(ReceptionQueueScreen), findsOneWidget);
    
    // 4. Open doc-2 (Unknown Patient - unlinked patient)
    appRouter.router.go('/reception/document/doc-2');
    await tester.pumpAndSettle();
    expect(find.byType(DocumentValidationScreen), findsOneWidget);
    expect(find.text('Unknown Patient'), findsWidgets);

    // Verify Approve button is disabled ("Cannot route — patient not linked" hint is shown)
    final routeBtn2 = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Approve & Route Patient'));
    expect(routeBtn2.onPressed, isNull);
    expect(find.text('Cannot route — patient not linked'), findsOneWidget);

    // Tap Reject Document (Reject button is enabled since pending, even if patientId is null)
    final rejectBtn = find.widgetWithText(OutlinedButton, 'Reject Document');
    expect(tester.widget<OutlinedButton>(rejectBtn).onPressed, isNotNull);

    await tester.tap(rejectBtn);
    await tester.pumpAndSettle();
    expect(find.text('Reject Document Submission?'), findsOneWidget);

    // Tap 'Illegible text' preset chip to fill explanation textbox
    await tester.tap(find.widgetWithText(ActionChip, 'Illegible text'));
    await tester.pumpAndSettle();

    // Confirm Rejection (enabled because template text length >= 20 chars)
    final confirmRejectBtn = find.widgetWithText(ElevatedButton, 'Confirm Rejection');
    expect(tester.widget<ElevatedButton>(confirmRejectBtn).onPressed, isNotNull);

    await tester.tap(confirmRejectBtn);
    await tester.pumpAndSettle(); // Complete reject write

    // Redirected back to queue screen
    expect(find.byType(ReceptionQueueScreen), findsOneWidget);

    // 5. Navigate back to dashboard, refresh to see changes
    appRouter.router.go('/reception/dashboard');
    await tester.pumpAndSettle();

    final dashboardProvider = Provider.of<ReceptionDashboardProvider>(tester.element(find.byType(ReceptionDashboardScreen)), listen: false);
    await dashboardProvider.loadDashboard();
    await tester.pumpAndSettle();

    // Verify stats updated (Active Queue 5->6, Routed Today 10->11, Pending 2->0)
    expect(find.text('6'), findsOneWidget); // Active Queue
    expect(find.text('0'), findsOneWidget); // Pending Submissions
    expect(find.text('11'), findsOneWidget); // Total Routed Today

    // 6. Regression Verify: Non-receptionist role (patient) cannot reach dashboard
    final patientAuth = MockJourneyAuthProvider();
    patientAuth.setMockIsAuthenticated(true);
    patientAuth.setMockProfile(Profile(
      id: 'patient-id',
      fullName: 'Jane Patient',
      role: UserRole.patient,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    final patientRouter = AppRouter(patientAuth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: patientAuth),
        ],
        child: MaterialApp.router(
          routerConfig: patientRouter.router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Attempt to navigate to reception dashboard
    patientRouter.router.go('/reception/dashboard');
    await tester.pumpAndSettle();

    // Dashboard screen is blocked
    expect(find.byType(ReceptionDashboardScreen), findsNothing);
  });
}
