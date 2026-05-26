import '../models/chatbot_log.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval and insertion for the `chatbot_logs` table.
class ChatbotLogsRepository {
  final _client = SupabaseService.client;

  /// Retrieves the history of chatbot logs for the specific [userId].
  /// Throws a [Failure] on error or RLS denial.
  Future<List<ChatbotLog>> getLogsForUser(String userId) async {
    try {
      final response = await _client
          .from('chatbot_logs')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return (response as List)
          .map((json) => ChatbotLog.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Inserts a new chatbot transaction record.
  /// Note: The `id` field is removed from the payload prior to execution,
  /// as the database column is GENERATED ALWAYS AS IDENTITY.
  /// Throws a [Failure] on error.
  Future<ChatbotLog> insertLog(ChatbotLog log) async {
    try {
      final jsonPayload = log.toJson();
      jsonPayload.remove('id'); // Exclude auto-generated identity ID

      final response = await _client
          .from('chatbot_logs')
          .insert(jsonPayload)
          .select()
          .single();
      return ChatbotLog.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
