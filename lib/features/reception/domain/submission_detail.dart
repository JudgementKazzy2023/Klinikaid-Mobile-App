import 'submission.dart';

class SubmissionDetail {
  final Submission submission;
  final String? ocrText;
  final String storagePath;
  final String patientDob;
  final String patientGender;
  final String patientContact;
  final String patientEmail;
  final String patientAddress;

  SubmissionDetail({
    required this.submission,
    this.ocrText,
    required this.storagePath,
    required this.patientDob,
    required this.patientGender,
    required this.patientContact,
    required this.patientEmail,
    required this.patientAddress,
  });
}
