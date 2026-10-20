import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/staff/data/repositories/staff_queue_repository.dart';

/// Verification note — integration acceptance gap (not RLS proof).
///
/// The original live test in this file signed up throwaway patient, lab-staff
/// and specialist accounts against the shared backend, inserted patient and
/// department-record rows, then asserted that a signed-in specialist could
/// find the patient by name and retrieve the cross-department timeline. That
/// flow relied on real signups, `user_metadata` role assignment and uncleaned
/// fixtures, so it is unsafe in shared environments and is replaced here by
/// deterministic HTTP-contract and model-mapping tests of the same legacy
/// [StaffQueueRepository] calls (`searchPatients`, `getDepartmentRecordsForPatient`).
///
/// Still unproven (integration acceptance gap): end-to-end role-gated signup,
/// server-side role assignment, and that RLS actually scopes which patient
/// rows and department records a specialist session can read on a deployed
/// backend. These tests intercept every request in-process, make no outbound
/// calls, and prove no RLS behavior.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient client;
  late StaffQueueRepository repo;
  final requests = <http.Request>[];
  Object responseBody = <dynamic>[];
  int responseStatus = 200;

  http.Response respond(http.Request request) => http.Response(
        jsonEncode(responseBody),
        responseStatus,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  setUp(() {
    requests.clear();
    responseBody = <dynamic>[];
    responseStatus = 200;
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    SupabaseService.mockClient = client;
    repo = StaffQueueRepository();
  });

  tearDown(() async {
    SupabaseService.mockClient = null;
    await client.dispose();
  });

  group('StaffQueueRepository.searchPatients (legacy)', () {
    test('issues the name-search PostgREST contract and maps rows in server order', () async {
      responseBody = [
        {
          'id': 'patient-row-1',
          'profile_id': 'profile-1',
          'first_name': 'SpecTest',
          'last_name': 'Aldrin',
          'date_of_birth': '1988-08-08',
          'gender': 'female',
          'contact_number': '09776655443',
          'address': 'Quezon City, PH',
          'created_at': '2026-01-01T08:00:00Z',
          'updated_at': '2026-01-01T08:00:00Z',
        },
        {
          'id': 'patient-row-2',
          'profile_id': 'profile-2',
          'first_name': 'Ana',
          'last_name': 'SpecTest-Cruz',
          'date_of_birth': '1991-02-02',
          'gender': 'male',
          'contact_number': '09123456789',
          'address': 'Manila, PH',
          'created_at': '2026-01-02T08:00:00Z',
          'updated_at': '2026-01-02T08:00:00Z',
        },
      ];

      final results = await repo.searchPatients('SpecTest');

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/patients'));
      expect(request.headers['apikey'], 'fake-key');
      expect(request.url.queryParameters['select'], '*');
      expect(
        request.url.queryParameters['or'],
        '(first_name.ilike.%SpecTest%,last_name.ilike.%SpecTest%)',
      );
      expect(request.url.queryParameters['order'], 'last_name.asc.nullslast');

      expect(results, hasLength(2));
      // Original flow intent: the created patient is discoverable by name search.
      expect(results.any((p) => p.id == 'patient-row-1'), isTrue);
      // Rows are mapped to the Patient model in server (last_name asc) order.
      expect(results.map((p) => p.id).toList(), ['patient-row-1', 'patient-row-2']);
      expect(results.first.fullName, 'SpecTest Aldrin');
      expect(results.first.gender, Gender.female);
      expect(results.first.dateOfBirth, DateTime(1988, 8, 8));
      expect(results.last.fullName, 'Ana SpecTest-Cruz');
    });

    test('surfaces a denied read as a permission failure, not an empty result', () async {
      responseStatus = 403;
      responseBody = {'message': 'insufficient privilege', 'code': '42501'};

      await expectLater(
        repo.searchPatients('SpecTest'),
        throwsA(
          isA<DatabaseFailure>().having(
            (f) => f.message,
            'message',
            contains('Access denied'),
          ),
        ),
      );
    });
  });

  group('StaffQueueRepository.getDepartmentRecordsForPatient (legacy)', () {
    test('issues the timeline PostgREST contract and maps laboratory history', () async {
      responseBody = [
        {
          'id': 'lab-record-1',
          'patient_id': 'patient-record-1',
          'recorder_id': 'staff-uuid',
          'department': 'laboratory',
          'test_type': 'Lipid Profile',
          // Legacy row shape as inserted by the original flow: flat columns
          // with is_flagged, plus the joined recorder profile.
          'test_name': 'Cholesterol',
          'test_value': '210',
          'unit': 'mg/dL',
          'is_flagged': true,
          'created_at': '2026-01-03T09:00:00Z',
          'updated_at': '2026-01-03T09:00:00Z',
          'recorder': {
            'id': 'staff-uuid',
            'full_name': 'Spec Lab Tech',
            'role': 'department_staff',
            'department': 'laboratory',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        },
      ];

      final timeline = await repo.getDepartmentRecordsForPatient('patient-record-1');

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/department_records'));
      expect(request.url.queryParameters['select'], '*,recorder:profiles(*)');
      expect(request.url.queryParameters['patient_id'], 'eq.patient-record-1');
      expect(request.url.queryParameters['order'], 'created_at.desc.nullslast');

      // Original flow intent: the specialist timeline contains the lab record,
      // attributed to the laboratory department with its stored values.
      final record = timeline.single;
      expect(record.id, 'lab-record-1');
      expect(record.department, Department.laboratory);
      expect(record.testResults['test_value']?.toString(), '210');
      expect(record.referenceRangeStatus, ReferenceRangeStatus.flagged);
      expect(record.recorder?.fullName, 'Spec Lab Tech');
    });
  });
}
