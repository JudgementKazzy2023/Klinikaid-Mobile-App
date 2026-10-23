import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/patient_submission_containment.dart';
import '../../../core/supabase/supabase_client.dart';

sealed class UploadResult {
  const UploadResult();
}

class UploadSuccess extends UploadResult {
  final String documentId;
  final String status;
  final bool replayed;
  const UploadSuccess(this.documentId, this.status, this.replayed);
}

class UploadFailure extends UploadResult {
  final String code;
  final String message;
  final String? field;
  final String? documentId;
  final String? status;
  const UploadFailure(
    this.code,
    this.message, {
    this.field,
    this.documentId,
    this.status,
  });
  static const unknown = UploadFailure(
    'SERVER_ERROR',
    'We could not confirm this submission. Your file and answers are still here. Try again, or contact the clinic.',
  );
}

class UploadLookup extends UploadResult {
  final String state;
  final String? documentId;
  final String? status;
  const UploadLookup(this.state, {this.documentId, this.status});
}

class UploadsRepository {
  final SupabaseClient? _injected;
  UploadsRepository({SupabaseClient? client}) : _injected = client;
  SupabaseClient get _client => _injected ?? SupabaseService.client;
  bool _owns(String owner) => _client.auth.currentUser?.id == owner;
  void _requireOwner(String owner) {
    if (!_owns(owner))
      throw StateError('Session changed. Your draft is still here.');
  }

  static String mimeFor(String ext) => switch (ext.toLowerCase()) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => '',
  };
  static String pendingPath(String owner, String assessment, String mime) =>
      '$owner/pending-submissions/$assessment/source.${switch (mime) {
        'application/pdf' => 'pdf',
        'image/png' => 'png',
        _ => 'jpg',
      }}';

  Future<void> prepare({
    required String owner,
    required String patientId,
    required String assessmentId,
    required String fileName,
    required String mime,
    required Uint8List bytes,
    required String ocrText,
  }) async {
    PatientSubmissionContainment.requireAvailable();
    _requireOwner(owner);
    if (mime.isEmpty || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException(
        'Only PDF, JPEG or PNG files up to 5 MB are supported.',
      );
    }
    final path = pendingPath(owner, assessmentId, mime);
    try {
      await _client.storage
          .from('patient-documents')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } on StorageException {
      // A lost upload response can leave the immutable object already present.
      _requireOwner(owner);
      final existing = await _client.storage
          .from('patient-documents')
          .download(path);
      if (!listEquals(existing, bytes)) {
        throw StateError(
          'Stored file differs. Contact the clinic before retrying.',
        );
      }
    }
    _requireOwner(owner);
    final row = {
      'id': assessmentId,
      'user_id': owner,
      'patient_id': patientId,
      'file_name': fileName,
      'file_type': mime,
      'file_path': path,
      'ocr_text': ocrText,
    };
    try {
      await _client.from('pending_document_ocr').insert(row);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      _requireOwner(owner);
      final existing = await _client
          .from('pending_document_ocr')
          .select()
          .eq('id', assessmentId)
          .eq('user_id', owner)
          .single();
      if (row.entries.any((e) => existing[e.key] != e.value)) {
        throw StateError(
          'Stored assessment differs. Contact the clinic before retrying.',
        );
      }
    }
    _requireOwner(owner);
  }

  /// Best effort: removes an assessment that has no committed or in-RPC submit
  /// (a returned pre-write error, or a `not_found` lookup), so an edited resend
  /// leaves no orphan row or pending file. Storage policy and
  /// migration 42's trigger refuse a file a document references, so this can
  /// never remove a submitted one.
  Future<void> discardAssessment({
    required String owner,
    required String assessmentId,
    required String mime,
  }) async {
    PatientSubmissionContainment.requireAvailable();
    if (!_owns(owner) || mime.isEmpty) return;
    try {
      await _client
          .from('pending_document_ocr')
          .delete()
          .eq('id', assessmentId)
          .eq('user_id', owner);
    } catch (_) {
      // Keep row and file together: a row left behind (for example while it
      // waits on an in-flight submit) must still have its file.
      return;
    }
    if (!_owns(owner)) return;
    try {
      await _client.storage.from('patient-documents').remove([
        pendingPath(owner, assessmentId, mime),
      ]);
    } catch (_) {}
  }

  Future<UploadResult> submit({
    required String owner,
    required String requestId,
    required String assessmentId,
    required String documentType,
    List<String>? selectedTestIds,
  }) async {
    PatientSubmissionContainment.requireAvailable();
    _requireOwner(owner);
    return _invoke('patient-document-submission/upload', {
      'request_id': requestId,
      'assessment_id': assessmentId,
      'document_type': documentType,
      if (selectedTestIds != null) 'selected_test_ids': selectedTestIds,
    });
  }

  Future<UploadResult> lookup({
    required String owner,
    required String requestId,
  }) async {
    PatientSubmissionContainment.requireAvailable();
    _requireOwner(owner);
    return _invoke('patient-document-submission/upload/status', {
      'request_id': requestId,
    }, lookup: true);
  }

  Future<UploadResult> _invoke(
    String route,
    Map<String, dynamic> body, {
    bool lookup = false,
  }) async {
    try {
      final response = await _client.functions
          .invoke(route, method: HttpMethod.post, body: body)
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (response.status != 200 || data is! Map) return UploadFailure.unknown;
      if (lookup) {
        if (data['state'] == 'not_found' || data['state'] == 'withdrawn') {
          return UploadLookup(data['state']);
        }
        if (data['state'] == 'committed' &&
            data['document_id'] is String &&
            (data['document_id'] as String).isNotEmpty &&
            data['status'] is String) {
          return UploadLookup(
            'committed',
            documentId: data['document_id'],
            status: data['status'],
          );
        }
      } else if (data['document_id'] is String &&
          (data['document_id'] as String).isNotEmpty &&
          data['status'] == 'pending' &&
          data['replayed'] is bool) {
        return UploadSuccess(
          data['document_id'],
          data['status'],
          data['replayed'],
        );
      }
      return UploadFailure.unknown;
    } on FunctionException catch (error) {
      try {
        final data = error.details is String
            ? jsonDecode(error.details)
            : error.details;
        if (data is Map &&
            data['error_code'] is String &&
            data['message'] is String) {
          return UploadFailure(
            data['error_code'],
            data['message'],
            field: data['field'] is String ? data['field'] : null,
            documentId: data['document_id'] is String
                ? data['document_id']
                : null,
            status: data['status'] is String ? data['status'] : null,
          );
        }
      } catch (_) {
        /* An unreadable response cannot establish the outcome. */
      }
      return UploadFailure.unknown;
    } on IOException {
      return UploadFailure.unknown;
    } catch (_) {
      return UploadFailure.unknown;
    }
  }
}
