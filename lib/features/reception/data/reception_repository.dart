import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../domain/submission.dart';
import '../domain/submission_detail.dart';
import '../domain/submission_status.dart';

class ReceptionRepository {
  final _client = Supabase.instance.client;

  /// Fetch all submissions, optionally filtered by status.
  /// Scoped by RLS: Receptionists have full select access to public.documents.
  Future<List<Submission>> getSubmissions({SubmissionStatus? status}) async {
    try {
      var query = _client.from('documents').select('*, uploader:profiles(*), patient:patients(*)');

      if (status != null) {
        query = query.eq('status', status.toDbStatus());
      }

      final response = await query.order('created_at', ascending: false);

      final List<Submission> submissions = [];
      for (final json in response as List) {
        final doc = json as Map<String, dynamic>;

        final uploader = doc['uploader'] as Map<String, dynamic>?;
        final patient = doc['patient'] as Map<String, dynamic>?;

        final uploaderName = uploader != null ? (uploader['full_name'] as String? ?? '') : '';
        final firstName = patient != null ? (patient['first_name'] as String? ?? '') : '';
        final lastName = patient != null ? (patient['last_name'] as String? ?? '') : '';
        
        final patientName = (firstName.isEmpty && lastName.isEmpty)
            ? 'Unknown Patient'
            : '$firstName $lastName'.trim();

        final dbStatus = doc['status'] as String? ?? 'pending';
        final docStatus = SubmissionStatus.fromDbStatus(dbStatus);

        submissions.add(Submission(
          id: doc['id'] as String,
          patientName: patientName,
          fileName: doc['file_name'] as String? ?? '',
          fileType: doc['file_type'] as String? ?? '',
          uploadedAt: DateTime.parse(doc['created_at'] as String),
          uploadedBy: uploaderName,
          status: docStatus,
        ));
      }

      return submissions;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Fetch a single submission's detail by ID.
  Future<SubmissionDetail> getSubmissionDetail(String id) async {
    try {
      final response = await _client
          .from('documents')
          .select('*, uploader:profiles(*), patient:patients(*)')
          .eq('id', id)
          .single();

      final doc = response as Map<String, dynamic>;
      final uploader = doc['uploader'] as Map<String, dynamic>?;
      final patient = doc['patient'] as Map<String, dynamic>?;

      final uploaderName = uploader != null ? (uploader['full_name'] as String? ?? '') : '';
      final firstName = patient != null ? (patient['first_name'] as String? ?? '') : '';
      final lastName = patient != null ? (patient['last_name'] as String? ?? '') : '';
      
      final patientName = (firstName.isEmpty && lastName.isEmpty)
          ? 'Unknown Patient'
          : '$firstName $lastName'.trim();

      final dbStatus = doc['status'] as String? ?? 'pending';
      final docStatus = SubmissionStatus.fromDbStatus(dbStatus);

      final submission = Submission(
        id: doc['id'] as String,
        patientName: patientName,
        fileName: doc['file_name'] as String? ?? '',
        fileType: doc['file_type'] as String? ?? '',
        uploadedAt: DateTime.parse(doc['created_at'] as String),
        uploadedBy: uploaderName,
        status: docStatus,
      );

      // Handle null patient fields gracefully (shows "Unknown Patient" + "—")
      final String patientDob = patient != null ? (patient['date_of_birth'] as String? ?? '—') : '—';
      final String patientGender = patient != null ? (patient['gender'] as String? ?? '—') : '—';
      final String patientContact = patient != null ? (patient['contact_number'] as String? ?? '—') : '—';
      final String patientEmail = patient != null ? (patient['email'] as String? ?? '—') : '—';
      final String patientAddress = patient != null ? (patient['address'] as String? ?? '—') : '—';

      return SubmissionDetail(
        submission: submission,
        ocrText: doc['ocr_text'] as String?,
        storagePath: doc['file_path'] as String? ?? '',
        patientDob: patientDob,
        patientGender: patientGender,
        patientContact: patientContact,
        patientEmail: patientEmail,
        patientAddress: patientAddress,
      );
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Get temporary signed URL of the document file in Supabase Storage.
  Future<String> getOriginalDocumentUrl(String id) async {
    try {
      final docResponse = await _client
          .from('documents')
          .select('file_path')
          .eq('id', id)
          .single();

      final filePath = docResponse['file_path'] as String;

      final response = await _client.storage
          .from('patient-documents')
          .createSignedUrl(filePath, 3600); // 1 hour expiry

      return response;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
