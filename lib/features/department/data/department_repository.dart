import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/patient_queue.dart';
import '../../../core/models/department_record.dart';
import '../../../core/models/patient.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../core/errors/failures.dart';

class DepartmentUnassignedException implements Exception {
  final String message;
  DepartmentUnassignedException([this.message = 'User profile has no department assigned.']);
  
  @override
  String toString() => message;
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

class DepartmentRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// Returns the current authenticated user's ID.
  String? get currentUserId => _client.auth.currentUser?.id;

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

      // 2. Sequential queue update with no transaction/RPC fallback
      final startOfToday = phtStartOfTodayUtc();
      try {
        await _client
            .from('patient_queue')
            .update({'status': 'completed'})
            .eq('patient_id', patientId)
            .eq('department', department)
            .inFilter('status', ['waiting', 'in_progress'])
            .gte('created_at', startOfToday.toIso8601String());
      } catch (e) {
        // Log warning and proceed (web parity)
        debugPrint('Warning: Failed to update queue status in D2: $e');
      }
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Submits free-text findings & impression rows to Supabase and updates patient queue.
  /// Implements sequential non-atomic write logic matching web route.ts.
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

      // Renders exactly two records rows representing Findings and Impression respectively.
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

      // 2. Sequential queue update with no transaction/RPC fallback
      final startOfToday = phtStartOfTodayUtc();
      try {
        await _client
            .from('patient_queue')
            .update({'status': 'completed'})
            .eq('patient_id', patientId)
            .eq('department', department)
            .inFilter('status', ['waiting', 'in_progress'])
            .gte('created_at', startOfToday.toIso8601String());
      } catch (e) {
        // Log warning and proceed (web parity)
        debugPrint('Warning: Failed to update queue status in D2: $e');
      }
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
