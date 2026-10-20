import 'patient.dart';
import 'profile.dart';

enum ReferenceRangeStatus {
  normal,
  flagged,
  inconclusive;

  static ReferenceRangeStatus fromString(String value) {
    switch (value.toLowerCase()) {
      // Legacy DB values — both map to flagged going forward
      case 'critical_high':
      case 'critical_low':
      case 'flagged':
        return ReferenceRangeStatus.flagged;
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
      case ReferenceRangeStatus.flagged:
        return 'flagged';
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

  /// The unit of the measured value, when the row carries one.
  String? get unit {
    final value = testResults['unit'];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// The lower bound of the reference range, when the row carries one.
  double? get referenceRangeMin => _asDouble(testResults['reference_range_min']);

  /// The upper bound of the reference range, when the row carries one.
  double? get referenceRangeMax => _asDouble(testResults['reference_range_max']);

  /// True when the result is flagged as abnormal.
  bool get isFlagged => referenceRangeStatus == ReferenceRangeStatus.flagged;

  /// The reference range of the measurement, formatted for display.
  /// Null when the row carries no bounds.
  String? get referenceRangeLabel {
    final min = referenceRangeMin;
    final max = referenceRangeMax;
    if (min == null || max == null) return null;
    final range = '${_formatNumber(min)} - ${_formatNumber(max)}';
    final unit = this.unit;
    return unit == null ? range : '$range $unit';
  }

  /// The measured value, with its unit when the row carries one.
  String get valueLabel {
    final value = testResults['test_value']?.toString() ?? '';
    final unit = this.unit;
    if (unit == null) return value;
    return value.isEmpty ? unit : '$value $unit';
  }

  factory DepartmentRecord.fromJson(Map<String, dynamic> json) {
    return DepartmentRecord(
      id: json['id'] as String,
      patientId: json['patient_id'] as String,
      recorderId: json['recorder_id'] as String,
      department: Department.fromString(json['department'] as String?) ?? Department.laboratory,
      testType: json['test_type'] as String? ?? '',
      testResults: _parseTestResults(json),
      referenceRangeStatus: ReferenceRangeStatus.fromString(
        json['reference_range_status'] as String? ??
        ((json['is_flagged'] as bool? ?? false) ? 'flagged' : 'normal')
      ),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      patient: json['patient'] != null ? Patient.fromJson(json['patient'] as Map<String, dynamic>) : null,
      recorder: json['recorder'] != null ? Profile.fromJson(json['recorder'] as Map<String, dynamic>) : null,
    );
  }

  /// Builds the result map of a department record row.
  ///
  /// The `department_records` table stores one measurement per row, flat:
  /// `test_name`, `test_value`, `unit`, `reference_range_min`,
  /// `reference_range_max` and `is_flagged` are columns of the row itself, not
  /// fields of a nested object. Reading only the name and the value dropped the
  /// unit and the reference bounds, so a flagged result arrived without the
  /// range that explains it.
  static Map<String, dynamic> _parseTestResults(Map<String, dynamic> json) {
    final results = <String, dynamic>{};

    final nested = json['test_results'];
    if (nested is Map) {
      nested.forEach((key, value) => results['$key'] = value);
    }

    for (final column in const [
      'test_name',
      'test_value',
      'unit',
      'reference_range_min',
      'reference_range_max',
    ]) {
      final value = json[column];
      if (value != null) results[column] = value;
    }

    return results;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
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
