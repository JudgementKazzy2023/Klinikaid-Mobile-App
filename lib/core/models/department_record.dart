import 'patient.dart';
import 'profile.dart';

enum ReferenceRangeStatus {
  normal,
  @JsonKey(name: 'critical_high')
  criticalHigh,
  @JsonKey(name: 'critical_low')
  criticalLow,
  inconclusive;

  static ReferenceRangeStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'critical_high':
        return ReferenceRangeStatus.criticalHigh;
      case 'critical_low':
        return ReferenceRangeStatus.criticalLow;
      case 'inconclusive':
        return ReferenceRangeStatus.inconclusive;
      case 'normal':
      default:
        return ReferenceRangeStatus.normal;
    }
  }

  String toJsonValue() {
    switch (this) {
      case ReferenceRangeStatus.normal:
        return 'normal';
      case ReferenceRangeStatus.criticalHigh:
        return 'critical_high';
      case ReferenceRangeStatus.criticalLow:
        return 'critical_low';
      case ReferenceRangeStatus.inconclusive:
        return 'inconclusive';
    }
  }
}

class DepartmentRecord {
  final String id;
  final String patientId;
  final String recorderId;
  final Department department;
  final String testType;
  final Map<String, dynamic> testResults;
  final ReferenceRangeStatus referenceRangeStatus;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Patient? patient;
  final Profile? recorder;

  DepartmentRecord({
    required this.id,
    required this.patientId,
    required this.recorderId,
    required this.department,
    required this.testType,
    required this.testResults,
    required this.referenceRangeStatus,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.patient,
    this.recorder,
  });

  factory DepartmentRecord.fromJson(Map<String, dynamic> json) {
    return DepartmentRecord(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      recorderId: json['recorder_id'] as String,
      department: Department.fromString(json['department'] as String?) ?? Department.laboratory,
      testType: json['test_type'] as String? ?? '',
      testResults: json['test_results'] as Map<String, dynamic>? ?? {},
      referenceRangeStatus: ReferenceRangeStatus.fromString(json['reference_range_status'] as String? ?? 'normal'),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      patient: json['patient'] != null ? Patient.fromJson(json['patient'] as Map<String, dynamic>) : null,
      recorder: json['recorder'] != null ? Profile.fromJson(json['recorder'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'recorder_id': recorderId,
      'department': department.toJsonValue(),
      'test_type': testType,
      'test_results': testResults,
      'reference_range_status': referenceRangeStatus.toJsonValue(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'patient': patient?.toJson(),
      'recorder': recorder?.toJson(),
    };
  }
}
