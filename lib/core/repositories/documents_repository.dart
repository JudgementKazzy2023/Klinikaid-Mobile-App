import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/document.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval for the `documents` table.
class DocumentsRepository {
  DocumentsRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// The client is resolved lazily so an injected client can be used and a
  /// repository can be built before Supabase is initialized.
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

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
}
