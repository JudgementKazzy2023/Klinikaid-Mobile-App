// Narrative laboratory result entry (mobile issue15 / roadmap9 batch ST02).
//
// Contract source: web src/lib/constants.ts LAB_NARRATIVE_TESTS /
// LAB_NARRATIVE_FIELDS / LAB_NARRATIVE_MAX_LENGTH and
// src/lib/records/validateLabResult.ts validateLabNarrative. All HTTP here is
// mocked; no live network or fixtures.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/data/lab_value_extraction_service.dart';
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';
import 'package:klinikaid_mobile/features/documents/clinic_test_catalog.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/screens/result_entry_screen.dart';

/// Exact narrative test_type names from web constants.ts. Spacing (including
/// around '/') and casing are part of the stored row contract.
const List<String> kWebNarrativeTests = [
  'Urinalysis',
  'Fecalysis',
  'Blood Urea Nitrogen (BUN)',
  'SGPT / ALT',
  'SGOT / AST',
  'Lipid Profile (narrative)',
];

/// Exact id -> label pairs of the web CLINIC_TEST_CATALOG (constants.ts @
/// 06ccce1). The mobile clinic test catalog must offer the same requestable
/// tests under the same ids.
const Map<String, String> kWebClinicCatalog = {
  'cbc': 'Complete Blood Count (CBC)',
  'urinalysis': 'Urinalysis',
  'fecalysis': 'Fecalysis',
  'fbs': 'Fasting Blood Sugar (FBS)',
  'lipid_profile': 'Lipid Profile',
  'creatinine': 'Creatinine',
  'bun': 'Blood Urea Nitrogen (BUN)',
  'sgpt_alt': 'SGPT / ALT',
  'sgot_ast': 'SGOT / AST',
  'chest_xray': 'Chest X-ray',
  'ecg': 'ECG',
  'ultrasound': 'Ultrasound',
};

/// Web CLINIC_TEST_CATALOG recording targets for the laboratory-requestable
/// entries (constants.ts @ 06ccce1 `recording`): panel name for structured
/// panels, narrative test name for narrative tests. The three non-laboratory
/// entries (chest_xray, ecg, ultrasound) record outside the lab entry form and
/// are deliberately absent.
const Map<String, String> kWebLabRecordingTargets = {
  'cbc': 'Complete Blood Count (CBC)', // panel
  'urinalysis': 'Urinalysis', // narrative
  'fecalysis': 'Fecalysis', // narrative
  'fbs': 'Fasting Blood Sugar (FBS)', // panel
  'lipid_profile': 'Lipid Profile (narrative)', // narrative
  'creatinine': 'Renal Function', // panel
  'bun': 'Blood Urea Nitrogen (BUN)', // narrative
  'sgpt_alt': 'SGPT / ALT', // narrative
  'sgot_ast': 'SGOT / AST', // narrative
};

/// Extraction service whose response is released by the test, so a stale
/// structured OCR result can land after the user changed the selection.
class _DelayedExtractionService extends LabValueExtractionService {
  final Completer<LabValueExtractionResult> completer = Completer();

  @override
  Future<LabValueExtractionResult> extractFromImagePath(String imagePath) =>
      completer.future;
}

class _FakeGoTrueClient extends GoTrueClient {
  _FakeGoTrueClient() : super(autoRefreshToken: false);

  @override
  User? get currentUser => User(
        id: 'recorder-uuid',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );
}

/// Real Supabase transport with mocked HTTP and a fixed signed-in user, so the
/// real DepartmentRepository serialises rows through the real Postgrest path.
class _AuthedSupabaseClient extends SupabaseClient {
  _AuthedSupabaseClient(http.Client httpClient)
      : super(
          'https://example.invalid',
          'fake',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: httpClient,
        );

  @override
  GoTrueClient get auth => _FakeGoTrueClient();
}

class _CapturingRepository extends DepartmentRepository {
  int freeTextCalls = 0;
  int labCalls = 0;
  String? lastPatientId;
  String? lastTestName;
  String? lastFindings;
  String? lastImpression;
  String? lastNotes;
  List<LabResultRow>? lastRows;
  bool throwQueueCompletion = false;

  @override
  String? get currentUserId => 'mock-recorder-uuid';

  @override
  Future<void> submitFreeTextResult({
    required String patientId,
    required String testName,
    required String findings,
    required String impression,
    String? notes,
  }) async {
    freeTextCalls++;
    lastPatientId = patientId;
    lastTestName = testName;
    lastFindings = findings;
    lastImpression = impression;
    lastNotes = notes;
    if (throwQueueCompletion) throw const QueueCompletionFailure();
  }

  @override
  Future<void> submitLabResults({
    required String patientId,
    required List<LabResultRow> rows,
  }) async {
    labCalls++;
    lastPatientId = patientId;
    lastRows = rows;
  }

  @override
  Future<Patient> getPatient(String id) async => Patient(
        id: id,
        profileId: id,
        firstName: 'Jane',
        lastName: 'Patient',
        dateOfBirth: DateTime(1990, 1, 1),
        gender: Gender.female,
        contactNumber: '09123456789',
        email: 'jane@example.com',
        address: '123 Street Manila',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}

class _MockSessionActivityService extends SessionActivityService {
  @override
  void startMonitoring({required Duration timeout, required VoidCallback onTimeout}) {}

  @override
  void stopMonitoring() {}

  @override
  void recordActivity() {}

  @override
  Future<void> restoreLastActivity() async {}
}

class _MockAuthProvider extends AuthProvider {
  _MockAuthProvider() : super(activityService: _MockSessionActivityService());

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  Profile? get profile => Profile(
        id: 'staff-uuid',
        fullName: 'Lab Staff',
        role: UserRole.departmentStaff,
        department: Department.laboratory,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: true,
      );

  @override
  bool get hasConsented => true;

  @override
  bool get isOnboarded => true;
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
        url: 'https://example.invalid',
        anonKey: 'synthetic-test-key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  group('Narrative catalog contract (web constants.ts sync)', () {
    test('kLabNarrativeTests matches the exact web narrative test names', () {
      expect(kLabNarrativeTests, kWebNarrativeTests);
    });

    test('structured group keys are unchanged; Lipid Profile stays Cholesterol', () {
      expect(kLabTestGroups.keys.toList(), [
        'Complete Blood Count (CBC)',
        'Fasting Blood Sugar (FBS)',
        'Renal Function',
        'Lipid Profile',
      ]);
      expect(kLabTestGroups['Lipid Profile'], ['Cholesterol']);
    });

    test('narrative tests and structured groups are disjoint', () {
      for (final name in kLabNarrativeTests) {
        expect(kLabTestGroups.containsKey(name), isFalse,
            reason: '$name must not collide with a structured group key');
      }
      expect(kLabNarrativeFields, ['Findings', 'Impression']);
      expect(kLabNarrativeMaxLength, 5000);
    });
  });

  group('HTTP payload contract (real repository, mocked HTTP)', () {
    late List<http.Request> requests;
    late DepartmentRepository repo;

    setUp(() {
      requests = [];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          // PostgREST returns the updated rows when the request selects
          // columns. Queue completion requires at least one matching row.
          return http.Response(
            '[{"id": "queue-row-1"}]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '[]',
          201,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
      repo = DepartmentRepository(client: _AuthedSupabaseClient(client))
        ..adminDepartmentOverride = 'laboratory';
    });

    Map<String, dynamic> row(int index) {
      final insert = requests.singleWhere((r) => r.url.path == '/rest/v1/department_records');
      return (jsonDecode(insert.body) as List)[index] as Map<String, dynamic>;
    }

    test('narrative save posts exact Findings+Impression rows and queue update', () async {
      final provider = ResultEntryProvider(repo);
      provider.setNarrativeTest('SGPT / ALT');
      provider.setFindings('  Mild elevation noted.  ');
      provider.setImpression('  Borderline ALT.  ');
      provider.setNotes('  Follow-up in 4 weeks.  ');

      final ok = await provider.submitNarrativeLabResult(patientId: 'patient-1');
      expect(ok, isTrue);

      final insert =
          requests.singleWhere((r) => r.url.path == '/rest/v1/department_records');
      expect(insert.method, 'POST');
      final rows = jsonDecode(insert.body) as List;
      expect(rows, [
        {
          'patient_id': 'patient-1',
          'recorder_id': 'recorder-uuid',
          'department': 'laboratory',
          'test_type': 'SGPT / ALT',
          'test_name': 'Findings',
          'test_value': 'Mild elevation noted.',
          'unit': null,
          'reference_range_min': null,
          'reference_range_max': null,
          'is_flagged': false,
          'notes': 'Follow-up in 4 weeks.',
        },
        {
          'patient_id': 'patient-1',
          'recorder_id': 'recorder-uuid',
          'department': 'laboratory',
          'test_type': 'SGPT / ALT',
          'test_name': 'Impression',
          'test_value': 'Borderline ALT.',
          'unit': null,
          'reference_range_min': null,
          'reference_range_max': null,
          'is_flagged': false,
          'notes': 'Follow-up in 4 weeks.',
        },
      ]);

      final queueUpdate =
          requests.singleWhere((r) => r.url.path == '/rest/v1/patient_queue');
      expect(queueUpdate.method, 'PATCH');
      expect(jsonDecode(queueUpdate.body), {'status': 'completed'});
    });

    test('whitespace impression omits the Impression row entirely', () async {
      final provider = ResultEntryProvider(repo);
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Clear, no abnormalities.');
      provider.setImpression('   ');

      final ok = await provider.submitNarrativeLabResult(patientId: 'patient-1');
      expect(ok, isTrue);

      final rows = jsonDecode(
              requests.singleWhere((r) => r.url.path == '/rest/v1/department_records').body)
          as List;
      expect(rows, hasLength(1));
      expect(row(0)['test_name'], 'Findings');
      expect(row(0)['test_type'], 'Urinalysis');
      expect(row(0)['test_value'], 'Clear, no abnormalities.');
      expect(row(0)['unit'], isNull);
      expect(row(0)['reference_range_min'], isNull);
      expect(row(0)['reference_range_max'], isNull);
      expect(row(0)['is_flagged'], false);
    });

    test('each narrative test_type round-trips exactly through the repository', () async {
      for (final testType in kWebNarrativeTests) {
        requests.clear();
        final provider = ResultEntryProvider(repo);
        provider.setNarrativeTest(testType);
        provider.setFindings('As reported.');

        final ok = await provider.submitNarrativeLabResult(patientId: 'patient-1');
        expect(ok, isTrue, reason: '$testType should submit');
        expect(row(0)['test_type'], testType);
      }
    });

    test('structured panel save still posts numeric rows unchanged', () async {
      final provider = ResultEntryProvider(repo);
      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setParameterValue('Hemoglobin', '14.0');

      final ok = await provider.submitLabResults(patientId: 'patient-1', gender: 'male');
      expect(ok, isTrue);

      final rows = jsonDecode(
              requests.singleWhere((r) => r.url.path == '/rest/v1/department_records').body)
          as List;
      expect(rows, [
        {
          'patient_id': 'patient-1',
          'recorder_id': 'recorder-uuid',
          'department': 'laboratory',
          'test_type': 'Complete Blood Count (CBC)',
          'test_name': 'Hemoglobin',
          'test_value': '14.0',
          'unit': 'g/dL',
          'reference_range_min': 13.5,
          'reference_range_max': 17.5,
          'is_flagged': false,
          'notes': null,
        },
      ]);
    });
  });

  group('Narrative provider validation (refuses before write)', () {
    late _CapturingRepository repo;
    late ResultEntryProvider provider;

    setUp(() {
      repo = _CapturingRepository();
      provider = ResultEntryProvider(repo);
    });

    test('every one of the six narrative tests submits with its exact name', () async {
      for (final testType in kWebNarrativeTests) {
        final p = ResultEntryProvider(repo)..setNarrativeTest(testType);
        p.setFindings('As reported.');
        expect(await p.submitNarrativeLabResult(patientId: 'p1'), isTrue,
            reason: '$testType should submit');
        expect(repo.lastTestName, testType);
      }
      expect(repo.freeTextCalls, kWebNarrativeTests.length);
    });

    test('no narrative selection is refused', () async {
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(repo.freeTextCalls, 0);
      expect(provider.errorMessage, 'Select a laboratory test.');
    });

    test('setNarrativeTest ignores names outside the narrative catalog', () {
      provider.setNarrativeTest('Cholesterol');
      expect(provider.narrativeTest, isNull);
      provider.setNarrativeTest('Lipid Profile');
      expect(provider.narrativeTest, isNull);
      provider.setNarrativeTest('UrinalysisX');
      expect(provider.narrativeTest, isNull);
    });

    test('empty or whitespace findings are refused', () async {
      provider.setNarrativeTest('Fecalysis');
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(provider.errorMessage, 'Findings are required.');
      provider.setFindings('    \n  ');
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(repo.freeTextCalls, 0);
    });

    test('overlong findings are refused', () async {
      provider.setNarrativeTest('Fecalysis');
      provider.setFindings('x' * (kLabNarrativeMaxLength + 1));
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(provider.errorMessage, contains('5000'));
      expect(repo.freeTextCalls, 0);
    });

    test('overlong impression is refused', () async {
      provider.setNarrativeTest('Fecalysis');
      provider.setFindings('ok');
      provider.setImpression('y' * (kLabNarrativeMaxLength + 1));
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(provider.errorMessage, contains('5000'));
      expect(repo.freeTextCalls, 0);
    });

    test('exactly 5000 characters in both fields is accepted', () async {
      provider.setNarrativeTest('Fecalysis');
      provider.setFindings('x' * kLabNarrativeMaxLength);
      provider.setImpression('y' * kLabNarrativeMaxLength);
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isTrue);
      expect(repo.freeTextCalls, 1);
    });

    test('whitespace impression reaches the repository trimmed and empty', () async {
      provider.setNarrativeTest('Blood Urea Nitrogen (BUN)');
      provider.setFindings('  within normal limits  ');
      provider.setImpression('   ');
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isTrue);
      expect(repo.lastFindings, 'within normal limits');
      expect(repo.lastImpression, '');
    });

    test('queue completion warning is surfaced without failing the save', () async {
      repo.throwQueueCompletion = true;
      provider.setNarrativeTest('SGOT / AST');
      provider.setFindings('ok');
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isTrue);
      expect(provider.queueCompletionWarning, QueueCompletionFailure.message);
    });

    test('selecting a structured group clears the narrative selection and vice versa',
        () {
      provider.setNarrativeTest('Urinalysis');
      expect(provider.isNarrativeSelection, isTrue);
      provider.setLabGroup('Complete Blood Count (CBC)');
      expect(provider.isNarrativeSelection, isFalse);
      expect(provider.currentLabSelection, 'Complete Blood Count (CBC)');
      provider.setNarrativeTest('Lipid Profile (narrative)');
      expect(provider.isNarrativeSelection, isTrue);
      expect(provider.currentLabSelection, 'Lipid Profile (narrative)');
    });

    test('non-laboratory free-text still requires an impression', () async {
      provider.setFindings('Lungs are clear.');
      provider.setImpression('   ');
      expect(await provider.submitFreeTextResult(patientId: 'p1', testName: 'Chest X-Ray'),
          isFalse);
      expect(repo.freeTextCalls, 0);
      expect(
          provider.errorMessage, 'All fields (Test Name, Findings, Impression) are required.');
    });
  });

  group('Narrative selection state transitions (provider)', () {
    late _CapturingRepository repo;
    late ResultEntryProvider provider;

    setUp(() {
      repo = _CapturingRepository();
      provider = ResultEntryProvider(repo);
    });

    test('changing to a different narrative test clears findings and impression', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');
      provider.setImpression('Impression for A.');

      provider.setNarrativeTest('Fecalysis');

      expect(provider.findings, isEmpty,
          reason: 'a changed test must not carry previous clinical answers');
      expect(provider.impression, isEmpty);
    });

    test('switching to a structured group clears findings and impression', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');
      provider.setImpression('Impression for A.');

      provider.setLabGroup('Complete Blood Count (CBC)');

      expect(provider.findings, isEmpty);
      expect(provider.impression, isEmpty);
    });

    test('reselecting the same narrative test preserves unfinished input', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Partial findings');
      provider.setImpression('Partial impression');

      provider.setNarrativeTest('Urinalysis'); // same test: no state change

      expect(provider.findings, 'Partial findings');
      expect(provider.impression, 'Partial impression');
    });

    test('narrative A -> CBC -> narrative B cannot submit A\u2019s answers under B', () async {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');
      provider.setImpression('Impression for A.');

      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setNarrativeTest('Fecalysis');

      // Findings are required again for the new test; nothing may be posted.
      expect(await provider.submitNarrativeLabResult(patientId: 'p1'), isFalse);
      expect(repo.freeTextCalls, 0);
      expect(provider.errorMessage, 'Findings are required.');
    });

    test('notes survive a test change (notes are shared, not per-test)', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');
      provider.setNotes('Shared note.');

      provider.setNarrativeTest('Fecalysis');

      expect(provider.notes, 'Shared note.');
    });

    test('structured OCR autofill while a narrative test is active ends in a consistent structured state', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');
      provider.setImpression('Impression for A.');

      final applied = provider.applyOcrAutofill(
        panel: 'Renal Function',
        values: const {'Creatinine': ' 1.15 '},
      );

      expect(applied, isTrue);
      expect(provider.isNarrativeSelection, isFalse,
          reason: 'a structured OCR apply must not leave a narrative selection active');
      expect(provider.currentLabSelection, 'Renal Function');
      expect(provider.parameterValues, {'Creatinine': '1.15'});
      expect(provider.hasOcrAutofill, isTrue);
      expect(provider.findings, isEmpty);
      expect(provider.impression, isEmpty);
    });

    test('failed structured OCR autofill leaves the narrative selection untouched', () {
      provider.setNarrativeTest('Urinalysis');
      provider.setFindings('Findings for A.');

      final applied = provider.applyOcrAutofill(panel: null, values: const {});

      expect(applied, isFalse);
      expect(provider.narrativeTest, 'Urinalysis');
      expect(provider.findings, 'Findings for A.');
      expect(provider.errorMessage, 'No values extracted, enter manually.');
    });
  });

  group('Requested-test catalog coverage (web CLINIC_TEST_CATALOG sync)', () {
    test('mobile clinic test catalog matches the web catalog ids and labels', () {
      final mobile = {
        for (final t in clinicTestCatalog) t.id: t.label,
      };
      expect(mobile, kWebClinicCatalog);
    });

    test('every web-requestable laboratory test has a recording path offered by the mobile entry form', () {
      final offered = {...kLabTestGroups.keys, ...kLabNarrativeTests};
      for (final entry in kWebLabRecordingTargets.entries) {
        expect(offered, contains(entry.value),
            reason: '${entry.key} records as "${entry.value}", which the mobile lab form must offer');
      }
      // Every catalog laboratory entry is covered by the recording map, so a
      // new requestable lab test cannot be added without a mobile path.
      const nonLab = {'chest_xray', 'ecg', 'ultrasound'};
      final labCatalogIds = kWebClinicCatalog.keys.where((id) => !nonLab.contains(id));
      expect(kWebLabRecordingTargets.keys.toSet(), labCatalogIds.toSet());
    });

    test('every narrative test is requested by some catalog entry', () {
      final requestedNarrative = kWebLabRecordingTargets.values
          .where(kLabNarrativeTests.contains)
          .toSet();
      expect(requestedNarrative, kLabNarrativeTests.toSet());
    });

    test('catalog laboratory labels distinguish the two lipid profile targets', () {
      // The catalog request "Lipid Profile" records as the narrative test;
      // only total cholesterol uses the structured panel.
      expect(kWebLabRecordingTargets['lipid_profile'], 'Lipid Profile (narrative)');
      expect(kWebLabRecordingTargets['creatinine'], 'Renal Function');
      expect(kLabTestGroups['Lipid Profile'], ['Cholesterol']);
    });
  });

  group('Narrative entry screen (widget)', () {
    late _CapturingRepository repo;
    late _MockAuthProvider auth;

    setUp(() {
      repo = _CapturingRepository();
      auth = _MockAuthProvider();
    });

    Future<void> pumpScreen(
      WidgetTester tester, {
      String department = 'laboratory',
      LabValueExtractionService? extractionService,
    }) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(
            path: '/entry',
            builder: (_, _) => ResultEntryScreen(
              patientId: 'patient-123',
              repo: repo,
              departmentOverride: department,
              extractionService: extractionService,
              imagePathPicker: () async => 'dummy.jpg',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      router.push('/entry');
      await tester.pumpAndSettle();
    }

    Future<void> selectNarrativeTest(WidgetTester tester, String name) async {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('dropdown offers all six narrative tests plus the four groups',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      for (final name in [...kWebNarrativeTests, ...kLabTestGroups.keys]) {
        // The currently selected group is rendered both in the closed button
        // and the open menu, so allow one-or-more matches.
        expect(find.text(name), findsWidgets, reason: '$name should be selectable');
      }
      await tester.tap(find.text('Urinalysis'));
      await tester.pumpAndSettle();

      // Narrative mode: narrative fields only, no structured inputs or OCR fill.
      expect(find.byKey(const Key('narrative_findings_input')), findsOneWidget);
      expect(find.byKey(const Key('narrative_impression_input')), findsOneWidget);
      expect(find.byKey(const Key('param_input_Hemoglobin')), findsNothing);
      expect(find.byKey(const Key('extract_lab_values_button')), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('narrative_findings_input')))
              .maxLength,
          5000);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('narrative_impression_input')))
              .maxLength,
          5000);

      // Switching back restores the structured form.
      await selectNarrativeTest(tester, 'Complete Blood Count (CBC)');
      expect(find.byKey(const Key('narrative_findings_input')), findsNothing);
      expect(find.byKey(const Key('param_input_Hemoglobin')), findsOneWidget);
      expect(find.byKey(const Key('extract_lab_values_button')), findsOneWidget);
    });

    testWidgets('narrative save with Findings only submits and shows success',
        (tester) async {
      await pumpScreen(tester);
      await selectNarrativeTest(tester, 'Fecalysis');

      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'No ova or parasites seen.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(repo.freeTextCalls, 1);
      expect(repo.lastPatientId, 'patient-123');
      expect(repo.lastTestName, 'Fecalysis');
      expect(repo.lastFindings, 'No ova or parasites seen.');
      expect(repo.lastImpression, '');
      // Successful submit pops back to the previous route.
      expect(find.byKey(const Key('submit_result_btn')), findsNothing);
    });

    testWidgets('empty narrative Findings is refused before any write', (tester) async {
      await pumpScreen(tester);
      await selectNarrativeTest(tester, 'Blood Urea Nitrogen (BUN)');

      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(repo.freeTextCalls, 0);
      expect(find.text('Findings are required.'), findsOneWidget);
    });

    testWidgets(
        'switching to a different narrative test blanks the fields and cannot save A\u2019s answers under B',
        (tester) async {
      await pumpScreen(tester);
      await selectNarrativeTest(tester, 'Urinalysis');
      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Findings for A.');
      await tester.enterText(
          find.byKey(const Key('narrative_impression_input')), 'Impression for A.');
      await tester.pumpAndSettle();

      await selectNarrativeTest(tester, 'Fecalysis');

      // Visible field state always agrees with the provider: blank after a
      // changed test.
      expect(find.text('Findings for A.'), findsNothing);
      expect(find.text('Impression for A.'), findsNothing);

      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(repo.freeTextCalls, 0,
          reason: 'a changed test must never post the previous test answers');
      expect(find.text('Findings are required.'), findsOneWidget);

      // Correct new input for B posts B.
      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Findings for B.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(repo.freeTextCalls, 1);
      expect(repo.lastTestName, 'Fecalysis');
      expect(repo.lastFindings, 'Findings for B.');
      expect(repo.lastImpression, '');
    });

    testWidgets(
        'narrative A -> CBC -> narrative B shows blank fields and cannot post hidden old findings',
        (tester) async {
      await pumpScreen(tester);
      await selectNarrativeTest(tester, 'Urinalysis');
      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Findings for A.');
      await tester.enterText(
          find.byKey(const Key('narrative_impression_input')), 'Impression for A.');
      await tester.pumpAndSettle();

      await selectNarrativeTest(tester, 'Complete Blood Count (CBC)');
      expect(find.byKey(const Key('narrative_findings_input')), findsNothing);
      await selectNarrativeTest(tester, 'Fecalysis');

      // Fields are recreated blank; the provider must not hide A's answers.
      expect(find.text('Findings for A.'), findsNothing);
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();
      expect(repo.freeTextCalls, 0,
          reason: 'a blank new test must not save previous findings');
      expect(find.text('Findings are required.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Findings for B.');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();

      expect(repo.freeTextCalls, 1);
      expect(repo.lastTestName, 'Fecalysis');
      expect(repo.lastFindings, 'Findings for B.');
    });

    testWidgets('reselecting the same narrative test preserves unfinished input',
        (tester) async {
      await pumpScreen(tester);
      await selectNarrativeTest(tester, 'Urinalysis');
      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Partial findings');
      await tester.pumpAndSettle();

      await selectNarrativeTest(tester, 'Urinalysis'); // same test again

      expect(find.text('Partial findings'), findsOneWidget);
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();
      expect(repo.freeTextCalls, 1);
      expect(repo.lastTestName, 'Urinalysis');
      expect(repo.lastFindings, 'Partial findings');
    });

    testWidgets(
        'a stale structured OCR response landing after a narrative selection leaves a consistent structured state',
        (tester) async {
      final service = _DelayedExtractionService();
      await pumpScreen(tester, extractionService: service);

      // Extraction starts in structured mode; the user switches to a
      // narrative test while the OCR response is still in flight. Fixed pumps
      // here: the in-flight indicator animates, so pumpAndSettle never ends.
      await tester.tap(find.byKey(const Key('extract_lab_values_button')));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Urinalysis').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
          find.byKey(const Key('narrative_findings_input')), 'Findings for A.');
      await tester.pump(const Duration(milliseconds: 300));

      service.completer.complete(const LabValueExtractionResult(
        panel: 'Renal Function',
        values: {'Creatinine': '1.15'},
        tokensUsed: 10,
      ));
      await tester.pumpAndSettle();

      // The structured apply must end the narrative selection: no narrative
      // fields, structured inputs present with the extracted value.
      expect(find.byKey(const Key('narrative_findings_input')), findsNothing);
      expect(find.text('Findings for A.'), findsNothing);
      expect(find.byKey(const Key('param_input_Creatinine')), findsOneWidget);
      final creatinine = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('param_input_Creatinine')),
        matching: find.byType(TextField),
      ));
      expect(creatinine.controller?.text, '1.15');
      expect(find.text('Renal Function'), findsWidgets);

      // The structured save path is what runs, and it posts structured rows.
      await tester.enterText(find.byKey(const Key('param_input_Creatinine')), '1.0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit_result_btn')));
      await tester.pumpAndSettle();
      expect(repo.freeTextCalls, 0);
      expect(repo.labCalls, 1);
      expect(repo.lastRows?.single.testName, 'Creatinine');
    });
  });
}
