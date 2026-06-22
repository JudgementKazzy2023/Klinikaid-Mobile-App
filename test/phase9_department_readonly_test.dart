import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/staff/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/department_home_screen.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
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

// Mock DepartmentProvider subclass
class MockDepartmentProvider extends DepartmentProvider {
  final List<PatientQueue> mockQueueEntries;

  MockDepartmentProvider(super.department, this.mockQueueEntries);

  @override
  bool get isLoading => false;

  @override
  List<PatientQueue> get queueEntries => mockQueueEntries;

  @override
  Future<void> loadDashboard() async {
    // No-op for tests
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

  Widget createTestWidget(AuthProvider authProvider, DepartmentProvider deptProvider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp(
        home: DepartmentHomeScreen(providerOverride: deptProvider),
      ),
    );
  }

  testWidgets('DepartmentHomeScreen does not render Start Service or Complete buttons', (tester) async {
    final authProvider = MockAuthProvider();
    authProvider.setMockProfile(Profile(
      id: 'staff-uuid',
      fullName: 'Alice Laboratory Staff',
      role: UserRole.departmentStaff,
      department: Department.laboratory,
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
          firstName: 'John',
          lastName: 'Doe',
          dateOfBirth: DateTime(1990, 1, 1),
          gender: Gender.male,
          contactNumber: '09123456789',
          address: 'Address 1',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      PatientQueue(
        id: 2,
        patientId: 'patient-uuid-2',
        status: QueueStatus.inProgress,
        department: Department.laboratory,
        triageNotes: 'Urgent check',
        priorityLevel: PriorityLevel.urgent,
        estimatedWaitMinutes: 5,
        createdAt: now,
        updatedAt: now,
        patient: Patient(
          id: 'patient-uuid-2',
          firstName: 'Jane',
          lastName: 'Smith',
          dateOfBirth: DateTime(1995, 2, 2),
          gender: Gender.female,
          contactNumber: '09123456780',
          address: 'Address 2',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    ];

    final deptProvider = MockDepartmentProvider('laboratory', mockQueueEntries);

    await tester.pumpWidget(createTestWidget(authProvider, deptProvider));
    await tester.pumpAndSettle();

    // Verify list items are rendered
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Jane Smith'), findsOneWidget);

    // Verify Start Service and Complete buttons are NOT rendered
    expect(find.text('Start Service'), findsNothing);
    expect(find.text('Complete'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });
}
