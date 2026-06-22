import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/staff/presentation/providers/reception_provider.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/reception_home_screen.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';

// Mock AuthProvider subclass
class MockAuthProvider extends AuthProvider {
  Profile? _mockProfile;
  MockAuthProvider() : super();
  void setMockProfile(Profile? p) {
    _mockProfile = p;
  }
  @override
  Profile? get profile => _mockProfile;
}

// Mock ReceptionProvider subclass
class MockReceptionProvider extends ReceptionProvider {
  final List<PatientQueue> mockQueueEntries;
  final List<Document> mockPendingDocuments;
  final List<Document> mockApprovedDocuments;
  final List<Document> mockRejectedDocuments;

  MockReceptionProvider({
    required this.mockQueueEntries,
    required this.mockPendingDocuments,
    required this.mockApprovedDocuments,
    required this.mockRejectedDocuments,
  }) : super();

  @override
  bool get isLoading => false;

  @override
  List<PatientQueue> get queueEntries => mockQueueEntries;

  @override
  List<Document> get pendingDocuments => mockPendingDocuments;

  @override
  List<Document> get approvedDocuments => mockApprovedDocuments;

  @override
  List<Document> get rejectedDocuments => mockRejectedDocuments;

  @override
  Future<void> loadDashboard() async {
    // No-op for tests
  }

  @override
  void subscribeQueue() {
    // No-op
  }

  @override
  void subscribeDocuments() {
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

  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Widget createTestWidget(AuthProvider authProvider, ReceptionProvider receptionProvider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ReceptionHomeScreen(providerOverride: receptionProvider),
        ),
      ),
    );
  }

  group('Receptionist Documents Three-Tab Widget Tests', () {
    late MockAuthProvider authProvider;
    late DateTime now;
    late List<Document> mockPending;
    late List<Document> mockApproved;
    late List<Document> mockRejected;
    late List<PatientQueue> mockQueue;

    setUp(() {
      authProvider = MockAuthProvider();
      authProvider.setMockProfile(Profile(
        id: 'reception-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      now = DateTime.utc(2026, 6, 22, 9, 30);
      mockQueue = [];

      final patient = Patient(
        id: 'patient-uuid',
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 5, 15),
        gender: Gender.female,
        contactNumber: '09123456789',
        address: 'Rizal, PH',
        createdAt: now,
        updatedAt: now,
      );

      mockPending = [
        Document(
          id: 'doc-pending-1',
          patientId: 'patient-uuid',
          uploaderId: 'patient-uuid',
          fileName: 'referral.pdf',
          filePath: 'uploads/referral.pdf',
          fileType: 'pdf',
          status: DocumentStatus.pending,
          createdAt: now,
          updatedAt: now,
          patient: patient,
        ),
        Document(
          id: 'doc-pending-2',
          patientId: 'patient-uuid',
          uploaderId: 'patient-uuid',
          fileName: 'prescription.pdf',
          filePath: 'uploads/prescription.pdf',
          fileType: 'pdf',
          status: DocumentStatus.pending,
          createdAt: now,
          updatedAt: now,
          patient: patient,
        ),
      ];

      mockApproved = [
        Document(
          id: 'doc-approved-1',
          patientId: 'patient-uuid',
          uploaderId: 'patient-uuid',
          fileName: 'approved_lab.pdf',
          filePath: 'uploads/approved_lab.pdf',
          fileType: 'pdf',
          status: DocumentStatus.approved,
          createdAt: now,
          updatedAt: now,
          patient: patient,
        ),
      ];

      mockRejected = [
        Document(
          id: 'doc-rejected-1',
          patientId: 'patient-uuid',
          uploaderId: 'patient-uuid',
          fileName: 'rejected_receipt.pdf',
          filePath: 'uploads/rejected_receipt.pdf',
          fileType: 'pdf',
          status: DocumentStatus.rejected,
          rejectionReason: 'Blurry text details',
          createdAt: now,
          updatedAt: now,
          patient: patient,
        ),
      ];
    });

    testWidgets('Pending tab shows only pending documents', (tester) async {
      final provider = MockReceptionProvider(
        mockQueueEntries: mockQueue,
        mockPendingDocuments: mockPending,
        mockApprovedDocuments: mockApproved,
        mockRejectedDocuments: mockRejected,
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Documents view is primary, no top-level tab navigation required

      // Assert Pending sub-tab shows the 2 pending documents and none of the others
      expect(find.text('referral.pdf'), findsOneWidget);
      expect(find.text('prescription.pdf'), findsOneWidget);
      expect(find.text('approved_lab.pdf'), findsNothing);
      expect(find.text('rejected_receipt.pdf'), findsNothing);
    });

    testWidgets('Approved tab shows only approved documents with approval timestamp', (tester) async {
      final provider = MockReceptionProvider(
        mockQueueEntries: mockQueue,
        mockPendingDocuments: mockPending,
        mockApprovedDocuments: mockApproved,
        mockRejectedDocuments: mockRejected,
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Documents view is primary

      // Navigate to Approved sub-tab
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Approved')));
      await tester.pumpAndSettle();

      // Assert Approved sub-tab shows approved_lab.pdf and the formatted timestamp
      expect(find.text('approved_lab.pdf'), findsOneWidget);
      expect(find.text('referral.pdf'), findsNothing);
      expect(find.text('rejected_receipt.pdf'), findsNothing);

      final localUpdate = now.toLocal();
      final yyyymmdd = localUpdate.toString().substring(0, 10);
      final hhmm = localUpdate.toString().substring(11, 16);
      expect(find.text('Approved on $yyyymmdd $hhmm'), findsOneWidget);
    });

    testWidgets('Rejected tab shows only rejected documents with timestamp and reason', (tester) async {
      final provider = MockReceptionProvider(
        mockQueueEntries: mockQueue,
        mockPendingDocuments: mockPending,
        mockApprovedDocuments: mockApproved,
        mockRejectedDocuments: mockRejected,
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Documents view is primary

      // Navigate to Rejected sub-tab
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Rejected')));
      await tester.pumpAndSettle();

      // Assert Rejected sub-tab shows rejected_receipt.pdf and the formatted timestamp and reason
      expect(find.text('rejected_receipt.pdf'), findsOneWidget);
      expect(find.text('referral.pdf'), findsNothing);
      expect(find.text('approved_lab.pdf'), findsNothing);

      final localUpdate = now.toLocal();
      final yyyymmdd = localUpdate.toString().substring(0, 10);
      final hhmm = localUpdate.toString().substring(11, 16);
      expect(find.text('Rejected on $yyyymmdd $hhmm — Blurry text details'), findsOneWidget);
    });

    testWidgets('All three tabs render no action buttons', (tester) async {
      final provider = MockReceptionProvider(
        mockQueueEntries: mockQueue,
        mockPendingDocuments: mockPending,
        mockApprovedDocuments: mockApproved,
        mockRejectedDocuments: mockRejected,
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Documents view is primary

      // Helper to check no action buttons exist
      void assertNoActionButtons() {
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Reject'), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      }

      // Check Pending tab
      assertNoActionButtons();

      // Check Approved tab
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Approved')));
      await tester.pumpAndSettle();
      assertNoActionButtons();

      // Check Rejected tab
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Rejected')));
      await tester.pumpAndSettle();
      assertNoActionButtons();
    });

    testWidgets('Empty state renders for tab with no documents', (tester) async {
      final provider = MockReceptionProvider(
        mockQueueEntries: mockQueue,
        mockPendingDocuments: [],
        mockApprovedDocuments: [],
        mockRejectedDocuments: [],
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Documents view is primary

      // Assert Pending tab empty state
      expect(find.text('No pending documents. New submissions will appear here.'), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);

      // Assert Approved tab empty state
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Approved')));
      await tester.pumpAndSettle();
      expect(find.text('No approved documents in the last 30 days.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

      // Assert Rejected tab empty state
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Rejected')));
      await tester.pumpAndSettle();
      expect(find.text('No rejected documents in the last 30 days.'), findsOneWidget);
      expect(find.byIcon(Icons.highlight_off_rounded), findsOneWidget);
    });
  });
}
