// Narrative laboratory result entry (mobile issue15 / roadmap9 batch ST02).
//
// Contract source: web src/lib/constants.ts LAB_NARRATIVE_TESTS /
// LAB_NARRATIVE_FIELDS / LAB_NARRATIVE_MAX_LENGTH and
// src/lib/records/validateLabResult.ts validateLabNarrative. All HTTP here is
// mocked; no live network or fixtures.
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
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';
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
          'https://example.supabase.co',
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
        url: 'https://example.supabase.co',
        anonKey: 'fake-anon-key',
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
          return http.Response('', 204, request: request);
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

  group('Narrative entry screen (widget)', () {
    late _CapturingRepository repo;
    late _MockAuthProvider auth;

    setUp(() {
      repo = _CapturingRepository();
      auth = _MockAuthProvider();
    });

    Future<void> pumpScreen(WidgetTester tester, {String department = 'laboratory'}) async {
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
  });
}
