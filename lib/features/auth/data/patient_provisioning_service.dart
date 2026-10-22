import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/supabase/supabase_client.dart';

/// How a patient provisioning attempt ended.
enum PatientProvisioningOutcome {
  /// The function answered and refused the request. Nothing was written.
  rejected,

  /// The outcome is unknown: the request may have been applied before the
  /// connection dropped, so a patient row may already exist. The account must
  /// be kept in this case.
  uncertain,
}

class PatientProvisioningException implements Exception {
  final String message;
  final PatientProvisioningOutcome outcome;

  const PatientProvisioningException(this.message, {required this.outcome});

  @override
  String toString() => message;
}

abstract class PatientProvisioningService {
  Future<Patient?> createPatientRecord({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  });
}

class SupabasePatientProvisioningService implements PatientProvisioningService {
  final _client = SupabaseService.client;

  @override
  Future<Patient?> createPatientRecord({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-patient-record',
        method: HttpMethod.post,
        body: {
          'first_name': firstName,
          'last_name': lastName,
          'date_of_birth': dateOfBirth.toIso8601String().substring(0, 10),
          'gender': gender.toJsonValue(),
          'contact_number': contactNumber,
          'email': email,
          'address': address,
        },
      );

      final data = response.data;
      final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final patientJson = json['patient'];
      if (response.status >= 200 && response.status < 300) {
        if (patientJson is Map<String, dynamic>) {
          try {
            return Patient.fromJson(patientJson);
          } catch (e) {
            // The function answered with success, so the row exists: only the
            // response could not be read.
            throw const PatientProvisioningException(
              'Patient provisioning response was invalid.',
              outcome: PatientProvisioningOutcome.uncertain,
            );
          }
        }
        return null;
      }

      throw PatientProvisioningException(
        json['message'] as String? ?? 'Patient provisioning failed.',
        outcome: PatientProvisioningOutcome.rejected,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final json = details is Map<String, dynamic> ? details : <String, dynamic>{};
      throw PatientProvisioningException(
        json['message'] as String? ?? e.reasonPhrase ?? 'Patient provisioning failed.',
        outcome: PatientProvisioningOutcome.rejected,
      );
    } on TimeoutException catch (e) {
      throw PatientProvisioningException(
        e.message ?? 'Patient provisioning timed out.',
        outcome: PatientProvisioningOutcome.uncertain,
      );
    } on SocketException {
      throw const PatientProvisioningException(
        'You are currently offline. Please check your network connection.',
        outcome: PatientProvisioningOutcome.uncertain,
      );
    } on PatientProvisioningException {
      rethrow;
    } catch (e) {
      throw PatientProvisioningException(
        e.toString(),
        outcome: PatientProvisioningOutcome.uncertain,
      );
    }
  }
}

class MockPatientProvisioningService implements PatientProvisioningService {
  bool shouldFail = false;
  PatientProvisioningOutcome outcome = PatientProvisioningOutcome.rejected;
  bool wasCalled = false;
  int callCount = 0;

  /// Fails the first [failFirstCalls] calls and succeeds afterwards.
  int failFirstCalls = 0;
  Patient? patient;

  @override
  Future<Patient?> createPatientRecord({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    wasCalled = true;
    callCount++;
    if (shouldFail || callCount <= failFirstCalls) {
      throw PatientProvisioningException(
        outcome == PatientProvisioningOutcome.rejected
            ? 'Patient provisioning failed.'
            : 'Network failure.',
        outcome: outcome,
      );
    }
    return patient;
  }
}
