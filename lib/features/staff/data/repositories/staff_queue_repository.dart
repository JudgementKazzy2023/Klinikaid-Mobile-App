import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/document.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/errors/failures.dart';

/// Repository that manages data queries and updates for staff roles.
/// All queries respect Supabase Row Level Security (RLS) policies.
class StaffQueueRepository {
  final _client = SupabaseService.client;

  /// Fetches Today's patient queue. If [department] is provided, filters the queue to that department.
  /// Sorting is chronological (created_at ascending).
  Future<List<PatientQueue>> getQueueForToday({String? department}) async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

      var query = _client
          .from('patient_queue')
          .select('*, patient:patients(*)');

      // Filter for today's entries
      query = query.gte('created_at', startOfToday);

      // Defense-in-depth: query filter by department (UX filter, server RLS enforces security)
      if (department != null) {
        query = query.eq('department', department);
      }

      final response = await query.order('created_at', ascending: true);

      return (response as List)
          .map((json) => PatientQueue.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Updates a patient's queue status in the database.
  Future<void> updateQueueStatus(int queueId, QueueStatus status) async {
    try {
      await _client
          .from('patient_queue')
          .update({'status': status.toJsonValue()})
          .eq('id', queueId);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves documents by status, optionally filtering by age.
  Future<List<Document>> getDocumentsByStatus({
    required DocumentStatus status,
    Duration? maxAge,
  }) async {
    try {
      var query = _client
          .from('documents')
          .select('*, patient:patients(*)')
          .eq('status', status.toJsonValue());

      if (maxAge != null) {
        final cutoff = DateTime.now().toUtc().subtract(maxAge).toIso8601String();
        query = query.gte('updated_at', cutoff);
      }

      final response = await query.order('updated_at', ascending: false);

      return (response as List)
          .map((json) => Document.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves the list of documents that are in a 'pending' state.
  Future<List<Document>> getPendingDocuments() async {
    return getDocumentsByStatus(status: DocumentStatus.pending);
  }

  /// Updates the approval status of a document, optionally attaching a rejection reason.
  Future<void> updateDocumentStatus(
    String documentId,
    DocumentStatus status, {
    String? rejectionReason,
  }) async {
    try {
      final updates = <String, dynamic>{'status': status.toJsonValue()};
      if (status == DocumentStatus.rejected) {
        updates['rejection_reason'] = rejectionReason;
      } else {
        updates['rejection_reason'] = null; // Clear any pre-existing reason if approved
      }

      await _client
          .from('documents')
          .update(updates)
          .eq('id', documentId);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Searches for patients by first name or last name.
  Future<List<Patient>> searchPatients(String query) async {
    try {
      final response = await _client
          .from('patients')
          .select()
          .or('first_name.ilike.%$query%,last_name.ilike.%$query%')
          .order('last_name', ascending: true);

      return (response as List)
          .map((json) => Patient.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves all department records (lab results, imaging, etc.) associated with a specific patient.
  Future<List<DepartmentRecord>> getDepartmentRecordsForPatient(String patientId) async {
    try {
      final response = await _client
          .from('department_records')
          .select('*, recorder:profiles(*)')
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => DepartmentRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves the most recent department records entered for a specific department (limit 30).
  Future<List<DepartmentRecord>> getRecentDepartmentRecords(String department) async {
    try {
      final response = await _client
          .from('department_records')
          .select('*, patient:patients(*)')
          .eq('department', department)
          .order('created_at', ascending: false)
          .limit(30);

      return (response as List)
          .map((json) => DepartmentRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
