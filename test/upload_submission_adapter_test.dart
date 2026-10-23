import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
import 'package:klinikaid_mobile/features/documents/data/uploads_repository.dart';
import 'support/upload_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UploadFixture f;
  setUp(() async {
    PatientSubmissionContainment.activeForTesting = false;
    f = UploadFixture();
    await f.init();
  });
  tearDown(() async {
    try {
      await f.close();
    } finally {
      PatientSubmissionContainment.activeForTesting = true;
    }
  });
  test(
    'exact pending storage/assessment/function bodies and patient JWT; no documents writes',
    () async {
      expect(await f.submit(selected: ['cbc']), true);
      final storage = f.requests.singleWhere(
        (r) => r.url.path.contains('/storage/'),
      );
      expect(
        storage.url.path,
        contains(
          '/patient-documents/${UploadFixture.owner}/pending-submissions/',
        ),
      );
      expect(storage.url.path, endsWith('/source.pdf'));
      final assessment =
          jsonDecode(
                f.requests
                    .singleWhere(
                      (r) => r.url.path.endsWith('/pending_document_ocr'),
                    )
                    .body,
              )
              as Map;
      expect(assessment.keys.toSet(), {
        'id',
        'user_id',
        'patient_id',
        'file_name',
        'file_type',
        'file_path',
        'ocr_text',
      });
      expect(assessment['patient_id'], UploadFixture.patientId);
      expect(assessment['user_id'], UploadFixture.owner);
      final invoke = f.requests.singleWhere(
        (r) => r.url.path.endsWith('/upload'),
      );
      final body = jsonDecode(invoke.body) as Map;
      expect(body.keys.toSet(), {
        'request_id',
        'assessment_id',
        'document_type',
        'selected_test_ids',
      });
      expect(body['assessment_id'], assessment['id']);
      expect(body['document_type'], 'lab-request');
      expect(body['selected_test_ids'], ['cbc']);
      expect(
        invoke.headers['authorization'],
        'Bearer ${f.client.auth.currentSession!.accessToken}',
      );
      expect(
        f.requests.any(
          (r) =>
              r.url.path.endsWith('/documents') &&
              r.method.toUpperCase() != 'GET',
        ),
        false,
      );
      expect(await f.drafts(), isEmpty);
      expect(await f.file.exists(), true);
    },
  );
  test('replayed:true is confirmed success', () async {
    f.respond = (r) async => r.url.path.endsWith('/upload')
        ? f.json({
            'document_id': 'original',
            'status': 'pending',
            'replayed': true,
          }, 200)
        : f.defaults(r);
    expect(await f.submit(), true);
    expect(f.provider.submittedDocumentId, 'original');
  });
  const codes = {
    'FIELD_REQUIRED': 400,
    'FIELD_INVALID': 400,
    'DUPLICATE_PENDING': 409,
    'IDEMPOTENCY_CONFLICT': 409,
    'RECONCILIATION_REQUIRED': 409,
    'ASSESSMENT_NOT_FOUND': 409,
    'UNAUTHENTICATED': 401,
    'EMAIL_NOT_CONFIRMED': 403,
    'CONSENT_REQUIRED': 403,
    'PASSWORD_CHANGE_REQUIRED': 403,
    'PATIENT_ACCOUNT_REQUIRED': 403,
    'NO_PATIENT_RECORD': 403,
    'PROFILE_INACTIVE': 403,
    'UNKNOWN_FIELD': 400,
    'METHOD_NOT_ALLOWED': 405,
    'SERVER_ERROR': 503,
  };
  for (final entry in codes.entries) {
    test(
      '${entry.key}: typed mapping retains draft/file and exposes remediation',
      () async {
        f.respond = (r) async => r.url.path.endsWith('/upload')
            ? f.json({
                'error_code': entry.key,
                'message': 'Safe server message',
                'field': 'selected_test_ids',
                'document_id': 'duplicate-document',
                'status': 'pending',
              }, entry.value)
            : f.defaults(r);
        expect(await f.submit(), false);
        expect(f.provider.errorCode, entry.key);
        expect(await f.drafts(), hasLength(1));
        expect(await f.file.exists(), true);
        if (['FIELD_REQUIRED', 'FIELD_INVALID'].contains(entry.key))
          expect(f.provider.fieldErrors, {
            'selected_test_ids': 'Safe server message',
          });
        if (entry.key == 'DUPLICATE_PENDING') {
          expect(f.provider.duplicateDocumentId, 'duplicate-document');
          expect(
            f.provider.errorMessage,
            'You already have a pending Laboratory Request',
          );
        }
        const routes = {
          'UNAUTHENTICATED': '/login',
          'EMAIL_NOT_CONFIRMED': '/verify',
          'CONSENT_REQUIRED': '/consent',
          'PASSWORD_CHANGE_REQUIRED': 'change-password',
        };
        expect(f.provider.remediationRoute, routes[entry.key]);
        if ([
          'IDEMPOTENCY_CONFLICT',
          'RECONCILIATION_REQUIRED',
          'ASSESSMENT_NOT_FOUND',
        ].contains(entry.key)) {
          final before = f.requests.length;
          final draft = (await f.drafts()).single;
          expect(await f.provider.resolveQueuedDraft(draft.id), false);
          expect(f.requests.length, before);
          expect(f.provider.errorMessage, contains('contact the clinic'));
        }
        if (['UNKNOWN_FIELD', 'METHOD_NOT_ALLOWED'].contains(entry.key))
          expect(f.provider.errorMessage, 'This app version is out of date.');
        if (entry.key == 'SERVER_ERROR')
          expect(f.provider.errorMessage, UploadFailure.unknown.message);
      },
    );
  }
  for (final failure in ['network', 'timeout']) {
    test(
      '$failure then authoritative not_found resends same request; edits rotate content IDs',
      () async {
        f.respond = (r) async {
          if (r.url.path.endsWith('/upload')) {
            if (failure == 'network') throw const SocketException('fixture');
            throw TimeoutException('fixture');
          }
          return f.defaults(r);
        };
        expect(await f.submit(), false);
        final first = (await f.drafts()).single;
        expect(first.uploadState, 'unknown');
        expect(await File(first.localFilePath).exists(), true);
        expect(await f.submit(), false);
        final second = (await f.drafts()).single;
        expect(second.requestId, first.requestId);
        expect(second.assessmentId, first.assessmentId);
        final routes = f.requests
            .where((r) => r.url.path.contains('/functions/'))
            .toList();
        expect(routes.map((r) => r.url.path.split('/').last), [
          'upload',
          'status',
          'upload',
        ]);
        expect(jsonDecode(routes[1].body), {'request_id': first.requestId});
        expect(await f.submit(category: 'other'), false);
        final third = (await f.drafts()).single;
        expect(third.requestId, isNot(first.requestId));
        expect(third.assessmentId, isNot(first.assessmentId));
      },
    );
  }
  test(
    'committed lookup resolves unknown without preparation or resend',
    () async {
      f.respond = (r) async => r.url.path.endsWith('/upload')
          ? f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503)
          : f.defaults(r);
      await f.submit();
      final before = f.requests.length;
      f.respond = (r) async => r.url.path.endsWith('/status')
          ? f.json({
              'state': 'committed',
              'document_id': 'committed',
              'status': 'approved',
            }, 200)
          : f.defaults(r);
      expect(await f.submit(), true);
      expect(f.requests.length, before + 1);
      expect(f.provider.submittedDocumentId, 'committed');
      expect(await f.drafts(), isEmpty);
    },
  );
  bool discardedRow(String assessmentId) => f.requests.any(
    (r) =>
        r.method == 'DELETE' &&
        r.url.path.endsWith('/pending_document_ocr') &&
        r.url.queryParameters['id'] == 'eq.$assessmentId',
  );
  bool discardedFile(String assessmentId) => f.requests.any(
    (r) =>
        r.method == 'DELETE' &&
        r.url.path.contains('/storage/') &&
        r.body.contains('/pending-submissions/$assessmentId/'),
  );
  Future<http.Response> fieldInvalidOnce(http.Request r) async =>
      r.url.path.endsWith('/upload')
      ? f.json({
          'error_code': 'FIELD_INVALID',
          'message': 'Pick a test',
          'field': 'selected_test_ids',
        }, 400)
      : f.defaults(r);

  test('an edited resend discards the unused earlier assessment', () async {
    f.respond = fieldInvalidOnce;
    expect(await f.submit(selected: ['cbc']), false);
    final first = (await f.drafts()).single;
    f.respond = f.defaults;
    expect(await f.submit(selected: ['fbs']), true);
    expect(discardedRow(first.assessmentId!), true);
    expect(discardedFile(first.assessmentId!), true);
  });

  test('an unchanged resend keeps its assessment', () async {
    f.respond = fieldInvalidOnce;
    expect(await f.submit(selected: ['cbc']), false);
    final first = (await f.drafts()).single;
    f.respond = f.defaults;
    expect(await f.submit(selected: ['cbc']), true);
    expect(discardedRow(first.assessmentId!), false);
  });

  test('a replayed success removes the re-inserted pending row', () async {
    f.respond = (r) async => r.url.path.endsWith('/upload')
        ? f.json({
            'document_id': 'slow-first-attempt',
            'status': 'pending',
            'replayed': true,
          }, 200)
        : f.defaults(r);
    final before = f.requests.length;
    expect(await f.submit(), true);
    final prepared = f.requests
        .skip(before)
        .firstWhere((r) => r.url.path.endsWith('/pending_document_ocr'));
    final id = (jsonDecode(prepared.body) as Map)['id'] as String;
    expect(discardedRow(id), true);
  });

  test('a template-only code from /upload is treated as an unknown outcome', () async {
    f.respond = (r) async => r.url.path.endsWith('/upload')
        ? f.json({'error_code': 'UNKNOWN_TEMPLATE', 'message': 'x'}, 400)
        : f.defaults(r);
    expect(await f.submit(), false);
    expect(f.provider.errorMessage, UploadFailure.unknown.message);
  });

  test(
    'confirmed outcomes delete the app copy, never the original file',
    () async {
      final folder = Directory(
        '${f.temp.path}/submission-drafts/${UploadFixture.owner}',
      );
      List<FileSystemEntity> copies() =>
          folder.existsSync() ? folder.listSync() : <FileSystemEntity>[];

      expect(await f.submit(), true);
      expect(copies(), isEmpty);
      expect(await f.file.exists(), true);

      f.respond = (r) async => r.url.path.endsWith('/upload')
          ? f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503)
          : f.defaults(r);
      expect(await f.submit(), false);
      expect(copies(), hasLength(1)); // unknown: the copy is kept
      f.respond = (r) async => r.url.path.endsWith('/status')
          ? f.json({
              'state': 'committed',
              'document_id': 'committed',
              'status': 'pending',
            }, 200)
          : f.defaults(r);
      expect(await f.submit(), true);
      expect(copies(), isEmpty);
      expect(await f.file.exists(), true);
    },
  );
  for (final state in ['withdrawn', 'unavailable']) {
    test('$state lookup never resends or deletes draft/file', () async {
      f.respond = (r) async => r.url.path.endsWith('/upload')
          ? f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503)
          : f.defaults(r);
      await f.submit();
      final draft = (await f.drafts()).single;
      final before = f.requests.length;
      f.respond = (r) async => state == 'withdrawn'
          ? f.json({'state': 'withdrawn'}, 200)
          : f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503);
      expect(await f.submit(), false);
      expect(f.requests.length, before + 1);
      expect(await f.drafts(), hasLength(1));
      expect(await File(draft.localFilePath).exists(), true);
      expect((await f.drafts()).single.requestId, draft.requestId);
    });
  }
  test(
    'containment blocks every repository/provider operation before HTTP/Storage',
    () async {
      PatientSubmissionContainment.activeForTesting = true;
      final repo = UploadsRepository(client: f.client);
      await expectLater(
        repo.submit(
          owner: UploadFixture.owner,
          requestId: 'id',
          assessmentId: 'id',
          documentType: 'other',
        ),
        throwsStateError,
      );
      await expectLater(
        repo.lookup(owner: UploadFixture.owner, requestId: 'id'),
        throwsStateError,
      );
      await expectLater(
        repo.prepare(
          owner: UploadFixture.owner,
          patientId: 'id',
          assessmentId: 'id',
          fileName: 'x',
          mime: 'application/pdf',
          bytes: await f.file.readAsBytes(),
          ocrText: '',
        ),
        throwsStateError,
      );
      expect(await f.submit(), false);
      await f.provider.syncOfflineQueue();
      expect(await f.provider.resolveQueuedDraft('id'), false);
      expect(f.requests, isEmpty);
    },
  );
  test(
    'changed bytes after unknown get a new ID only after original outcome check',
    () async {
      f.respond = (r) async => r.url.path.endsWith('/upload')
          ? f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503)
          : f.defaults(r);
      await f.submit();
      final before = (await f.drafts()).single;
      await f.file.writeAsString('%PDF-1.7 EDITED');
      await f.submit();
      final after = (await f.drafts()).single;
      expect(after.requestId, isNot(before.requestId));
      expect(
        f.requests.where((r) => r.url.path.endsWith('/status')),
        hasLength(1),
      );
    },
  );
}
