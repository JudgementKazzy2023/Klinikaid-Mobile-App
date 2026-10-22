import 'patient.dart';
import 'profile.dart'; // For Department enum

enum QueueStatus {
  waiting,
  @JsonKey(name: 'in_progress')
  inProgress,
  completed,
  cancelled;

  /// Parses a status string without inventing one: an unrecognized value
  /// returns null instead of being read as [QueueStatus.waiting].
  ///
  /// Anything that must not silently become "waiting" -- an unknown row, a
  /// stale cache entry, a status added after this build -- goes through here.
  static QueueStatus? tryFromString(String value) {
    switch (value.toLowerCase()) {
      case 'in_progress':
      case 'inprogress': // Legacy cache used the Dart enum name.
        return QueueStatus.inProgress;
      case 'completed':
        return QueueStatus.completed;
      case 'cancelled':
        return QueueStatus.cancelled;
      case 'waiting':
        return QueueStatus.waiting;
      default:
        return null;
    }
  }

  static QueueStatus fromString(String value) {
    return tryFromString(value) ?? QueueStatus.waiting;
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

/// Whether [rawStatus] counts as a current queue membership.
///
/// This is the rule the web patient dashboard answers the issue with:
/// `patient_queue` is filtered with `status IN ('waiting', 'in_progress')` and
/// ordered newest first, so completed and cancelled history is never the
/// current queue. The comparison happens on the raw string the source spelled,
/// because [QueueStatus.fromString] maps anything it does not recognize to
/// `waiting`, which would turn an unknown status into a live queue entry.
bool isActiveQueueStatus(String rawStatus) {
  final status = QueueStatus.tryFromString(rawStatus);
  return status == QueueStatus.waiting || status == QueueStatus.inProgress;
}

class PatientQueue {
  final int id;
  final String patientId;
  final QueueStatus status;

  /// The status exactly as the source spelled it (server row or cache row).
  ///
  /// [status] is the parsed value and an unknown string parses to `waiting`,
  /// so this is what tells a genuinely unknown status apart from a real
  /// `waiting` one. [isActiveQueueStatus] reads it.
  final String rawStatus;
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
    String? rawStatus,
  }) : rawStatus = rawStatus ?? status.toJsonValue();

  factory PatientQueue.fromJson(Map<String, dynamic> json) {
    // ID can be int or string from database serialization
    final rawId = json['id'];
    final parsedId = rawId is int ? rawId : int.parse(rawId.toString());

    final rawStatus = json['status'] as String? ?? 'waiting';

    return PatientQueue(
      id: parsedId,
      patientId: json['patient_id'] as String,
      status: QueueStatus.fromString(rawStatus),
      rawStatus: rawStatus,
      department:
          Department.fromString(json['department'] as String?) ??
          Department.laboratory,
      triageNotes: json['triage_notes'] as String?,
      priorityLevel: PriorityLevel.fromString(
        json['priority_level'] as String? ?? 'routine',
      ),
      estimatedWaitMinutes: json['estimated_wait_minutes'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      patient: json['patient'] != null
          ? Patient.fromJson(json['patient'] as Map<String, dynamic>)
          : null,
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
