import 'patient.dart';
import 'profile.dart'; // For Department enum

enum QueueStatus {
  waiting,
  @JsonKey(name: 'in_progress')
  inProgress,
  completed,
  cancelled;

  static QueueStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'in_progress':
        return QueueStatus.inProgress;
      case 'completed':
        return QueueStatus.completed;
      case 'cancelled':
        return QueueStatus.cancelled;
      case 'waiting':
      default:
        return QueueStatus.waiting;
    }
  }

  String toJsonValue() {
    switch (this) {
      case QueueStatus.waiting:
        return 'waiting';
      case QueueStatus.inProgress:
        return 'in_progress';
      case QueueStatus.completed:
        return 'completed';
      case QueueStatus.cancelled:
        return 'cancelled';
    }
  }
}

enum PriorityLevel {
  routine,
  urgent,
  emergency;

  static PriorityLevel fromString(String value) {
    switch (value.toLowerCase()) {
      case 'urgent':
        return PriorityLevel.urgent;
      case 'emergency':
        return PriorityLevel.emergency;
      case 'routine':
      default:
        return PriorityLevel.routine;
    }
  }

  String toJsonValue() {
    return name;
  }
}

class PatientQueue {
  final int id;
  final String patientId;
  final QueueStatus status;
  final Department department;
  final String? triageNotes;
  final PriorityLevel priorityLevel;
  final int? estimatedWaitMinutes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Patient? patient;

  PatientQueue({
    required this.id,
    required this.patientId,
    required this.status,
    required this.department,
    this.triageNotes,
    required this.priorityLevel,
    this.estimatedWaitMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.patient,
  });

  factory PatientQueue.fromJson(Map<String, dynamic> json) {
    // ID can be int or string from database serialization
    final rawId = json['id'];
    final parsedId = rawId is int ? rawId : int.parse(rawId.toString());

    return PatientQueue(
      id: parsedId,
      patientId: json['patient_id'] as String,
      status: QueueStatus.fromString(json['status'] as String? ?? 'waiting'),
      department: Department.fromString(json['department'] as String?) ?? Department.laboratory,
      triageNotes: json['triage_notes'] as String?,
      priorityLevel: PriorityLevel.fromString(json['priority_level'] as String? ?? 'routine'),
      estimatedWaitMinutes: json['estimated_wait_minutes'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      patient: json['patient'] != null ? Patient.fromJson(json['patient'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'status': status.toJsonValue(),
      'department': department.toJsonValue(),
      'triage_notes': triageNotes,
      'priority_level': priorityLevel.toJsonValue(),
      'estimated_wait_minutes': estimatedWaitMinutes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'patient': patient?.toJson(),
    };
  }
}
