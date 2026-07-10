import '../../../../core/models/patient_queue.dart';

/// Represents a patient triage entry on the Receptionist Dashboard.
class RecentTriageEntry {
  final String patientName;
  final String department;
  final QueueStatus status;
  final DateTime createdAt;

  const RecentTriageEntry({
    required this.patientName,
    required this.department,
    required this.status,
    required this.createdAt,
  });
}
