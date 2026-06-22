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

  group('Receptionist Hide Today\'s Queue Tab Widget Tests', () {
    testWidgets('ReceptionHomeScreen does not render a Today\'s Queue tab and Document list is primary', (tester) async {
      final authProvider = MockAuthProvider();
      authProvider.setMockProfile(Profile(
        id: 'reception-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final now = DateTime.now();

      final queueEntries = [
        PatientQueue(
          id: 1,
          patientId: 'patient-uuid-1',
          status: QueueStatus.waiting,
          department: Department.laboratory,
          triageNotes: 'Routine test',
          priorityLevel: PriorityLevel.routine,
          estimatedWaitMinutes: 10,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-uuid-1',
            firstName: 'UniqueQueue',
            lastName: 'PatientName',
            dateOfBirth: DateTime(1990, 5, 15),
            gender: Gender.female,
            contactNumber: '09123456789',
            address: 'Rizal, PH',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final pendingDocuments = [
        Document(
          id: 'doc-pending-1',
          patientId: 'patient-uuid-2',
          uploaderId: 'patient-uuid-2',
          fileName: 'referral_document.pdf',
          filePath: 'uploads/referral_document.pdf',
          fileType: 'pdf',
          status: DocumentStatus.pending,
          createdAt: now,
          updatedAt: now,
          patient: Patient(
            id: 'patient-uuid-2',
            firstName: 'Jane',
            lastName: 'DocPatient',
            dateOfBirth: DateTime(1995, 10, 10),
            gender: Gender.female,
            contactNumber: '09123456788',
            address: 'Manila, PH',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      ];

      final provider = MockReceptionProvider(
        mockQueueEntries: queueEntries,
        mockPendingDocuments: pendingDocuments,
        mockApprovedDocuments: const [],
        mockRejectedDocuments: const [],
      );

      await tester.pumpWidget(createTestWidget(authProvider, provider));
      await tester.pumpAndSettle();

      // Assert: The text "Today's Queue" tab is NOT visible/rendered
      expect(find.text("Today's Queue"), findsNothing);

      // Assert: The patient name only in the queue entries list is NOT rendered
      expect(find.text("UniqueQueue PatientName"), findsNothing);

      // Assert: The pending document list content IS rendered as primary view content
      expect(find.text("referral_document.pdf"), findsOneWidget);
      expect(find.text("Jane DocPatient"), findsOneWidget);
    });
  });
}
