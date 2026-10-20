import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
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

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => const User(
        id: 'user-uuid-123',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseClient client;
  late Patient patient;
  late Directory tempDir;
  late File scanFile;

  setUp(() {
    client = FakeSupabaseClient();
    SupabaseService.mockClient = client;

    patient = Patient(
      id: 'patient-row-id-123',
      // The signed-in account owns this patient record: the provider refuses a
      // document submitted for a patient that belongs to another profile.
      profileId: 'user-uuid-123',
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
    scanFile = File('${tempDir.path}/scan.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0]);
  });

  tearDown(() {
    SupabaseService.mockClient = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<bool> submitScan(DocumentSubmissionProvider provider) {
    return provider.submitDocument(
      localFilePath: scanFile.path,
      originalFileName: 'scan.jpg',
      fileExtension: 'jpg',
      patient: patient,
      documentType: 'lab-request',
    );
  }

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
    test('network, permission and parse failures are reported as a failed check',
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
    });

    test('a malformed row fails the check instead of reporting no duplicate',
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
      }
    });

    test('a successful read still reports duplicate or clear', () async {
      client.documents = [_pendingTemplateRow('lab-request')];
      final duplicate = await checkPendingDuplicate(patient.id, 'lab-request');
      expect(duplicate.state, DuplicateCheckState.duplicate);
      expect(duplicate.duplicateDate, isNotNull);

      client.documents = [_pendingTemplateRow('referral-form')];
      final other = await checkPendingDuplicate(patient.id, 'lab-request');
      expect(other.state, DuplicateCheckState.clear);
      expect(other.duplicateDate, isNull);
    });
  });

  group('Immediate upload — a failed duplicate check blocks the submission', () {
    test('no upload or insert is attempted and the patient is asked to retry',
        () async {
      client.readError = const SocketException('Network is unreachable');
      final provider = DocumentSubmissionProvider(LocalDatabase());

      final submitted = await submitScan(provider);

      expect(submitted, isFalse);
      expect(
        provider.errorMessage,
        contains(
            'Could not check for a pending [Laboratory Request] submission.'),
      );
      expect(provider.errorMessage, contains('try again'));
      expect(client.uploads, isEmpty);
      expect(client.inserts, isEmpty);
    });

    test('a permission failure is surfaced the same way', () async {
      client.readError = const PostgrestException(
        message: 'permission denied for table documents',
        code: '42501',
      );
      final provider = DocumentSubmissionProvider(LocalDatabase());

      final submitted = await submitScan(provider);

      expect(submitted, isFalse);
      expect(
        provider.errorMessage,
        contains(
            'Could not check for a pending [Laboratory Request] submission.'),
      );
      expect(client.uploads, isEmpty);
      expect(client.inserts, isEmpty);
    });

    test('a real duplicate still blocks with the pending date', () async {
      client.documents = [_pendingTemplateRow('lab-request')];
      final provider = DocumentSubmissionProvider(LocalDatabase());

      final submitted = await submitScan(provider);

      expect(submitted, isFalse);
      expect(
        provider.errorMessage,
        contains(
            'You already have a pending [Laboratory Request] submitted on'),
      );
      expect(client.uploads, isEmpty);
      expect(client.inserts, isEmpty);
    });

    test('a verified clear check still uploads and inserts', () async {
      client.documents = [_pendingTemplateRow('referral-form')];
      final provider = DocumentSubmissionProvider(LocalDatabase());

      final submitted = await submitScan(provider);

      expect(submitted, isTrue);
      expect(provider.errorMessage, isNull);
      expect(client.uploads, hasLength(1));
      expect(client.inserts, hasLength(1));
    });
  });

  group('Template submission — a failed duplicate check blocks the submission',
      () {
    test('no insert is attempted and the patient is asked to retry', () async {
      client.readError = const SocketException('Network is unreachable');
      final provider = TemplatesProvider();

      final submitted = await submitTemplateForm(provider);

      expect(submitted, isFalse);
      expect(
        provider.errorMessage,
        contains(
            'Could not check for a pending [Laboratory Request] submission.'),
      );
      expect(provider.errorMessage, contains('try again'));
      expect(client.inserts, isEmpty);
    });

    test('a real duplicate still blocks with the pending date', () async {
      client.documents = [_pendingTemplateRow('lab-request')];
      final provider = TemplatesProvider();

      final submitted = await submitTemplateForm(provider);

      expect(submitted, isFalse);
      expect(
        provider.errorMessage,
        contains(
            'You already have a pending [Laboratory Request] submitted on'),
      );
      expect(client.inserts, isEmpty);
    });

    test('a verified clear check still inserts the template', () async {
      client.documents = [_pendingTemplateRow('referral-form')];
      final provider = TemplatesProvider();

      final submitted = await submitTemplateForm(provider);

      expect(submitted, isTrue);
      expect(provider.errorMessage, isNull);
      expect(client.inserts, hasLength(1));
    });
  });
}
