import '../../../core/models/patient_queue.dart';
import '../../../core/models/department_record.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/errors/failures.dart';

class DepartmentUnassignedException implements Exception {
  final String message;
  DepartmentUnassignedException([this.message = 'User profile has no department assigned.']);
  
  @override
  String toString() => message;
}

class DepartmentRepository {
  final _client = SupabaseService.client;

  /// Fetches the user's department from the profile table.
  /// Throws [DepartmentUnassignedException] if department is null or unknown.
  Future<String> _getCurrentUserDept() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthFailure('User not authenticated');
    }
    
    final response = await _client
        .from('profiles')
        .select('department')
        .eq('id', userId)
        .single();
    
    final dept = response['department'] as String?;
    if (dept == null || dept.trim().isEmpty) {
      throw DepartmentUnassignedException();
    }
    return dept;
  }

  /// Fetches today's queue entries for the user's department.
  /// No parameters to enforce server-side scoping.
  Future<List<PatientQueue>> getDailyQueue() async {
    try {
      final department = await _getCurrentUserDept();
      
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      
      final response = await _client
          .from('patient_queue')
          .select('*, patient:patients(*)')
          .eq('department', department)
          .inFilter('status', ['waiting', 'in_progress'])
          .gte('created_at', startOfToday)
          .order('created_at', ascending: true);
          
      return (response as List)
          .map((json) => PatientQueue.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DepartmentUnassignedException) rethrow;
      throw FailureMapper.fromException(e);
    }
  }

  /// Fetches completed department records for the user's department.
  /// No parameters to enforce server-side scoping.
  Future<List<DepartmentRecord>> getRecordsHistory() async {
    try {
      final department = await _getCurrentUserDept();
      
      final response = await _client
          .from('department_records')
          .select('*, patient:patients(*), recorder:profiles(*)')
          .eq('department', department)
          .order('created_at', ascending: false);
          
      return (response as List)
          .map((json) => DepartmentRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DepartmentUnassignedException) rethrow;
      throw FailureMapper.fromException(e);
    }
  }
}
