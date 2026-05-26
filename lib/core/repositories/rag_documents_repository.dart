import '../models/rag_document.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval for the `rag_documents` table.
/// This table is world-readable under RLS rules.
class RagDocumentsRepository {
  final _client = SupabaseService.client;

  /// Retrieves the list of vector-embedded knowledge base entries.
  /// Throws a [Failure] on error.
  Future<List<RagDocument>> getRagDocuments() async {
    try {
      final response = await _client
          .from('rag_documents')
          .select()
          .order('created_at', ascending: false);
      
      return (response as List)
          .map((json) => RagDocument.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
