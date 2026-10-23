import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
import 'package:klinikaid_mobile/features/patient/templates/data/templates_repository.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';

// Test subclasses exercise dormant code without changing production containment.
class HttpRepository extends TemplatesRepository {
  final TemplateSubmissionApi api;
  HttpRepository(SupabaseClient client) : api = TemplateSubmissionApi(client);
  @override
  Future<TemplateSubmissionResult> submitTemplateDocument({
    String? requestId,
    required String templateId,
    Map<String, String>? fields,
    String? patientId,
    String? uploaderId,
    String? templateName,
    Map<String, dynamic>? extractedMetadata,
  }) => api.submit(
    requestId: requestId!,
    templateId: templateId,
    fields: fields!,
  );
  @override
  Future<TemplateLookup?> lookupTemplateOutcome(String requestId) =>
      api.lookup(requestId);
}

void main() {
  // The adapter is dormant behind containment; these tests drive it directly.
  setUp(() => PatientSubmissionContainment.activeForTesting = false);
  tearDown(() => PatientSubmissionContainment.activeForTesting = true);

  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late TemplatesProvider provider;
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];
  var prechecks = 0;
  const values = {'chief_complaint': 'Synthetic answer'};
  const success = {
    'document_id': 'existing-document',
    'status': 'pending',
    'replayed': false,
  };
  http.Response json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<bool> submit({
    Map<String, String> fields = values,
    String template = 'patient-intake',
  }) => provider.submitTemplate(
    patientId: 'patient-row',
    uploaderId: 'patient-user',
    templateId: template,
    templateName: 'Patient Intake Form',
    formValues: fields,
    patientName: 'Never transmitted',
    dob: '1990-01-01',
    contactNumber: 'Never transmitted',
    address: 'Never transmitted',
  );
  setUp(() async {
    requests.clear();
    prechecks = 0;
    respond = (_) async => json(success, 200);
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
    final jwt =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
        '${base64Url.encode(utf8.encode(jsonEncode({'sub': 'patient-user', 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})))}.fixture';
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': jwt,
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'patient-user',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-23T00:00:00Z',
        },
      }),
    );
    provider = TemplatesProvider(
      repository: HttpRepository(client),
      checkDuplicate: (_, _) async {
        prechecks++;
        return null;
      },
    );
  });
  tearDown(() async {
    provider.dispose();
    await client.dispose();
  });
  test('exact POST body: answers only, patient JWT and UUID v4', () async {
    expect(await submit(), isTrue);
    final request = requests.single;
    expect(request.method.toUpperCase(), 'POST');
    expect(request.url.path, '/functions/v1/patient-document-submission');
    expect(
      request.headers['authorization'],
      'Bearer ${client.auth.currentSession!.accessToken}',
    );
    final body = jsonDecode(request.body) as Map;
    expect(body.keys.toSet(), {'request_id', 'template_id', 'fields'});
    expect(
      body['request_id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(body['template_id'], 'patient-intake');
    expect(body['fields'], values);
    expect(provider.result!.documentId, 'existing-document');
    expect(provider.result!.status, 'pending');
  });
  test('replay succeeds even when advisory sees a duplicate', () async {
    provider.dispose();
    provider = TemplatesProvider(
      repository: HttpRepository(client),
      checkDuplicate: (_, _) async => 'Oct 23, 2026',
    );
    respond = (_) async => json({...success, 'replayed': true}, 200);
    expect(await submit(), isTrue);
    expect(provider.result!.replayed, isTrue);
    expect(provider.errorMessage, isNull);
    expect(requests, hasLength(1));
  });
  const statuses = {
    'UNAUTHENTICATED': 401,
    'EMAIL_NOT_CONFIRMED': 403,
    'CONSENT_REQUIRED': 403,
    'PASSWORD_CHANGE_REQUIRED': 403,
    'PATIENT_ACCOUNT_REQUIRED': 403,
    'NO_PATIENT_RECORD': 403,
    'PROFILE_INACTIVE': 403,
    'SERVER_DATA_INVALID': 500,
    'AGE_REQUIREMENT_NOT_MET': 403,
    'UNKNOWN_TEMPLATE': 400,
    'UNKNOWN_FIELD': 400,
    'FIELD_REQUIRED': 400,
    'FIELD_INVALID': 400,
    'DUPLICATE_PENDING': 409,
    'IDEMPOTENCY_CONFLICT': 409,
    'RECONCILIATION_REQUIRED': 409,
    'SERVER_ERROR': 503,
    'METHOD_NOT_ALLOWED': 405,
  };
  const flows = {
    'UNAUTHENTICATED': TemplateRemediation.signIn,
    'EMAIL_NOT_CONFIRMED': TemplateRemediation.verifyEmail,
    'CONSENT_REQUIRED': TemplateRemediation.consent,
    'PASSWORD_CHANGE_REQUIRED': TemplateRemediation.changePassword,
  };
  for (final entry in statuses.entries) {
    test('${entry.key}: typed response and patient remediation', () async {
      respond = (_) async => json({
        'error_code': entry.key,
        'message': 'Safe server message',
        'field': 'chief_complaint',
        'document_id': 'pending-document',
        'status': 'pending',
      }, entry.value);
      final typed = await TemplateSubmissionApi(client).submit(
        requestId: 'c617cd35-f162-4e33-81fa-b47b1068f43a',
        templateId: 'patient-intake',
        fields: values,
      );
      expect(typed, isA<TemplateSubmissionError>());
      final error = typed as TemplateSubmissionError;
      expect(error.code, entry.key);
      expect(error.field, 'chief_complaint');
      expect(error.documentId, 'pending-document');
      expect(error.status, 'pending');
      requests.clear();
      expect(await submit(), isFalse);
      expect(provider.success, isFalse);
      expect(provider.isLoading, isFalse);
      expect(provider.errorCode, entry.key);
      expect(
        provider.remediation,
        flows[entry.key] ?? TemplateRemediation.none,
      );
      switch (entry.key) {
        case 'FIELD_REQUIRED':
        case 'FIELD_INVALID':
          expect(provider.fieldErrors, {
            'chief_complaint': 'Safe server message',
          });
          expect(provider.canSubmit, isTrue);
        case 'DUPLICATE_PENDING':
          expect(provider.duplicateDocumentId, 'pending-document');
          expect(
            provider.errorMessage,
            'You already have a pending Patient Intake Form',
          );
          expect(provider.canSubmit, isFalse);
        case 'UNKNOWN_TEMPLATE':
        case 'UNKNOWN_FIELD':
        case 'METHOD_NOT_ALLOWED':
          expect(provider.errorMessage, 'This app version is out of date.');
          expect(provider.canSubmit, isFalse);
        case 'IDEMPOTENCY_CONFLICT':
        case 'RECONCILIATION_REQUIRED':
          expect(provider.errorMessage, contains('contact the clinic'));
          expect(provider.canSubmit, isFalse);
          final id = provider.requestId;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(requests, hasLength(1));
          expect(await submit(), isFalse);
          provider.resetState();
          expect(provider.requestId, id);
          expect(provider.canSubmit, isFalse);
          expect(await submit(fields: {'chief_complaint': 'Edited'}), isFalse);
          expect(requests, hasLength(1));
        case 'SERVER_ERROR':
          expect(provider.outcomeUnknown, isTrue);
          expect(
            provider.errorMessage,
            TemplateSubmissionError.unknown.message,
          );
          expect(provider.canSubmit, isTrue);
        default:
          expect(provider.errorMessage, 'Safe server message');
          expect(provider.canSubmit, isFalse);
      }
    });
  }
  bool isStatus(http.Request r) => r.url.path.endsWith('/status');
  List<http.Request> sends() => requests.where((r) => !isStatus(r)).toList();
  List<http.Request> lookups() => requests.where(isStatus).toList();

  for (final failure in ['network', 'timeout']) {
    test(
      '$failure: the next submit asks /status first and never resends blindly',
      () async {
        var submitFails = true;
        var statusUnreachable = true;
        respond = (request) async {
          if (isStatus(request)) {
            if (statusUnreachable) throw const SocketException('offline');
            return json({'state': 'not_found'}, 200);
          }
          if (!submitFails) return json(success, 200);
          if (failure == 'network') {
            throw const SocketException('synthetic offline');
          }
          throw TimeoutException('synthetic timeout');
        };
        expect(await submit(), isFalse);
        expect(provider.errorMessage, TemplateSubmissionError.unknown.message);
        final first = jsonDecode(sends().single.body) as Map;

        // Status unreachable: still unknown, and nothing is sent again.
        expect(await submit(), isFalse);
        expect(provider.outcomeUnknown, isTrue);
        expect(sends(), hasLength(1));
        expect(jsonDecode(lookups().single.body),
            {'request_id': first['request_id']});

        // Server says it never committed: resend under the same id.
        statusUnreachable = false;
        submitFails = false;
        expect(await submit(), isTrue);
        expect(jsonDecode(lookups().last.body),
            {'request_id': first['request_id']});
        expect(jsonDecode(sends().last.body), first);
        expect(prechecks, 1);
      },
    );
  }

  Future<Map> failOnceThenStatus(Map<String, dynamic> status) async {
    respond = (_) async => throw const SocketException('offline');
    expect(await submit(), isFalse);
    final first = jsonDecode(sends().single.body) as Map;
    respond = (request) async =>
        isStatus(request) ? json(status, 200) : json(success, 200);
    return first;
  }

  test('committed earlier: success with that document, nothing resent', () async {
    await failOnceThenStatus(
        {'state': 'committed', 'document_id': 'doc-1', 'status': 'approved'});
    // Edited answers must not become a second submission.
    expect(await submit(fields: {'chief_complaint': 'Edited'}), isTrue);
    expect(provider.result!.documentId, 'doc-1');
    expect(provider.result!.status, 'approved');
    expect(provider.result!.replayed, isTrue);
    expect(sends(), hasLength(1));
  });

  test('withdrawn earlier: a fresh id, never the withdrawn one', () async {
    final first = await failOnceThenStatus({'state': 'withdrawn'});
    expect(await submit(), isTrue);
    final resent = jsonDecode(sends().last.body) as Map;
    expect(resent['request_id'], isNot(first['request_id']));
    expect(resent['fields'], first['fields']);
  });

  test('not found and edited: the edited answers go under their new id', () async {
    final first = await failOnceThenStatus({'state': 'not_found'});
    final edited = {'chief_complaint': 'Edited answer'};
    expect(await submit(fields: edited), isTrue);
    final third = jsonDecode(sends().last.body) as Map;
    expect(third['request_id'], isNot(first['request_id']));
    expect(third['fields'], edited);
  });

  test('a lookup is asked only once per unknown outcome', () async {
    await failOnceThenStatus({'state': 'not_found'});
    expect(await submit(), isTrue);
    expect(await submit(), isFalse); // already succeeded: nothing more
    expect(lookups(), hasLength(1));
  });

  test('editing and reverting still rotates the request ID', () async {
    respond = (_) async => throw const SocketException('offline');
    await submit();
    final originalId = provider.requestId;
    provider.answersChanged({'chief_complaint': 'Edit'});
    provider.answersChanged(values);
    await submit();
    expect(provider.requestId, isNot(originalId));
  });
  test('other is exempt from advisory duplicate lookup', () async {
    expect(await submit(template: 'other'), isTrue);
    expect(prechecks, 0);
  });
  for (final malformed in [
    http.Response('not json', 503),
    http.Response(
      '{"document_id":"doc"}',
      200,
      headers: {'content-type': 'application/json'},
    ),
    http.Response(
      '{"error_code":"NEW_CODE","message":"unknown"}',
      500,
      headers: {'content-type': 'application/json'},
    ),
  ]) {
    test(
      'unrecognized response stays uncertain (${malformed.statusCode}/${malformed.body})',
      () async {
        respond = (_) async => malformed;
        expect(await submit(), isFalse);
        expect(provider.outcomeUnknown, isTrue);
        expect(provider.errorMessage, TemplateSubmissionError.unknown.message);
      },
    );
  }
  test('simultaneous submit actions issue one request', () async {
    final pending = Completer<http.Response>();
    respond = (_) => pending.future;
    final first = submit();
    expect(await submit(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, hasLength(1));
    pending.complete(json(success, 200));
    expect(await first, isTrue);
  });
  test(
    'active containment blocks repository and provider before HTTP or precheck',
    () async {
      PatientSubmissionContainment.activeForTesting = true;
      await expectLater(
        TemplatesRepository(client: client).submitTemplateDocument(
          requestId: 'c617cd35-f162-4e33-81fa-b47b1068f43a',
          templateId: 'patient-intake',
          fields: values,
        ),
        throwsStateError,
      );
      expect(
        () => TemplatesRepository(client: client)
            .lookupTemplateOutcome('c617cd35-f162-4e33-81fa-b47b1068f43a'),
        throwsStateError,
      );
      final contained = TemplatesProvider(
        repository: HttpRepository(client),
        checkDuplicate: (_, _) async =>
            throw StateError('precheck must not run'),
      );
      expect(
        await contained.submitTemplate(
          patientId: 'patient',
          uploaderId: 'owner',
          templateId: 'patient-intake',
          templateName: 'Intake',
          formValues: values,
        ),
        isFalse,
      );
      expect(contained.errorMessage, PatientSubmissionContainment.message);
      expect(contained.success, isFalse);
      expect(requests, isEmpty);
      contained.dispose();
    },
  );
}
