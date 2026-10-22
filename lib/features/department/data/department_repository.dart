import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/patient_queue.dart';
import '../../../core/models/department_record.dart';
import '../../../core/models/patient.dart';
import '../../../core/supabase/paged_read.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/errors/failures.dart';

class DepartmentUnassignedException implements Exception {
  final String message;
  DepartmentUnassignedException([this.message = 'User profile has no department assigned.']);
  
  @override
  String toString() => message;
}

class QueueCompletionFailure implements Exception {
  const QueueCompletionFailure();
  static const message = 'Results saved, but queue completion could not be confirmed. Refresh the queue before taking further action. Do not resubmit these results.';
}

/// Compute the start of today in PHT (UTC+8), expressed as a UTC DateTime.
/// Replicates web's getPhtStartOfToday() exactly.
DateTime phtStartOfTodayUtc() {
  final phtNow = DateTime.now().toUtc().add(const Duration(hours: 8));
  final phtMidnight = DateTime.utc(phtNow.year, phtNow.month, phtNow.day);
  return phtMidnight.subtract(const Duration(hours: 8));
}

class LabResultRow {
  final String patientId;          // patient_id
  final String recorderId;         // recorder_id
  final String department;         // department
  final String testType;           // test_type
  final String testName;           // test_name
  final String testValue;          // test_value
  final String? unit;              // unit
  final double? referenceRangeMin; // reference_range_min
  final double? referenceRangeMax; // reference_range_max
  final bool isFlagged;            // is_flagged
  final String? notes;             // notes

  LabResultRow({
    required this.patientId,
    required this.recorderId,
    required this.department,
    required this.testType,
    required this.testName,
    required this.testValue,
    this.unit,
    this.referenceRangeMin,
    this.referenceRangeMax,
    required this.isFlagged,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'patient_id': patientId,
      'recorder_id': recorderId,
      'department': department,
      'test_type': testType,
      'test_name': testName,
      'test_value': testValue,
      'unit': unit,
      'reference_range_min': referenceRangeMin,
      'reference_range_max': referenceRangeMax,
      'is_flagged': isFlagged,
      'notes': notes,
    };
  }
}

/// The department's active queue and the exact number of entries it holds.
class DepartmentQueuePage {
  const DepartmentQueuePage({required this.entries, required this.total});

  /// Every open entry of the department, oldest first.
  final List<PatientQueue> entries;

  /// The server's exact count of the open entries of the department.
  ///
  /// Independent of how many entries were read back, so a screen that shows a
  /// count never reports the size of one page as the size of the queue.
  final int total;
}

class DepartmentRepository {
  DepartmentRepository({SupabaseClient? client}) : _injectedClient = client;
  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  String? adminDepartmentOverride;

  /// Returns the current authenticated user's ID.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Fetches the user's department from the profile table.
  /// Throws [DepartmentUnassignedException] if department is null or unknown.
  Future<String> _getCurrentUserDept() async {
    if (adminDepartmentOverride != null) {
      return adminDepartmentOverride!;
    }
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

  /// Fetches all active queue entries for the user's department.
  /// No parameters to enforce server-side scoping.
  ///
  /// The read is paged: PostgREST caps one response at its max-rows (1,000)
  /// and reports no error when it drops the rest, so an unpaginated select
  /// would hide every entry past the cap - a waiting patient the department
  /// would never see.
  ///
  /// The order is total (oldest first, then the primary key): entries that
  /// share a timestamp keep a fixed place in the order, so a page boundary
  /// never skips or repeats one of them. The read carries no date cutoff, so
  /// an entry that was routed before midnight is still listed and still
  /// closeable, exactly like the web's department queue.
  ///
  /// The server's exact count comes with the read, so the screen can report
  /// the size of the queue instead of the size of one page.
  Future<DepartmentQueuePage> getActiveQueue() async {
    try {
      final department = await _getCurrentUserDept();

      final read = await readAllPages(
        _client
            .from('patient_queue')
            .select('*, patient:patients(*)')
            .eq('department', department)
            .inFilter('status', ['waiting', 'in_progress'])
            .order('created_at', ascending: true),
        uniqueOrderColumn: 'id',
        uniqueOrderAscending: true,
      );

      return DepartmentQueuePage(
        entries: read.rows
            .map((json) => PatientQueue.fromJson(json))
            .toList(),
        total: read.total,
      );
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

  /// Fetches patient demographic information.
  Future<Patient> getPatient(String patientId) async {
    try {
      final response = await _client
          .from('patients')
          .select()
          .eq('id', patientId)
          .single();
      return Patient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  // A successful HTTP response can still update zero rows (including RLS
  // filtering). Keep the saved-results outcome separate from queue completion.
  Future<void> _completeQueue(String patientId, String department) async {
    try {
      final updated = await _client
          .from('patient_queue')
          .update({'status': 'completed'})
          .eq('patient_id', patientId)
          .eq('department', department)
          .inFilter('status', ['waiting', 'in_progress'])
          .select('id');
      if (updated.isEmpty) throw const QueueCompletionFailure();
    } catch (_) {
      throw const QueueCompletionFailure();
    }
  }

  /// Submits laboratory result rows to Supabase and updates patient queue.
  /// Implements sequential non-atomic write logic matching web route.ts.
  Future<void> submitLabResults({
    required String patientId,
    required List<LabResultRow> rows,
  }) async {
    try {
      final department = await _getCurrentUserDept();
      if (rows.isEmpty) return;

      // 1. Insert records rows to public.department_records
      await _client
          .from('department_records')
          .insert(rows.map((row) => row.toJson()).toList());

      await _completeQueue(patientId, department);
    } catch (e) {
      if (e is QueueCompletionFailure) rethrow;
      throw FailureMapper.fromException(e);
    }
  }

  /// Submits free-text findings & impression rows to Supabase and updates patient queue.
  /// Implements sequential non-atomic write logic matching web route.ts.
  ///
  /// Renders a Findings row and, when an impression is provided, a second
  /// Impression row. Laboratory narrative tests reuse this path; the non-lab
  /// entry forms require an impression before calling it.
  Future<void> submitFreeTextResult({
    required String patientId,
    required String testName,
    required String findings,
    required String impression,
    String? notes,
  }) async {
    try {
      final department = await _getCurrentUserDept();
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw const AuthFailure('User not authenticated');
      }

      final sharedNotes = notes?.trim().isEmpty == true ? null : notes?.trim();

      final rowsJson = [
        {
          'patient_id': patientId,
          'recorder_id': userId,
          'department': department,
          'test_type': testName.trim(),
          'test_name': 'Findings',
          'test_value': findings.trim(),
          'unit': null,
          'reference_range_min': null,
          'reference_range_max': null,
          'is_flagged': false,
          'notes': sharedNotes,
        },
        if (impression.trim().isNotEmpty)
          {
            'patient_id': patientId,
            'recorder_id': userId,
            'department': department,
            'test_type': testName.trim(),
            'test_name': 'Impression',
            'test_value': impression.trim(),
            'unit': null,
            'reference_range_min': null,
            'reference_range_max': null,
            'is_flagged': false,
            'notes': sharedNotes,
          }
      ];

      // 1. Insert records rows to public.department_records
      await _client.from('department_records').insert(rowsJson);

      await _completeQueue(patientId, department);
    } catch (e) {
      if (e is QueueCompletionFailure) rethrow;
      throw FailureMapper.fromException(e);
    }
  }
}
