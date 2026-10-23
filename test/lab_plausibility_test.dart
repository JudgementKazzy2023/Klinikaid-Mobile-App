import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/features/specialist/data/specialist_repository.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/domain/lab_reference_ranges.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';

// Web migration 40 (Setsuna-guwah/KlinikAid#212, live 2026-10-23): the DB refuses
// implausible lab values with PostgREST 400, code 23514, and web's sentence.
const _serverRefusal =
    'Hemoglobin: 99 g/dL is outside the possible range (1–25 g/dL). Check the value and its unit.';

class _FakeAuth extends GoTrueClient {
  _FakeAuth() : super(autoRefreshToken: false);

  @override
  User? get currentUser => User(
        id: 'recorder-uuid',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );
}

/// Real Supabase transport whose every insert is refused like migration 40.
class _RefusingClient extends SupabaseClient {
  _RefusingClient()
      : super(
          'https://example.supabase.co',
          'fake',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async => http.Response(
                jsonEncode({'code': '23514', 'message': _serverRefusal, 'details': null, 'hint': null}),
                400,
                request: request,
                headers: {'content-type': 'application/json'},
              )),
        );

  @override
  GoTrueClient get auth => _FakeAuth();
}

class _RecordingRepo extends DepartmentRepository {
  List<LabResultRow>? rows;

  @override
  String? get currentUserId => 'recorder';

  @override
  Future<void> submitLabResults({
    required String patientId,
    required List<LabResultRow> rows,
  }) async {
    this.rows = rows;
  }
}

void main() {
  test('plausible bounds match web constants.ts LAB_REFERENCE_RANGES', () {
    final bounds = {
      for (final r in kLabReferenceRanges) r.parameter: [r.plausibleMin, r.plausibleMax],
    };
    expect(bounds, {
      'Hemoglobin': [1, 25],
      'White Blood Cells (WBC)': [0, 1000],
      'Platelets': [0, 5000],
      'Fasting Blood Sugar (FBS)': [5, 3000],
      'Creatinine': [0.1, 40],
      'Cholesterol': [20, 2000],
    });
  });

  test('bounds are inclusive; outside them is refused with the unit', () {
    final hb = kLabReferenceRanges.firstWhere((r) => r.parameter == 'Hemoglobin');
    expect(labPlausibilityError(hb, 1), isNull);
    expect(labPlausibilityError(hb, 25), isNull);
    expect(
      labPlausibilityError(hb, 30),
      'Hemoglobin: 30 g/dL is outside the possible range (1–25 g/dL). Check the value and its unit.',
    );
    expect(labPlausibilityError(hb, 0.5), isNotNull);
  });

  group('department result entry', () {
    late _RecordingRepo repo;
    late ResultEntryProvider provider;

    setUp(() {
      repo = _RecordingRepo();
      provider = ResultEntryProvider(repo);
    });

    Future<bool> submitHemoglobin(String value) {
      provider.setLabGroup('Complete Blood Count (CBC)');
      provider.setParameterValue('Hemoglobin', value);
      return provider.submitLabResults(patientId: 'p1', gender: 'male');
    }

    test('an impossible value is refused before any write', () async {
      expect(await submitHemoglobin('30'), isFalse);
      expect(provider.errorMessage, contains('outside the possible range'));
      expect(repo.rows, isNull);
    });

    test('an abnormal but plausible value is saved and flagged', () async {
      expect(await submitHemoglobin('20'), isTrue);
      expect(repo.rows!.single.isFlagged, isTrue);
    });

    test('the value is stored as entered, like web', () async {
      expect(await submitHemoglobin('14'), isTrue);
      expect(repo.rows!.single.testValue, '14');
    });

    test('the refusal message echoes the value as entered, like web', () async {
      expect(await submitHemoglobin('30.0'), isFalse);
      expect(provider.errorMessage, startsWith('Hemoglobin: 30.0 g/dL is outside'));
    });

    test('exponent, non-numeric and trailing-dot forms are refused', () async {
      for (final bad in ['1e1', 'NaN', 'Infinity', '5.']) {
        expect(await submitHemoglobin(bad), isFalse, reason: bad);
        expect(repo.rows, isNull, reason: bad);
      }
    });
  });

  group('server refusal (23514) shows the server sentence', () {
    test('department save, through the real repository', () async {
      final repo = DepartmentRepository(client: _RefusingClient())
        ..adminDepartmentOverride = 'laboratory';
      final provider = ResultEntryProvider(repo)
        ..setLabGroup('Complete Blood Count (CBC)')
        ..setParameterValue('Hemoglobin', '14');

      expect(await provider.submitLabResults(patientId: 'p1', gender: 'male'), isFalse);
      expect(provider.errorMessage, _serverRefusal);
    });

    test('specialist save, through the real repository', () async {
      final repo = SpecialistRepository(client: _RefusingClient());
      // The specialist provider shows `e.toString()` of what the repository throws.
      await expectLater(
        repo.submitRecord(
          specialistPatientId: 'sp1',
          testType: 'Complete Blood Count (CBC)',
          rows: [SpecialistRecordRow(testName: 'Hemoglobin', testValue: '14', isFlagged: false)],
        ),
        throwsA(predicate((e) => e.toString() == _serverRefusal)),
      );
    });
  });
}
