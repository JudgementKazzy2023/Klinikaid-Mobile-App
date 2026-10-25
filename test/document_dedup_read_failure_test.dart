import 'support/upload_fixture.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/patient_submission_containment.dart';

import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';

import 'package:klinikaid_mobile/features/patient/submissions/document_dedup.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';

/// Fake Supabase client that records every write the app attempts, so a test
/// can prove that a failed duplicate check stopped the submission before it
/// reached the server.
class FakeSupabaseClient extends Fake implements SupabaseClient {
  FakeSupabaseClient({List<Map<String, dynamic>>? documents, this.readError})
    : documents = documents ?? <Map<String, dynamic>>[];

  /// Rows returned by the pending `documents` read.
  List<Map<String, dynamic>> documents;

  /// When set, the pending `documents` read fails with this error.
  Object? readError;

  /// Storage paths the app tried to upload.
  final List<String> uploads = [];

  /// Rows the app tried to insert into `documents`.
  final List<Map<String, dynamic>> inserts = [];

  @override
  GoTrueClient get auth => _FakeGoTrueClient();

  @override
  SupabaseStorageClient get storage => _FakeStorageClient(this);

  @override
  SupabaseQueryBuilder from(String table) => _FakeQueryBuilder(this);
}

/// Id of the account that is signed in while these tests run.
const _signedInUserId = 'user-uuid-123';

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => const User(
    id: _signedInUserId,
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
}

class _FakeStorageClient extends Fake implements SupabaseStorageClient {
  _FakeStorageClient(this._owner);

  final FakeSupabaseClient _owner;

  @override
  StorageFileApi from(String id) => _FakeStorageFileApi(_owner);
}

class _FakeStorageFileApi extends Fake implements StorageFileApi {
  _FakeStorageFileApi(this._owner);

  final FakeSupabaseClient _owner;

  @override
  Future<String> upload(
    String path,
    File file, {
    FileOptions fileOptions = const FileOptions(),
    int? retryAttempts,
    StorageRetryController? retryController,
  }) async {
    _owner.uploads.add(path);
    return path;
  }
}

class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _FakeQueryBuilder(this._owner);

  final FakeSupabaseClient _owner;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #select) {
      return _FakeFilterBuilder(_owner);
    }
    if (invocation.memberName == #insert) {
      final payload = invocation.positionalArguments.first;
      if (payload is Map) {
        _owner.inserts.add(Map<String, dynamic>.from(payload));
      }
      return _FakeFilterBuilder(_owner);
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeFilterBuilder(this._owner);

  final FakeSupabaseClient _owner;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #eq || invocation.memberName == #select) {
      return this;
    }
    if (invocation.memberName == #single) {
      return _FakeTransformBuilder(_insertedDocumentRow());
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) {
    final error = _owner.readError;
    final future = error != null
        ? Future<List<Map<String, dynamic>>>.error(error, StackTrace.current)
        : Future<List<Map<String, dynamic>>>.value(_owner.documents);
    return future.then(onValue, onError: onError);
  }
}

class _FakeTransformBuilder extends Fake
    implements PostgrestTransformBuilder<PostgrestMap> {
  _FakeTransformBuilder(this.value);

  final PostgrestMap value;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(PostgrestMap value) onValue, {
    Function? onError,
  }) {
    return Future<PostgrestMap>.value(value).then(onValue, onError: onError);
  }
}

Map<String, dynamic> _insertedDocumentRow() => {
  'id': 'generated-id',
  'patient_id': 'patient-row-id-123',
  'uploader_id': 'user-uuid-123',
  'file_name': 'scan.jpg',
  'file_path': 'user-uuid-123/generated-id_scan.jpg',
  'file_type': 'jpg',
  'status': 'pending',
  'ocr_text': '',
  'extracted_metadata': <String, dynamic>{'document_type': 'lab-request'},
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _pendingTemplateRow(String templateId) => {
  'file_type': 'template',
  'status': 'pending',
  'extracted_metadata': {'template_id': templateId},
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  // These tests exercise the submit flows that containment blocks.
  setUp(() => PatientSubmissionContainment.activeForTesting = false);
  tearDown(() => PatientSubmissionContainment.activeForTesting = true);

  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseClient client;
  late Patient patient;
  late Directory tempDir;

  setUp(() {
    client = FakeSupabaseClient();
    SupabaseService.mockClient = client;

    patient = Patient(
      id: 'patient-row-id-123',
      // The signed-in account owns this patient record: the provider refuses a
      // document submitted for a patient that belongs to another profile.
      profileId: _signedInUserId,
      firstName: 'Alice',
      lastName: 'Smith',
      dateOfBirth: DateTime(1995, 8, 10),
      gender: Gender.female,
      contactNumber: '09171234567',
      address: 'Manila, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    tempDir = Directory.systemTemp.createTempSync('klinikaid_dedup_test');
    File('${tempDir.path}/scan.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
  });

  tearDown(() {
    SupabaseService.mockClient = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<bool> submitTemplateForm(TemplatesProvider provider) {
    return provider.submitTemplate(
      patientId: patient.id,
      uploaderId: 'user-uuid-123',
      templateId: 'lab-request',
      templateName: 'Laboratory Request',
      formValues: const {'ordering_physician': 'Dr. Santos'},
      patientName: 'Alice Smith',
    );
  }

  group('Pending duplicate check — a failed read is not a clear check', () {
    test(
      'network, permission and parse failures are reported as a failed check',
      () async {
        final failures = <Object>[
          const SocketException('Network is unreachable'),
          const PostgrestException(
            message: 'permission denied for table documents',
            code: '42501',
          ),
          const FormatException('Unexpected character at 0'),
        ];

        for (final failure in failures) {
          client.readError = failure;

          final result = await checkPendingDuplicate(patient.id, 'lab-request');

          expect(result.state, DuplicateCheckState.failed, reason: '$failure');
          expect(result.duplicateDate, isNull, reason: '$failure');
          expect(result.error, isNotNull, reason: '$failure');
        }
      },
    );

    test(
      'only a connectivity failure is reported as a network failure',
      () async {
        client.readError = const SocketException('Network is unreachable');
        final networkFailure = await checkPendingDuplicate(
          patient.id,
          'lab-request',
        );
        expect(networkFailure.state, DuplicateCheckState.failed);
        expect(networkFailure.isNetworkFailure, isTrue);

        client.readError = const PostgrestException(
          message: 'permission denied for table documents',
          code: '42501',
        );
        final permissionFailure = await checkPendingDuplicate(
          patient.id,
          'lab-request',
        );
        expect(permissionFailure.state, DuplicateCheckState.failed);
        expect(permissionFailure.isNetworkFailure, isFalse);

        client.readError = const FormatException('Unexpected character at 0');
        final parseFailure = await checkPendingDuplicate(
          patient.id,
          'lab-request',
        );
        expect(parseFailure.state, DuplicateCheckState.failed);
        expect(parseFailure.isNetworkFailure, isFalse);
      },
    );

    test(
      'a malformed row fails the check instead of reporting no duplicate',
      () async {
        final malformedRows = <Map<String, dynamic>>[
          // extracted_metadata is not a map.
          {
            'file_type': 'template',
            'status': 'pending',
            'extracted_metadata': 'not-a-map',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          // created_at is not a timestamp.
          {
            'file_type': 'template',
            'status': 'pending',
            'extracted_metadata': {'template_id': 'lab-request'},
            'created_at': 'not-a-date',
          },
          // created_at is missing.
          {
            'file_type': 'template',
            'status': 'pending',
            'extracted_metadata': {'template_id': 'lab-request'},
          },
        ];

        for (final row in malformedRows) {
          client.documents = [row];

          final result = await checkPendingDuplicate(patient.id, 'lab-request');

          expect(result.state, DuplicateCheckState.failed, reason: '$row');
          expect(result.duplicateDate, isNull, reason: '$row');
          expect(result.isNetworkFailure, isFalse, reason: '$row');
        }
      },
    );

    test('a successful read still reports duplicate or clear', () async {
      client.documents = [_pendingTemplateRow('lab-request')];
      final duplicate = await checkPendingDuplicate(patient.id, 'lab-request');
      expect(duplicate.state, DuplicateCheckState.duplicate);
      expect(duplicate.duplicateDate, isNotNull);
      expect(duplicate.isNetworkFailure, isFalse);

      client.documents = [_pendingTemplateRow('referral-form')];
      final other = await checkPendingDuplicate(patient.id, 'lab-request');
      expect(other.state, DuplicateCheckState.clear);
      expect(other.duplicateDate, isNull);
      expect(other.isNetworkFailure, isFalse);
    });
  });

  group('Upload advisory reads defer to the authoritative server', () {
    for (final kind in [
      'offline',
      'permission',
      'malformed',
      'clear',
      'duplicate',
      'recovered-network',
      'server-field-error',
    ]) {
      test(
        '$kind read preserves drafts and uses the server outcome without direct inserts',
        () async {
          final f = UploadFixture();
          await f.init();
          try {
            f.respond = (r) async {
              if (r.url.path.endsWith('/documents')) {
                if (kind == 'offline' || kind == 'recovered-network')
                  throw const SocketException('synthetic read offline');
                if (kind == 'permission')
                  return f.json({
                    'message': 'permission denied',
                    'code': '42501',
                  }, 403);
                if (kind == 'malformed')
                  return f.json([
                    {
                      'file_type': 'template',
                      'status': 'pending',
                      'extracted_metadata': 'invalid',
                    },
                  ], 200);
                if (kind == 'duplicate')
                  return f.json([
                    {
                      'file_type': 'template',
                      'status': 'pending',
                      'extracted_metadata': {'template_id': 'lab-request'},
                      'created_at': '2026-10-23T00:00:00Z',
                    },
                  ], 200);
                return f.json([], 200);
              }
              if (kind == 'offline' && r.url.path.contains('/storage/'))
                throw const SocketException('synthetic upload offline');
              if (r.url.path.endsWith('/upload') && kind == 'duplicate')
                return f.json({
                  'error_code': 'DUPLICATE_PENDING',
                  'message': 'pending',
                  'document_id': 'existing',
                  'status': 'pending',
                }, 409);
              if (r.url.path.endsWith('/upload') &&
                  kind == 'server-field-error')
                return f.json({
                  'error_code': 'FIELD_INVALID',
                  'message': 'Select a valid value.',
                  'field': 'document_type',
                }, 400);
              return f.defaults(r);
            };
            final done = await f.submit();
            if (kind == 'offline' ||
                kind == 'duplicate' ||
                kind == 'server-field-error') {
              expect(done, false);
              expect(await f.drafts(), hasLength(1));
              expect(await f.file.exists(), true);
            } else {
              expect(done, true);
            }
            if (kind == 'duplicate')
              expect(f.provider.duplicateDocumentId, 'existing');
            if (kind == 'server-field-error')
              expect(f.provider.fieldErrors, {
                'document_type': 'Select a valid value.',
              });
            expect(
              f.requests.any(
                (r) =>
                    r.url.path.endsWith('/documents') &&
                    r.method.toUpperCase() != 'GET',
              ),
              false,
            );
          } finally {
            await f.close();
          }
        },
      );
    }
  });
  group('Template submission — the local duplicate check is advisory only', () {
    for (final readError in <Object?>[
      const SocketException('Network is unreachable'),
      const PostgrestException(
        message: 'permission denied for table documents',
        code: '42501',
      ),
      null,
    ]) {
      test(
        'never inserts into documents directly (read error: $readError)',
        () async {
          client.readError = readError;
          client.documents = [_pendingTemplateRow('lab-request')];
          await submitTemplateForm(TemplatesProvider());
          expect(client.inserts, isEmpty);
        },
      );
    }
  });
}
