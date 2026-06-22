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

  MockReceptionProvider(this.mockQueueEntries, this.mockPendingDocuments) : super();

  @override
  bool get isLoading => false;

  @override
  List<PatientQueue> get queueEntries => mockQueueEntries;

  @override
  List<Document> get pendingDocuments => mockPendingDocuments;

  @override
  List<Document> get approvedDocuments => const [];

  @override
  List<Document> get rejectedDocuments => const [];

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
        home: ReceptionHomeScreen(providerOverride: receptionProvider),
      ),
    );
  }

  testWidgets('ReceptionHomeScreen does not render Mark Arrived, Approve, or Reject buttons', (tester) async {
    final authProvider = MockAuthProvider();
    authProvider.setMockProfile(Profile(
      id: 'reception-uuid',
      fullName: 'Bob Receptionist',
      role: UserRole.receptionist,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    final now = DateTime.now();
    final mockQueueEntries = [
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
          firstName: 'Jane',
          lastName: 'Patient',
          dateOfBirth: DateTime(1990, 5, 15),
          gender: Gender.female,
          contactNumber: '09123456789',
          address: 'Address 1',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    ];

    final mockPendingDocuments = [
      Document(
        id: 'doc-uuid-1',
        patientId: 'patient-uuid-1',
        uploaderId: 'patient-uuid-1',
        fileName: 'referral.pdf',
        filePath: 'uploads/referral.pdf',
        fileType: 'pdf',
        status: DocumentStatus.pending,
        createdAt: now,
        updatedAt: now,
        patient: Patient(
          id: 'patient-uuid-1',
          firstName: 'Jane',
          lastName: 'Patient',
          dateOfBirth: DateTime(1990, 5, 15),
          gender: Gender.female,
          contactNumber: '09123456789',
          address: 'Address 1',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    ];

    final receptionProvider = MockReceptionProvider(mockQueueEntries, mockPendingDocuments);

    await tester.pumpWidget(createTestWidget(authProvider, receptionProvider));
    await tester.pumpAndSettle();

    // Verify "Mark Arrived" button is NOT rendered
    expect(find.text('Mark Arrived'), findsNothing);

    expect(find.text('referral.pdf'), findsOneWidget);

    // Verify "Approve" and "Reject" buttons are NOT rendered
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // Verify status badge "PENDING" is rendered on DocumentReviewCard
    expect(find.text('PENDING'), findsOneWidget);
  });
}
