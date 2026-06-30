import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';
import 'package:klinikaid_mobile/features/staff/presentation/providers/specialist_provider.dart';
import 'package:klinikaid_mobile/features/staff/presentation/screens/specialist_home_screen.dart';

class MockAuthProvider extends AuthProvider {
  Profile? _mockProfile;
  MockAuthProvider() : super();
  void setMockProfile(Profile? p) {
    _mockProfile = p;
  }
  @override
  Profile? get profile => _mockProfile;
}

class MockSpecialistProvider extends SpecialistProvider {
  final List<Patient> mockSearchResults;
  final Patient? mockSelectedPatient;
  final List<DepartmentRecord> mockPatientTimeline;
  final List<GroupedRecord> mockGroupedPatientTimeline;
  final bool mockIsLoading;

  MockSpecialistProvider({
    this.mockSearchResults = const [],
    this.mockSelectedPatient,
    this.mockPatientTimeline = const [],
    this.mockGroupedPatientTimeline = const [],
    this.mockIsLoading = false,
  }) : super();

  @override
  bool get isLoading => mockIsLoading;

  @override
  List<Patient> get searchResults => mockSearchResults;

  @override
  Patient? get selectedPatient => mockSelectedPatient;

  @override
  List<DepartmentRecord> get patientTimeline => mockPatientTimeline;

  @override
  List<GroupedRecord> get groupedPatientTimeline => mockGroupedPatientTimeline;

  @override
  Future<void> loadAllPatients() async {}

  @override
  void search(String query) {}

  @override
  Future<void> selectPatient(Patient patient) async {}

  @override
  void clearSelection() {}

  @override
  void clearAll() {}
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

  Widget createTestWidget(AuthProvider auth, SpecialistProvider spec) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        home: SpecialistHomeScreen(providerOverride: spec),
      ),
    );
  }

  group('Phase 9: Specialist Patient History Timeline Widget Tests', () {
    late MockAuthProvider authProvider;
    late Patient testPatient;
    late DateTime now;

    setUp(() {
      authProvider = MockAuthProvider();
      authProvider.setMockProfile(Profile(
        id: 'spec-id',
        fullName: 'Dr. House',
        role: UserRole.medicalSpecialist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      testPatient = Patient(
        id: 'patient-123',
        firstName: 'Victor',
        lastName: 'Wembanyama',
        dateOfBirth: DateTime(2004, 1, 4),
        gender: Gender.male,
        contactNumber: '1234567890',
        address: 'France',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      now = DateTime.utc(2026, 6, 23, 9, 22, 13);
    });

    testWidgets('1. Two same-bucket records render as ONE card', (tester) async {
      final rec1 = DepartmentRecord(
        id: 'rec-1',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.imaging,
        testType: 'Leg X-ray',
        testResults: {'test_name': 'Findings', 'test_value': 'Torn Achilles Tendon'},
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        updatedAt: now,
      );

      final rec2 = DepartmentRecord(
        id: 'rec-2',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.imaging,
        testType: 'Leg X-ray',
        testResults: {'test_name': 'Impression', 'test_value': 'Weak plantar flexion'},
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 5)),
        updatedAt: now.add(const Duration(seconds: 5)),
      );

      final grouped = groupRecords([rec1, rec2]);
      final specProvider = MockSpecialistProvider(
        mockSelectedPatient: testPatient,
        mockPatientTimeline: [rec1, rec2],
        mockGroupedPatientTimeline: grouped,
      );

      await tester.pumpWidget(createTestWidget(authProvider, specProvider));
      await tester.pumpAndSettle();

      // Assert only ONE Leg X-ray card is rendered (not two)
      expect(find.text('Leg X-ray'), findsOneWidget);
      expect(find.text('Consolidated Diagnostic Report (2 parameters)'), findsOneWidget);
    });

    testWidgets('2. Grouped card click opens modal and shows stacked parameters', (tester) async {
      final rec1 = DepartmentRecord(
        id: 'rec-1',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.imaging,
        testType: 'Leg X-ray',
        testResults: {'test_name': 'Findings', 'test_value': 'Torn Achilles Tendon'},
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        updatedAt: now,
      );

      final rec2 = DepartmentRecord(
        id: 'rec-2',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.imaging,
        testType: 'Leg X-ray',
        testResults: {'test_name': 'Impression', 'test_value': 'Weak plantar flexion'},
        referenceRangeStatus: ReferenceRangeStatus.inconclusive,
        createdAt: now.add(const Duration(seconds: 5)),
        updatedAt: now.add(const Duration(seconds: 5)),
      );

      final grouped = groupRecords([rec1, rec2]);
      final specProvider = MockSpecialistProvider(
        mockSelectedPatient: testPatient,
        mockPatientTimeline: [rec1, rec2],
        mockGroupedPatientTimeline: grouped,
      );

      await tester.pumpWidget(createTestWidget(authProvider, specProvider));
      await tester.pumpAndSettle();

      // Tap on the card
      await tester.tap(find.text('Leg X-ray'));
      await tester.pumpAndSettle();

      // Expect to see both parameter values in the bottom sheet details
      expect(find.text('Torn Achilles Tendon'), findsOneWidget);
      expect(find.text('Weak plantar flexion'), findsOneWidget);
    });

    testWidgets('3. Long clinical text (test_value) wraps without overflow', (tester) async {
      final longValue = 'Weak Plantar Flexion: Significant weakness in plantar flexion, with visual presentation of torn achilles tendon tissue. Severe pain on manipulation and loading. The patient was instructed to rest immediately and seek surgical consult. Surgical repair recommended.';
      
      final rec1 = DepartmentRecord(
        id: 'rec-1',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.imaging,
        testType: 'Leg X-ray',
        testResults: {'test_name': 'Impression', 'test_value': longValue},
        referenceRangeStatus: ReferenceRangeStatus.criticalHigh,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = groupRecords([rec1]);
      final specProvider = MockSpecialistProvider(
        mockSelectedPatient: testPatient,
        mockPatientTimeline: [rec1],
        mockGroupedPatientTimeline: grouped,
      );

      // Force a smaller window size to verify no overflow
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(createTestWidget(authProvider, specProvider));
      await tester.pumpAndSettle();

      // Verify long test value is visible
      expect(find.textContaining('Result: Weak Plantar Flexion: Significant weakness'), findsOneWidget);
      
      // Ensure no overflow errors occurred
      expect(tester.takeException(), isNull);

      // Reset tester size
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('4. Single-parameter records render unchanged (backward compat)', (tester) async {
      final rec1 = DepartmentRecord(
        id: 'rec-1',
        patientId: testPatient.id,
        recorderId: 'tech-123',
        department: Department.laboratory,
        testType: 'Hemoglobin',
        testResults: {'test_name': 'Hgb', 'test_value': '14.5', 'unit': 'g/dL'},
        referenceRangeStatus: ReferenceRangeStatus.normal,
        createdAt: now,
        updatedAt: now,
      );

      final grouped = groupRecords([rec1]);
      final specProvider = MockSpecialistProvider(
        mockSelectedPatient: testPatient,
        mockPatientTimeline: [rec1],
        mockGroupedPatientTimeline: grouped,
      );

      await tester.pumpWidget(createTestWidget(authProvider, specProvider));
      await tester.pumpAndSettle();

      expect(find.text('Hemoglobin'), findsOneWidget);
      expect(find.text('Test Name: Hgb'), findsOneWidget);
      expect(find.text('Result: 14.5 g/dL'), findsOneWidget);
    });
  });
}
