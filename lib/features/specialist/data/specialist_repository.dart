import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/supabase/paged_read.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/models/specialist_patient.dart';
import '../../../../core/models/specialist_record.dart';

class SpecialistRepository {
  SpecialistRepository({SupabaseClient? client}) : _injectedClient = client;
  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  /// Fetch all private patients of the logged-in specialist.
  /// RLS auto-scopes query to auth.uid().
  ///
  /// The read is paged: PostgREST caps one response at its max-rows (1,000) and
  /// reports no error when it drops the rest, so an unpaginated select would
  /// hide every patient past the cap.
  ///
  /// The order is total (newest first, then the primary key): patients that
  /// share a timestamp keep a fixed place in the order, so a page boundary
  /// never skips or repeats one of them.
  Future<List<SpecialistPatient>> getMyPatients() async {
    try {
      final read = await readAllPages(
        _client
            .from('specialist_patients')
            .select()
            .order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
      );

      return read.rows
          .map((json) => SpecialistPatient.fromJson(json))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Insert a new private patient.
  /// RLS will enforce that specialist_id == auth.uid().
  Future<SpecialistPatient> addPatient({
    required String firstName,
    required String lastName,
    required DateTime dob,
    required String gender,
    String? contactNumber,
    String? email,
    String? address,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const AuthFailure('Unauthenticated user.');
      }

      final response = await _client
          .from('specialist_patients')
          .insert({
            'specialist_id': uid,
            'first_name': firstName,
            'last_name': lastName,
            'date_of_birth': dob.toIso8601String().substring(0, 10),
            'gender': gender,
            'contact_number': contactNumber?.trim().isEmpty == true ? null : contactNumber?.trim(),
            'email': email?.trim().isEmpty == true ? null : email?.trim(),
            'address': address?.trim().isEmpty == true ? null : address?.trim(),
          })
          .select()
          .single();

      return SpecialistPatient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Archive the patient and records atomically through the ownership-checked RPC.
  Future<bool> archivePatient(String patientId) async {
    try {
      final result = await _client.rpc('archive_specialist_patient',
          params: {'p_patient_id': patientId});
      return result == true;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Get a single private patient by ID.
  Future<SpecialistPatient> getPatientById(String patientId) async {
    try {
      final response = await _client
          .from('specialist_patients')
          .select()
          .eq('id', patientId)
          .single();

      return SpecialistPatient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Fetches raw data to derive dashboard aggregates client-side.
  /// Returns a Map containing:
  /// - 'patients': `List<SpecialistPatient>`
  /// - 'records': `List<SpecialistRecord>`
  /// - 'recordsWithPatient': `List<Map<String, dynamic>>` (raw JSON to resolve joined patient info)
  /// - 'total_patients': int (the server's exact patient count)
  ///
  /// Both reads are paged so the aggregates cover every row and not just the
  /// first page the server was willing to return, and both are ordered totally
  /// (newest first, then the primary key) so a page boundary cannot skip or
  /// repeat a row that shares a timestamp.
  Future<Map<String, dynamic>> getDashboardRawData() async {
    try {
      final patientsRead = await readAllPages(
        _client
            .from('specialist_patients')
            .select()
            .order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
      );

      final recordsRead = await readAllPages(
        _client
            .from('specialist_records')
            .select('*, patient:specialist_patients(*)')
            .order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
      );

      final patients = patientsRead.rows
          .map((json) => SpecialistPatient.fromJson(json))
          .toList();

      final records = recordsRead.rows
          .map((json) => SpecialistRecord.fromJson(json))
          .toList();

      return {
        'patients': patients,
        'records': records,
        'raw_records': recordsRead.rows,
        'total_patients': patientsRead.total,
      };
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Submit a batch of record rows to specialist_records.
  /// Resolves specialist_id from session (never client-supplied).
  Future<void> submitRecord({
    required String specialistPatientId,
    required String testType,
    required List<SpecialistRecordRow> rows,
    String? notes,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const AuthFailure('Unauthenticated user.');
      }

      final payload = rows.map((row) => {
        'specialist_patient_id': specialistPatientId,
        'specialist_id': uid,
        'test_type': testType,
        'test_name': row.testName,
        'test_value': row.testValue,
        'unit': row.unit,
        'reference_range_min': row.referenceRangeMin,
        'reference_range_max': row.referenceRangeMax,
        'is_flagged': row.isFlagged,
        'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      }).toList();

      await _client.from('specialist_records').insert(payload);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieve the records for a specific private patient.
  ///
  /// Paged, so a patient with more records than the server's row cap still
  /// shows all of them, and ordered totally (oldest first, then the primary
  /// key) so records that share a timestamp keep a fixed place in the order.
  Future<List<SpecialistRecord>> getPatientRecords(String specialistPatientId) async {
    try {
      final read = await readAllPages(
        _client
            .from('specialist_records')
            .select()
            .eq('specialist_patient_id', specialistPatientId)
            .order('created_at', ascending: true),
        uniqueOrderColumn: 'id',
        uniqueOrderAscending: true,
      );

      return read.rows
          .map((json) => SpecialistRecord.fromJson(json))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}

/// Payload model container for inserting into specialist_records.
class SpecialistRecordRow {
  final String testName;
  final String testValue;
  final String? unit;
  final double? referenceRangeMin;
  final double? referenceRangeMax;
  final bool isFlagged;

  SpecialistRecordRow({
    required this.testName,
    required this.testValue,
    this.unit,
    this.referenceRangeMin,
    this.referenceRangeMax,
    required this.isFlagged,
  });
}
