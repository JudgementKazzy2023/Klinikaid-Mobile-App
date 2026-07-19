import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/screens/result_entry_screen.dart';
import 'package:klinikaid_mobile/features/department/data/lab_value_extraction_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/core/utils/lab_validators.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/department/domain/flag_calculator.dart';
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';

class MockSessionActivityService extends SessionActivityService {
  @override
  void startMonitoring({required Duration timeout, required VoidCallback onTimeout}) {}
  @override
  void stopMonitoring() {}
  @override
  void recordActivity() {}
  @override
  Future<void> restoreLastActivity() async {}
}

class MockAuthProviderForLab extends AuthProvider {
  final Department mockDepartment;

  MockAuthProviderForLab({this.mockDepartment = Department.laboratory})
      : super(
          activityService: MockSessionActivityService(),
        );

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLoading => false;
  @override
  Profile? get profile => Profile(
    id: 'mock-staff-uuid',
    fullName: 'Lab Staff',
    role: UserRole.departmentStaff,
    department: mockDepartment,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    isActive: true,
  );
  @override
  bool get hasConsented => true;
  @override
  bool get isOnboarded => true;
}

class MockDepartmentRepository extends DepartmentRepository {
  String? lastPatientId;
  List<LabResultRow>? lastRows;
  bool submitCalled = false;

  @override
  String? get currentUserId => 'mock-recorder-uuid';

  @override
  Future<void> submitLabResults({
    required String patientId,
    required List<LabResultRow> rows,
  }) async {
    submitCalled = true;
    lastPatientId = patientId;
    lastRows = rows;
  }

  @override
  Future<void> submitFreeTextResult({
    required String patientId,
    required String testName,
    required String findings,
    required String impression,
    String? notes,
  }) async {
    submitCalled = true;
    lastPatientId = patientId;
  }

  @override
  Future<Patient> getPatient(String id) async {
    return Patient(
      id: id,
      profileId: id,
      firstName: 'John',
      lastName: 'Doe',
      dateOfBirth: DateTime(1990, 1, 1),
      gender: Gender.male,
      contactNumber: '09123456789',
      email: 'john.doe@gmail.com',
      address: '123 Street Manila',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

class MockLabValueExtractionService extends LabValueExtractionService {
  final LabValueExtractionResult result;

  MockLabValueExtractionService(this.result);

  @override
  Future<LabValueExtractionResult> extractFromImagePath(String imagePath) async {
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  late MockDepartmentRepository mockRepo;
  late MockAuthProviderForLab mockAuth;
  late LocalDatabase localDatabase;

  setUp(() {
    mockRepo = MockDepartmentRepository();
    mockAuth = MockAuthProviderForLab();
    localDatabase = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await localDatabase.close();
  });

  Widget createTestWidget(AppRouter router) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
        Provider<DepartmentRepository>.value(value: mockRepo),
      ],
      child: MaterialApp.router(
        routerConfig: router.router,
      ),
    );
  }

  group('Lab entry input validation and formatting tests', () {
    test('1. isValueFlagged sanity checks', () {
      const range = LabReferenceRange(
        parameter: 'Hemoglobin',
        unit: 'g/dL',
        maleMin: 13.5,
        maleMax: 17.5,
        femaleMin: 12.0,
        femaleMax: 15.5,
      );
      // Male out-of-range (high)
      expect(isValueFlagged(18.0, range, 'male'), isTrue);
      // Male in-range
      expect(isValueFlagged(14.0, range, 'male'), isFalse);
      // Female out-of-range (low)
      expect(isValueFlagged(11.0, range, 'female'), isTrue);
      // Female in-range
      expect(isValueFlagged(13.0, range, 'female'), isFalse);
    });

    test('2. MaxIntegerDigitsFormatter limits digits correctly', () {
      const formatter = MaxIntegerDigitsFormatter(4);

      // Allowed cases
      expect(
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '9999'),
        ).text,
        '9999',
      );
      expect(
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '150.5'),
        ).text,
        '150.5',
      );
      expect(
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '.5'),
        ).text,
        '.5',
      );

      // Blocked cases (returns old value)
      const oldVal = TextEditingValue(text: '1234');
      expect(
        formatter.formatEditUpdate(
          oldVal,
          const TextEditingValue(text: '12345'),
        ).text,
        '1234',
      );
      expect(
        formatter.formatEditUpdate(
          oldVal,
          const TextEditingValue(text: '12345.6'),
        ).text,
        '1234',
      );
    });

    test('2b. OCR extraction filter drops unsafe Gemini values', () {
      final valid = LabValueExtractionService.sanitizeGeminiText('''
```json
{
  "panel": "Complete Blood Count (CBC)",
  "values": {
    "Hemoglobin": "14.2",
    "White Blood Cells (WBC)": "7.1",
    "Platelets": "250",
    "Creatinine": "1.2",
    "Unknown": "999",
    "BadText": "high"
  },
  "tokens_used": 42
}
```
''');

      expect(valid.panel, 'Complete Blood Count (CBC)');
      expect(valid.values, {
        'Hemoglobin': '14.2',
        'White Blood Cells (WBC)': '7.1',
        'Platelets': '250',
      });

      final partial = LabValueExtractionService.sanitizeFunctionResponse({
        'panel': 'Renal Function',
        'values': {
          'Creatinine': '1.15',
          'Hemoglobin': '14.0',
          'Extra': 'abc',
        },
      });
      expect(partial.panel, 'Renal Function');
      expect(partial.values, {'Creatinine': '1.15'});

      final fbs = LabValueExtractionService.sanitizeFunctionResponse({
        'panel': 'Fasting Blood Sugar (FBS)',
        'values': {
          'Fasting Blood Sugar (FBS)': '95',
          'Creatinine': '1.2',
          'Unknown Panel Value': '99',
        },
      });
      expect(fbs.panel, 'Fasting Blood Sugar (FBS)');
      expect(fbs.values, {'Fasting Blood Sugar (FBS)': '95'});

      final failed = LabValueExtractionService.sanitizeGeminiText('I am sorry, the image is too blurry.');
      expect(failed.panel, isNull);
      expect(failed.values, isEmpty);
    });

    testWidgets('3. Out-of-range dialog warning cancels or confirms submit correctly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final router = AppRouter(mockAuth);
      await tester.pumpWidget(createTestWidget(router));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Default group is Complete Blood Count (CBC). Enter abnormal value: 25.5 (out of range) for Hemoglobin
      final inputFinder = find.byKey(const Key('param_input_Hemoglobin'));
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, '25.5');
      await tester.pumpAndSettle();

      // Tap submit button
      final submitBtn = find.text('Submit Test Results');
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear with Title: "Confirm flagged value(s)"
      expect(find.text('Confirm flagged value(s)'), findsOneWidget);
      
      // Formatting matches: "Hemoglobin: 25.5 g/dL (normal 13.5–17.5). Please confirm this value was entered correctly."
      expect(find.textContaining('Hemoglobin: 25.5 g/dL (normal 13.5–17.5). Please confirm this value was entered correctly.'), findsOneWidget);

      // Click "Review" (Cancel)
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      // Dialog is gone, submission not executed
      expect(find.text('Confirm flagged value(s)'), findsNothing);
      expect(mockRepo.submitCalled, isFalse);

      // Tap submit again, click "Confirm & Save"
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      expect(find.text('Confirm flagged value(s)'), findsOneWidget);

      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();

      // Dialog is closed, submit is executed
      expect(mockRepo.submitCalled, isTrue);
      expect(mockRepo.lastPatientId, 'patient-123');
      expect(mockRepo.lastRows?.first.testName, 'Hemoglobin');
      expect(mockRepo.lastRows?.first.testValue, '25.5');
      expect(mockRepo.lastRows?.first.isFlagged, isTrue);
    });

    testWidgets('3b. OCR autofill sets panel and values atomically without auto-save', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final extractionService = MockLabValueExtractionService(
        const LabValueExtractionResult(
          panel: 'Renal Function',
          values: {'Creatinine': '1.15'},
          tokensUsed: 10,
        ),
      );

      final testRouter = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/entry',
            builder: (_, _) => ResultEntryScreen(
              patientId: 'patient-123',
              repo: mockRepo,
              extractionService: extractionService,
              imagePathPicker: () async => 'dummy.jpg',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ],
          child: MaterialApp.router(routerConfig: testRouter),
        ),
      );
      testRouter.push('/entry');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('extract_lab_values_button')));
      await tester.pumpAndSettle();

      expect(mockRepo.submitCalled, isFalse);
      expect(find.byKey(const Key('ocr_verify_note')), findsOneWidget);
      expect(find.text('Renal Function'), findsOneWidget);
      expect(find.byKey(const Key('param_input_Creatinine')), findsOneWidget);

      final creatinineTextField = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('param_input_Creatinine')),
        matching: find.byType(TextField),
      ));
      expect(creatinineTextField.controller?.text, '1.15');
      expect(creatinineTextField.enabled, isNot(false));

      await tester.enterText(find.byKey(const Key('param_input_Creatinine')), '1.0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Confirm flagged value(s)'), findsNothing);
      expect(mockRepo.submitCalled, isTrue);
      expect(mockRepo.lastRows?.single.testName, 'Creatinine');
      expect(mockRepo.lastRows?.single.testValue, '1.0');
    });

    testWidgets('4. In-range values bypass the warning dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final router = AppRouter(mockAuth);
      await tester.pumpWidget(createTestWidget(router));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Enter normal value: 14.5 for Hemoglobin
      final inputFinder = find.byKey(const Key('param_input_Hemoglobin'));
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, '14.5');
      await tester.pumpAndSettle();

      final submitBtn = find.text('Submit Test Results');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Dialog should NOT show, and submission occurs directly
      expect(find.text('Confirm flagged value(s)'), findsNothing);
      expect(mockRepo.submitCalled, isTrue);
      expect(mockRepo.lastRows?.first.isFlagged, isFalse);
    });

    testWidgets('5. Multiple flagged params list all in the warning dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final router = AppRouter(mockAuth);
      await tester.pumpWidget(createTestWidget(router));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Enter abnormal value for Hemoglobin: 11.0
      final inputHgb = find.byKey(const Key('param_input_Hemoglobin'));
      await tester.enterText(inputHgb, '11.0');

      // Enter abnormal value for Platelets: 500
      final inputPlt = find.byKey(const Key('param_input_Platelets'));
      await tester.enterText(inputPlt, '500');
      await tester.pumpAndSettle();

      final submitBtn = find.text('Submit Test Results');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Dialog should show with both
      expect(find.text('Confirm flagged value(s)'), findsOneWidget);
      expect(find.textContaining('Hemoglobin: 11 g/dL (normal 13.5–17.5). Please confirm this value was entered correctly.'), findsOneWidget);
      expect(find.textContaining('Platelets: 500 x10^3/µL (normal 150–450). Please confirm this value was entered correctly.'), findsOneWidget);

      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();
      expect(mockRepo.submitCalled, isTrue);
    });

    testWidgets('6. Consistency test: badge-flag state and dialog-trigger state match', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final router = AppRouter(mockAuth);
      await tester.pumpWidget(createTestWidget(router));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Part A: In-range value (14.5)
      final inputFinder = find.byKey(const Key('param_input_Hemoglobin'));
      await tester.enterText(inputFinder, '14.5');
      await tester.pumpAndSettle();

      // Assert badge is NOT showing
      expect(find.text('Flagged'), findsNothing);

      // Submit and assert dialog is NOT showing
      final submitBtn = find.text('Submit Test Results');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      expect(find.text('Confirm flagged value(s)'), findsNothing);

      // Back to entry form (submit did direct save, let's re-enter)
      mockRepo.submitCalled = false;
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Part B: Out-of-range value (25.5)
      final inputFinder2 = find.byKey(const Key('param_input_Hemoglobin'));
      await tester.enterText(inputFinder2, '25.5');
      await tester.pumpAndSettle();

      // Assert badge IS showing
      expect(find.text('Flagged'), findsOneWidget);

      // Submit and assert dialog IS showing
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();
      expect(find.text('Confirm flagged value(s)'), findsOneWidget);
    });

    testWidgets('7. 4-digit cap widget level test', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final router = AppRouter(mockAuth);
      await tester.pumpWidget(createTestWidget(router));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const Key('param_input_Hemoglobin'));
      
      // Enter "9999" first to establish an old value
      await tester.enterText(inputFinder, '9999');
      await tester.pumpAndSettle();
      
      // Enter "99999" (5 digits, should trigger rejection and fall back to "9999")
      await tester.enterText(inputFinder, '99999');
      await tester.pumpAndSettle();
      
      final TextField textField = tester.widget(find.descendant(
        of: inputFinder,
        matching: find.byType(TextField),
      ));
      expect(textField.controller?.text, '9999');

      // Enter "150.5"
      await tester.enterText(inputFinder, '150.5');
      await tester.pumpAndSettle();
      final TextField textField2 = tester.widget(find.descendant(
        of: inputFinder,
        matching: find.byType(TextField),
      ));
      expect(textField2.controller?.text, '150.5');
    });

    testWidgets('8. Free-text mode: no cap, no dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final imagingAuth = MockAuthProviderForLab(mockDepartment: Department.imaging);
      final router = AppRouter(imagingAuth);
      
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<LocalDatabase>.value(value: localDatabase),
          ChangeNotifierProvider<AuthProvider>.value(value: imagingAuth),
          Provider<DepartmentRepository>.value(value: mockRepo),
        ],
        child: MaterialApp.router(
          routerConfig: router.router,
        ),
      ));
      
      router.router.go('/department/queue');
      await tester.pumpAndSettle();
      router.router.push('/department/result-entry/patient-123');
      await tester.pumpAndSettle();

      // Find findings field
      final findingsFinder = find.byKey(const Key('findings_input'));
      expect(findingsFinder, findsOneWidget);
      
      // Enter text
      await tester.enterText(findingsFinder, 'Abnormal findings showing 99999 units.');
      await tester.pumpAndSettle();
      
      final provider = Provider.of<ResultEntryProvider>(
        tester.element(findingsFinder),
        listen: false,
      );
      expect(provider.findings, 'Abnormal findings showing 99999 units.');

      // Enter impression
      final impressionFinder = find.byKey(const Key('impression_input'));
      await tester.enterText(impressionFinder, 'Impression details.');
      await tester.pumpAndSettle();

      // Tap submit and verify no confirmation dialog is shown
      final submitBtn = find.text('Submit Test Results');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm flagged value(s)'), findsNothing);
    });
  });
}
