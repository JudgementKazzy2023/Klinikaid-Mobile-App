import '../models/patient_queue.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval for the `patient_queue` table.
class PatientQueueRepository {
  final _client = SupabaseService.client;

  /// Retrieves the list of queue entries associated with a specific [patientId].
  /// Throws a [Failure] on error or RLS denial.
  Future<List<PatientQueue>> getQueueForPatient(String patientId) async {
    try {
      final response = await _client
          .from('patient_queue')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);
      
      return (response as List)
          .map((json) => PatientQueue.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
