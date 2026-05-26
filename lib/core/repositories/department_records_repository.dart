import '../models/department_record.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval for the `department_records` table.
/// Patients have read-only access to their own records.
class DepartmentRecordsRepository {
  final _client = SupabaseService.client;

  /// Retrieves the list of clinical department results associated with a specific [patientId].
  /// Throws a [Failure] on error or RLS denial.
  Future<List<DepartmentRecord>> getRecordsForPatient(String patientId) async {
    try {
      final response = await _client
          .from('department_records')
          .select()
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);
      
      return (response as List)
          .map((json) => DepartmentRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
