import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// Mock the real Supabase HTTP transport; no backend fixtures or live requests.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late ReceptionRepository repository;
  late List<http.Request> requests;
  // The pre-routing status read is logged apart, so counts describe writes.
  late List<String> log;
  var rpcStatus = 200;
  var rpcBody = '{"id":"queue-1"}';
  var documentStatus = 200;
  var documentBody = '{"id":"document-1"}';

  setUp(() {
    requests = [];
    log = [];
    rpcStatus = 200;
    rpcBody = '{"id":"queue-1"}';
    documentStatus = 200;
    documentBody = '{"id":"document-1"}';
    client = SupabaseClient(
      'https://example.invalid',
      'placeholder-anon-key',
      // Represents the signed-in staff session's bearer, never a service key.
      accessToken: () async => 'mock-staff-access-token',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(
          request.headers['Authorization'],
          'Bearer mock-staff-access-token',
        );
        log.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          expect(request.url.path, '/rest/v1/documents');
          expect(request.url.queryParameters['id'], 'eq.document-1');
          final row = {'status': 'pending'};
          final object = request.headers['accept']?.contains('object') ?? false;
          return http.Response(
            jsonEncode(object ? row : [row]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(request);
        if (request.url.path == '/rest/v1/rpc/triage_patient') {
          expect(request.method, 'POST');
          return http.Response(
            rpcBody,
            rpcStatus,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.url.path, '/rest/v1/documents');
        expect(request.method, 'PATCH');
        return http.Response(
          documentBody,
          documentStatus,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repository = ReceptionRepository(client: client);
  });

  tearDown(() async => client.dispose());

  Future<void> route({
    String priority = 'routine',
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? notes,
  }) => repository.approveAndRoute(
    documentId: 'document-1',
    patientId: 'patient-1',
    department: 'laboratory',
    priority: priority,
    bloodPressure: bloodPressure,
    weightKg: weightKg,
    temperatureC: temperatureC,
    triageNotes: notes,
  );

  test(
    'one authenticated RPC with exact args, then document approval',
    () async {
      await route(
        priority: 'urgent',
        bloodPressure: ' 120/80 ',
        weightKg: 72.5,
        temperatureC: 36.7,
        notes: ' headache ',
      );
      expect(requests, hasLength(2));
      expect(jsonDecode(requests.first.body), {
        'p_patient_id': 'patient-1',
        'p_department': 'laboratory',
        'p_priority_level': 'urgent',
        'p_vitals': {
          'blood_pressure': '120/80',
          'weight_kg': 72.5,
          'temperature_c': 36.7,
        },
        'p_notes': 'headache',
      });
      expect(jsonDecode(requests.last.body), {'status': 'approved'});
      expect(requests.last.url.queryParameters['id'], 'eq.document-1');
      expect(requests.last.url.queryParameters['select'], 'id');
      expect(requests.last.url.queryParameters['status'], 'eq.pending');
      expect(log, [
        'GET /rest/v1/documents',
        'POST /rest/v1/rpc/triage_patient',
        'PATCH /rest/v1/documents',
      ]);
    },
  );

  test(
    'optional vitals stay absent; blank notes become empty; priorities pass through',
    () async {
      for (final priority in ['routine', 'urgent', 'emergency']) {
        await route(priority: priority, bloodPressure: '  ', notes: '  ');
        expect(jsonDecode(requests[requests.length - 2].body), {
          'p_patient_id': 'patient-1',
          'p_department': 'laboratory',
          'p_priority_level': priority,
          'p_vitals': <String, dynamic>{},
          'p_notes': '',
        });
      }
      expect(requests, hasLength(6));
    },
  );

  test('null notes and vitals use empty values', () async {
    await route();
    final args = jsonDecode(requests.first.body);
    expect(args['p_vitals'], isEmpty);
    expect(args['p_notes'], '');
  });

  test(
    'permission or missing RPC failure never approves or falls back',
    () async {
      for (final error in [
        {'code': '42501', 'message': 'not permitted'},
        {'code': 'PGRST202', 'message': 'triage_patient was not found'},
      ]) {
        requests.clear();
        rpcStatus = 403;
        rpcBody = jsonEncode(error);
        await expectLater(
          route(),
          throwsA(
            isA<DatabaseFailure>().having(
              (e) => e.message,
              'message',
              contains(
                error['code'] == '42501'
                    ? 'Access denied'
                    : 'triage_patient was not found',
              ),
            ),
          ),
        );
        expect(requests, hasLength(1));
      }
    },
  );

  test('PT409 preserves useful open queue error, never approves', () async {
    rpcStatus = 409;
    rpcBody = jsonEncode({
      'code': 'PT409',
      'message': 'patient already has an open queue entry',
      'details': 'imaging',
    });
    await expectLater(
      route(),
      throwsA(
        isA<DatabaseFailure>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('open queue entry in Imaging'),
            contains('Resolve the existing entry'),
          ),
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('PT409 without a known department remains actionable', () async {
    rpcStatus = 409;
    rpcBody =
        '{"code":"PT409","message":"patient already has an open queue entry"}';
    await expectLater(
      route(),
      throwsA(
        isA<DatabaseFailure>().having(
          (e) => e.message,
          'message',
          contains('Resolve the existing entry'),
        ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('RPC response with no row does not approve', () async {
    rpcStatus = 406;
    rpcBody = '{"code":"PGRST116","message":"No rows returned"}';
    await expectLater(route(), throwsA(isA<DatabaseFailure>()));
    expect(requests, hasLength(1));
  });

  test(
    'document failure reports partial success; repeat is blocked by open guard',
    () async {
      documentStatus = 403;
      documentBody = '{"code":"42501","message":"not permitted"}';
      await expectLater(
        route(),
        throwsA(
          isA<DatabaseFailure>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Patient was routed'),
              contains('approval could not be confirmed'),
              contains('do not route the patient again'),
            ),
          ),
        ),
      );
      expect(requests, hasLength(2));
      rpcStatus = 409;
      rpcBody =
          '{"code":"PT409","message":"patient already has an open queue entry","details":"laboratory"}';
      await expectLater(
        route(),
        throwsA(
          isA<DatabaseFailure>().having(
            (e) => e.message,
            'message',
            contains('open queue entry in Laboratory'),
          ),
        ),
      );
      expect(requests, hasLength(3));
      expect(requests.where((r) => r.method == 'PATCH'), hasLength(1));
    },
  );

  test('silent document RLS no-op is reported as partial completion', () async {
    documentStatus = 406;
    documentBody = '{"code":"PGRST116","message":"No rows returned"}';
    await expectLater(
      route(),
      throwsA(
        isA<DatabaseFailure>().having(
          (e) => e.message,
          'message',
          contains('Patient was routed'),
        ),
      ),
    );
    expect(requests, hasLength(2));
  });
}
