import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/patient_submission_containment.dart';

sealed class TemplateSubmissionResult {
  const TemplateSubmissionResult();
}

class TemplateSubmissionSuccess extends TemplateSubmissionResult {
  final String documentId;
  final String status;
  final bool replayed;
  const TemplateSubmissionSuccess(this.documentId, this.status, this.replayed);
}

class TemplateSubmissionError extends TemplateSubmissionResult {
  final String code;
  final String message;
  final String? field;
  final String? documentId;
  final String? status;
  const TemplateSubmissionError(
    this.code,
    this.message, {
    this.field,
    this.documentId,
    this.status,
  });

  static const unknown = TemplateSubmissionError(
    'SERVER_ERROR',
    'We could not confirm this submission. Your answers are still here. '
        'Try again, or contact the clinic.',
  );
}

enum TemplateLookupState { committed, withdrawn, notFound }

/// What the server knows about an earlier request (POST .../status).
class TemplateLookup {
  final TemplateLookupState state;
  final String? documentId;
  final String? status;
  const TemplateLookup(this.state, {this.documentId, this.status});
}

/// Transport separated from the guarded app entry point for synthetic HTTP tests.
class TemplateSubmissionApi {
  final SupabaseClient client;
  const TemplateSubmissionApi(this.client);

  Future<TemplateSubmissionResult> submit({
    required String requestId,
    required String templateId,
    required Map<String, String> fields,
  }) async {
    try {
      final response = await client.functions
          .invoke(
            'patient-document-submission',
            method: HttpMethod.post,
            body: {
              'request_id': requestId,
              'template_id': templateId,
              'fields': Map<String, String>.from(fields),
            },
          )
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (response.status == 200 &&
          data is Map &&
          data['document_id'] is String &&
          (data['document_id'] as String).isNotEmpty &&
          data['status'] == 'pending' &&
          data['replayed'] is bool) {
        return TemplateSubmissionSuccess(
          data['document_id'],
          data['status'],
          data['replayed'],
        );
      }
      return TemplateSubmissionError.unknown;
    } on FunctionException catch (error) {
      try {
        final details = error.details;
        final data = details is String ? jsonDecode(details) : details;
        if (data is Map &&
            data['error_code'] is String &&
            data['message'] is String) {
          return TemplateSubmissionError(
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
        // A response that cannot be decoded cannot establish the outcome.
      }
      return TemplateSubmissionError.unknown;
    } catch (_) {
      // Includes timeout and transport failures, possibly after a commit.
      return TemplateSubmissionError.unknown;
    }
  }

  /// Null when the outcome cannot be read: never treat that as an answer.
  Future<TemplateLookup?> lookup(String requestId) async {
    try {
      final response = await client.functions
          .invoke(
            'patient-document-submission/status',
            method: HttpMethod.post,
            body: {'request_id': requestId},
          )
          .timeout(const Duration(seconds: 30));
      final data = response.data;
      if (response.status != 200 || data is! Map) return null;
      switch (data['state']) {
        case 'committed':
          final id = data['document_id'];
          if (id is! String || id.isEmpty) return null;
          return TemplateLookup(TemplateLookupState.committed,
              documentId: id, status: data['status'] as String?);
        case 'withdrawn':
          return const TemplateLookup(TemplateLookupState.withdrawn);
        case 'not_found':
          return const TemplateLookup(TemplateLookupState.notFound);
      }
      return null;
    } catch (_) {
      // Includes FunctionException (gate refusals), timeouts and transport.
      return null;
    }
  }
}

class TemplatesRepository {
  final SupabaseClient? _injectedClient;
  TemplatesRepository({SupabaseClient? client}) : _injectedClient = client;

  Future<TemplateSubmissionResult> submitTemplateDocument({
    String? requestId,
    required String templateId,
    Map<String, String>? fields,
    // Legacy arguments keep existing containment callers source compatible.
    // They are never used to build the function body.
    String? patientId,
    String? uploaderId,
    String? templateName,
    Map<String, dynamic>? extractedMetadata,
  }) async {
    PatientSubmissionContainment.requireAvailable();
    if (requestId == null || fields == null) {
      throw ArgumentError('A request ID and patient answers are required.');
    }
    return TemplateSubmissionApi(
      _injectedClient ?? SupabaseService.client,
    ).submit(requestId: requestId, templateId: templateId, fields: fields);
  }

  Future<TemplateLookup?> lookupTemplateOutcome(String requestId) {
    PatientSubmissionContainment.requireAvailable();
    return TemplateSubmissionApi(
      _injectedClient ?? SupabaseService.client,
    ).lookup(requestId);
  }
}
