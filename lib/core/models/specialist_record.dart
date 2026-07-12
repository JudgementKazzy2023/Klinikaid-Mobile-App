class SpecialistRecord {
  final String id;
  final String specialistPatientId;
  final String specialistId;
  final String testType;
  final String testName;
  final String testValue;
  final String? unit;
  final double? referenceRangeMin;
  final double? referenceRangeMax;
  final bool isFlagged;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  SpecialistRecord({
    required this.id,
    required this.specialistPatientId,
    required this.specialistId,
    required this.testType,
    required this.testName,
    required this.testValue,
    this.unit,
    this.referenceRangeMin,
    this.referenceRangeMax,
    required this.isFlagged,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SpecialistRecord.fromJson(Map<String, dynamic> json) {
    return SpecialistRecord(
      id: json['id'] as String,
      specialistPatientId: json['specialist_patient_id'] as String,
      specialistId: json['specialist_id'] as String,
      testType: json['test_type'] as String,
      testName: json['test_name'] as String,
      testValue: json['test_value'] as String,
      unit: json['unit'] as String?,
      referenceRangeMin: (json['reference_range_min'] as num?)?.toDouble(),
      referenceRangeMax: (json['reference_range_max'] as num?)?.toDouble(),
      isFlagged: json['is_flagged'] as bool? ?? false,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'specialist_patient_id': specialistPatientId,
      'specialist_id': specialistId,
      'test_type': testType,
      'test_name': testName,
      'test_value': testValue,
      'unit': unit,
      'reference_range_min': referenceRangeMin,
      'reference_range_max': referenceRangeMax,
      'is_flagged': isFlagged,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
