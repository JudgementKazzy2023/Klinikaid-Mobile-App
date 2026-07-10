import 'submission_status.dart';

class Submission {
  final String id;
  final String? patientId;
  final String patientName;
  final String fileName;
  final String fileType;
  final DateTime uploadedAt;
  final String uploadedBy;
  final SubmissionStatus status;

  Submission({
    required this.id,
    this.patientId,
    required this.patientName,
    required this.fileName,
    required this.fileType,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.status,
  });
}
