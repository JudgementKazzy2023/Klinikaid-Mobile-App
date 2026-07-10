import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_detail.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/document_validation_screen.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_queue_screen.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class MockAuthProvider extends AuthProvider {
  Profile? _mockProfile;

  MockAuthProvider() : super();

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  Profile? get profile => _mockProfile;
}

class MockReceptionRepository extends ReceptionRepository {
  final SubmissionDetail mockDetail;
  final String mockUrl;

  MockReceptionRepository({
    required this.mockDetail,
    this.mockUrl = 'https://dummy.signed.url/pdf',
  });

  @override
  Future<SubmissionDetail> getSubmissionDetail(String id) async {
    return mockDetail;
  }

  @override
  Future<String> getOriginalDocumentUrl(String id) async {
    return mockUrl;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const sharedPreferencesChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sharedPreferencesChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  // Mock url_launcher MethodChannel
  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  bool urlLaunched = false;
  String? launchedUrlString;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(urlChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'canLaunch') {
      return true;
    }
    if (methodCall.method == 'launch') {
      urlLaunched = true;
      launchedUrlString = (methodCall.arguments as Map)['url'] as String?;
      return true;
    }
    return null;
  });

  setUpAll(() async {
    await supabase.Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  Widget createTestWidget({
    required AuthProvider authProvider,
    required ReceptionRepository repository,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        Provider<ReceptionRepository>.value(value: repository),
        ChangeNotifierProvider<ReceptionQueueProvider>(
          create: (context) => ReceptionQueueProvider(repository: repository),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: DocumentValidationScreen(submissionId: 'sub-id-123'),
        ),
      ),
    );
  }


  group('Phase R1: Document Validation Screen Widget Tests', () {
    late MockAuthProvider authProvider;
    late Submission mockSub;
    late SubmissionDetail mockDetail;

    setUp(() {
      urlLaunched = false;
      launchedUrlString = null;

      authProvider = MockAuthProvider();
      authProvider.setMockProfile(Profile(
        id: 'receptionist-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      mockSub = Submission(
        id: 'sub-id-123',
        patientName: 'Jane Doe',
        fileName: 'referral_jane.pdf',
        fileType: 'pdf',
        uploadedAt: DateTime.now(),
        uploadedBy: 'Jane Doe',
        status: SubmissionStatus.submitted,
      );

      mockDetail = SubmissionDetail(
        submission: mockSub,
        ocrText: 'This is the raw OCR text of the referral document.',
        storagePath: 'uploads/referral_jane.pdf',
        patientDob: '1990-05-15',
        patientGender: 'female',
        patientContact: '09123456789',
        patientEmail: 'jane.doe@email.com',
        patientAddress: 'Rizal, Philippines',
      );
    });

    testWidgets('Renders all patient detail fields and metadata correctly', (tester) async {
      final repo = MockReceptionRepository(mockDetail: mockDetail);
      await tester.pumpWidget(createTestWidget(authProvider: authProvider, repository: repo));
      await tester.pumpAndSettle();

      // 10. Patient details card renders all fields
      expect(find.text('Jane Doe'), findsWidgets);
      expect(find.text('1990-05-15'), findsOneWidget);
      expect(find.text('female'), findsOneWidget);
      expect(find.text('09123456789'), findsOneWidget);
      expect(find.text('jane.doe@email.com'), findsOneWidget);
      expect(find.text('Rizal, Philippines'), findsOneWidget);

      // 12. OCR text card shows extracted text
      expect(find.text('This is the raw OCR text of the referral document.'), findsOneWidget);
      expect(find.text('MONOSPACE RAW'), findsOneWidget);

      // 14. AI Validation Report card -> always shows "No OCR Score"
      expect(find.text('No OCR Score'), findsOneWidget);
      
      // 15. AI card shows "Confidence score not available for this upload."
      expect(find.text('Confidence score not available for this upload.'), findsOneWidget);

      // 16. Metadata card shows file name, type, uploaded at/by
      expect(find.text('referral_jane.pdf'), findsWidgets);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Jane Doe'), findsWidgets); // uploader and name

      // 17. Reject + Approve buttons DISABLED this phase
      final rejectBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Reject Document'));
      final approveBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Approve & Route Patient'));
      expect(rejectBtn.onPressed, isNull);
      expect(approveBtn.onPressed, isNull);

      // Tooltip/label "Cannot route — patient not linked" is visible because patientId is null
      expect(find.text('Cannot route — patient not linked'), findsOneWidget);
    });

    testWidgets('Handles unknown patient and empty OCR text gracefully', (tester) async {
      final unknownSub = Submission(
        id: 'sub-id-123',
        patientName: 'Unknown Patient',
        fileName: 'referral_jane.pdf',
        fileType: 'pdf',
        uploadedAt: DateTime.now(),
        uploadedBy: 'Jane Doe',
        status: SubmissionStatus.submitted,
      );

      final unknownDetail = SubmissionDetail(
        submission: unknownSub,
        ocrText: '',
        storagePath: 'uploads/referral_jane.pdf',
        patientDob: '—',
        patientGender: '—',
        patientContact: '—',
        patientEmail: '—',
        patientAddress: '—',
      );

      final repo = MockReceptionRepository(mockDetail: unknownDetail);
      await tester.pumpWidget(createTestWidget(authProvider: authProvider, repository: repo));
      await tester.pumpAndSettle();

      // 11. Unknown patient -> shows "Unknown Patient" + "—" fields
      expect(find.text('Unknown Patient'), findsWidgets);
      expect(find.text('—'), findsWidgets); // Displays dashes for dob, gender, contact, etc.

      // 13. Empty OCR -> "No OCR text extraction available for this document."
      expect(find.text('No OCR text extraction available for this document.'), findsOneWidget);
    });

    testWidgets('Tapping view original triggers URL launcher', (tester) async {
      final repo = MockReceptionRepository(mockDetail: mockDetail);
      await tester.pumpWidget(createTestWidget(authProvider: authProvider, repository: repo));
      await tester.pumpAndSettle();

      // 18. View Original Document -> triggers URL open (mock)
      final viewOriginalBtnFinder = find.widgetWithText(ElevatedButton, 'View Original Document');
      expect(viewOriginalBtnFinder, findsOneWidget);
      await tester.ensureVisible(viewOriginalBtnFinder);
      await tester.pumpAndSettle();
      await tester.tap(viewOriginalBtnFinder);
      await tester.pumpAndSettle();

      expect(urlLaunched, true);
      expect(launchedUrlString, 'https://dummy.signed.url/pdf');
    });

    testWidgets('Back button in AppBar navigates back to queue screen', (tester) async {
      final repo = MockReceptionRepository(mockDetail: mockDetail);
      final appRouter = AppRouter(authProvider);
      
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            Provider<ReceptionRepository>.value(value: repo),
            ChangeNotifierProvider<ReceptionQueueProvider>(
              create: (context) => ReceptionQueueProvider(repository: repo),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: appRouter.router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Go directly to the validation page
      appRouter.router.go('/reception/document/sub-id-123');
      await tester.pumpAndSettle();

      // 19. Back to Queue -> returns to queue
      final backBtnFinder = find.byIcon(Icons.arrow_back);
      expect(backBtnFinder, findsOneWidget);
      await tester.tap(backBtnFinder);
      await tester.pumpAndSettle();

      expect(find.byType(DocumentValidationScreen), findsNothing);
      expect(find.byType(ReceptionQueueScreen), findsOneWidget);
    });

    testWidgets('DocumentValidationScreen resolves without ProviderNotFoundError when accessed via router navigation', (tester) async {
      final repo = MockReceptionRepository(mockDetail: mockDetail);
      final appRouter = AppRouter(authProvider);
      
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            Provider<ReceptionRepository>.value(value: repo),
            // Notice: we do NOT provide ReceptionQueueProvider here!
            // It is only provided inside ReceptionShell (receptionist subtree).
          ],
          child: MaterialApp.router(
            routerConfig: appRouter.router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to the validation page
      appRouter.router.go('/reception/document/sub-id-123');
      await tester.pumpAndSettle();

      // If it has provider dependencies, this would crash and fail the test.
      // Asserting that it renders successfully confirms it is decoupled.
      expect(find.byType(DocumentValidationScreen), findsOneWidget);
      expect(find.text('Jane Doe'), findsWidgets);
    });
  });
}
