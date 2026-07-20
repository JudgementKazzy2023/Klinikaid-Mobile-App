import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/supabase/supabase_client.dart';

class PatientProvisioningException implements Exception {
  final String message;
  final bool functionRan;

  const PatientProvisioningException(this.message, {required this.functionRan});

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
            throw const PatientProvisioningException(
              'Patient provisioning response was invalid.',
              functionRan: true,
            );
          }
        }
        return null;
      }

      throw PatientProvisioningException(
        json['message'] as String? ?? 'Patient provisioning failed.',
        functionRan: true,
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final json = details is Map<String, dynamic> ? details : <String, dynamic>{};
      throw PatientProvisioningException(
        json['message'] as String? ?? e.reasonPhrase ?? 'Patient provisioning failed.',
        functionRan: true,
      );
    } on TimeoutException catch (e) {
      throw PatientProvisioningException(
        e.message ?? 'Patient provisioning timed out.',
        functionRan: false,
      );
    } on SocketException {
      throw const PatientProvisioningException(
        'You are currently offline. Please check your network connection.',
        functionRan: false,
      );
    } on PatientProvisioningException {
      rethrow;
    } catch (e) {
      throw PatientProvisioningException(e.toString(), functionRan: false);
    }
  }
}

class MockPatientProvisioningService implements PatientProvisioningService {
  bool shouldFail = false;
  bool functionRan = true;
  bool wasCalled = false;
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
    if (shouldFail) {
      throw PatientProvisioningException(
        functionRan ? 'Patient provisioning failed.' : 'Network failure.',
        functionRan: functionRan,
      );
    }
    return patient;
  }
}
