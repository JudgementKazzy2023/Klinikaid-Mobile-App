import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';

/// Approve and reject act only on a document that is still pending, and only
/// report success when the update returned the row it changed.
void main() {
  late List<http.Request> requests;
  late bool documentStillPending;
  // What the pre-routing status read sees (may differ from the update: race).
  late String statusSeenBeforeRouting;

  SupabaseClient client() => SupabaseClient(
        'https://example.supabase.co',
        'fake',
        httpClient: MockClient((request) async {
          requests.add(request);
          final json = {'content-type': 'application/json'};
          if (request.method == 'GET') {
            final row = {'status': statusSeenBeforeRouting};
            final object = request.headers['accept']?.contains('object') ?? false;
            return http.Response(jsonEncode(object ? row : [row]), 200,
                request: request, headers: json);
          }
          if (request.url.path.endsWith('/rpc/triage_patient')) {
            return http.Response('{"id":1}', 200, request: request, headers: json);
          }
          // PostgREST answers .single() with no matching row like this.
          return documentStillPending
              ? http.Response('{"id":"doc"}', 200, request: request, headers: json)
              : http.Response(
                  jsonEncode({
                    'code': 'PGRST116',
                    'message': 'JSON object requested, multiple (or no) rows returned',
                    'details': 'The result contains 0 rows',
                    'hint': null,
                  }),
                  406,
                  request: request,
                  headers: json);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

  setUp(() {
    requests = [];
    documentStillPending = true;
    statusSeenBeforeRouting = 'pending';
  });

  Future<void> approve() => ReceptionRepository(client: client()).approveAndRoute(
        documentId: 'doc',
        patientId: 'patient',
        department: 'laboratory',
        priority: 'normal',
      );
  bool routed() => requests.any((r) => r.url.path.endsWith('/rpc/triage_patient'));

  Map<String, String> documentUpdate() => requests
      .singleWhere((r) => r.method == 'PATCH' && r.url.path == '/rest/v1/documents')
      .url
      .queryParameters;

  test('reject matches only a pending document and asks for the changed row', () async {
    await ReceptionRepository(client: client())
        .rejectDocument(documentId: 'doc', reason: 'Blurred image, please retake.');
    expect(documentUpdate(), {'id': 'eq.doc', 'status': 'eq.pending', 'select': 'id'});
  });

  test('reject of a document that is no longer pending is reported, not success', () async {
    documentStillPending = false;
    await expectLater(
      ReceptionRepository(client: client())
          .rejectDocument(documentId: 'doc', reason: 'Blurred image, please retake.'),
      throwsA(isA<DatabaseFailure>().having(
          (f) => f.message, 'message', contains('no longer pending'))),
    );
  });

  test('approval of a pending document routes, then updates only if still pending', () async {
    await approve();
    expect(routed(), isTrue);
    expect(documentUpdate(), {'id': 'eq.doc', 'status': 'eq.pending', 'select': 'id'});
  });

  test('an already decided document is refused before the patient is routed', () async {
    statusSeenBeforeRouting = 'rejected';
    await expectLater(approve(), throwsA(isA<DatabaseFailure>().having(
        (f) => f.message, 'message', contains('no longer pending'))));
    expect(routed(), isFalse);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
  });

  test('a decision made between the read and the update gets a plain message', () async {
    documentStillPending = false;
    await expectLater(approve(), throwsA(isA<DatabaseFailure>().having(
        (f) => f.message, 'message', allOf(
          contains('no longer pending, so it was not approved'),
          isNot(contains('JSON object requested'))))));
    expect(routed(), isTrue);
  });
}
