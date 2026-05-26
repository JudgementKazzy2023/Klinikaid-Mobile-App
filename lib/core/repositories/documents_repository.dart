import '../models/document.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval and uploads for the `documents` table.
class DocumentsRepository {
  final _client = SupabaseService.client;

  /// Retrieves the list of documents uploaded by the specific [uploaderId].
  /// Throws a [Failure] on error or RLS denial.
  Future<List<Document>> getDocumentsForPatient(String uploaderId) async {
    try {
      final response = await _client
          .from('documents')
          .select()
          .eq('uploader_id', uploaderId)
          .order('created_at', ascending: false);
      
      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Inserts a new document metadata record (which has already been processed by OCR).
  /// Throws a [Failure] on error.
  Future<Document> insertDocument(Document document) async {
    try {
      final jsonPayload = document.toJson();
      jsonPayload.remove('patient');
      jsonPayload.remove('uploader');
      final response = await _client
          .from('documents')
          .insert(jsonPayload)
          .select()
          .single();
      return Document.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Updates a pending document's details. RLS restricts this to documents where `status = 'pending'`.
  /// Throws a [Failure] on error (e.g. if the document is already approved/rejected).
  Future<Document> updatePendingDocument(Document document) async {
    try {
      final jsonPayload = document.toJson();
      jsonPayload.remove('patient');
      jsonPayload.remove('uploader');
      final response = await _client
          .from('documents')
          .update(jsonPayload)
          .eq('id', document.id)
          .eq('status', 'pending') // Aligns with RLS rules
          .select()
          .single();
      return Document.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
