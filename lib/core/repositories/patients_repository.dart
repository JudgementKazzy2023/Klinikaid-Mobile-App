import '../models/patient.dart';
import '../supabase/supabase_client.dart';
import '../errors/failures.dart';

/// Repository that manages data retrieval and updates for the `patients` table.
class PatientsRepository {
  final _client = SupabaseService.client;

  /// Retrieves the patient record associated with the given [profileId].
  /// Returns `null` if the record does not exist (e.g., user is not yet onboarded).
  /// Throws a [Failure] on error or RLS denial.
  Future<Patient?> getPatientByProfileId(String profileId) async {
    try {
      final response = await _client
          .from('patients')
          .select()
          .eq('profile_id', profileId)
          .maybeSingle();
      if (response == null) return null;
      return Patient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Inserts a new patient record.
  /// Throws a [Failure] on error.
  Future<Patient> createPatient(Patient patient) async {
    try {
      final response = await _client
          .from('patients')
          .insert(patient.toJson())
          .select()
          .single();
      return Patient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Updates patient clinical details.
  /// Throws a [Failure] on error.
  Future<Patient> updatePatient(Patient patient) async {
    try {
      final response = await _client
          .from('patients')
          .update(patient.toJson())
          .eq('id', patient.id)
          .select()
          .single();
      return Patient.fromJson(response);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves all patients, ordered by last_name.
  Future<List<Patient>> getAllPatients() async {
    try {
      final response = await _client
          .from('patients')
          .select()
          .order('last_name', ascending: true);

      return (response as List)
          .map((json) => Patient.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}

