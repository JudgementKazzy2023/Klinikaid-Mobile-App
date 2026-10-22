import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/supabase/paged_read.dart';
import '../domain/submission.dart';
import '../domain/submission_detail.dart';
import '../domain/submission_status.dart';
import '../domain/recent_triage_entry.dart';
import '../../../../core/models/patient_queue.dart';

/// Rows shown per page in the reception board.
///
/// The documents table is the largest one reception reads, and the web caps
/// its board for the same reason (3.1 MB of HTML for 557 rows). The mobile
/// board shows one page at a time and discloses the exact total instead of
/// reading the whole table onto a phone.
const int kReceptionSubmissionsPageSize = 100;

/// One page of the reception board, plus the exact number of rows it holds.
class SubmissionsPage {
  const SubmissionsPage({required this.submissions, required this.total});

  /// The submissions of this page, newest first.
  final List<Submission> submissions;

  /// The server's exact count of the submissions the filter matched.
  ///
  /// Independent of how many rows were read back, so the board never reports
  /// the size of one page as the size of the queue.
  final int total;
}

/// Compute the start of today in PHT (UTC+8), expressed as a UTC DateTime.
/// Replicates web's getPhtStartOfToday() exactly — Ralph verified the math.
DateTime phtStartOfTodayUtc() {
  final phtNow = DateTime.now().toUtc().add(const Duration(hours: 8));
  final phtMidnight = DateTime.utc(phtNow.year, phtNow.month, phtNow.day);
  return phtMidnight.subtract(const Duration(hours: 8));
}

class ReceptionRepository {
  final SupabaseClient _client;

  ReceptionRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Fetches one page of the submissions, optionally filtered by status.
  /// Scoped by RLS: Receptionists have full select access to public.documents.
  ///
  /// The read is paged: PostgREST caps one response at its max-rows (1,000)
  /// and reports no error when it drops the rest, so an unpaginated select
  /// would hide every document past the cap - a referral that would never be
  /// actioned.
  ///
  /// The order is total (newest first, then the primary key): documents that
  /// share a timestamp keep a fixed place in the order, so a page boundary
  /// never skips or repeats one of them.
  ///
  /// The exact count is asked for with the first page only; a later page keeps
  /// the total of the first one instead of paying for a second count.
  Future<SubmissionsPage> getSubmissionsPage({
    SubmissionStatus? status,
    int offset = 0,
    int limit = kReceptionSubmissionsPageSize,
  }) async {
    try {
      var query = _client.from('documents').select(
          '*, uploader:profiles(*), patient:patients(*)');

      if (status != null) {
        query = query.eq('status', status.toDbStatus());
      }

      final read = await readPage(
        query.order('created_at', ascending: false),
        uniqueOrderColumn: 'id',
        offset: offset,
        pageSize: limit,
      );

      final List<Submission> submissions = [];
      for (final doc in read.rows) {
        final uploader = doc['uploader'] as Map<String, dynamic>?;
        final patient = doc['patient'] as Map<String, dynamic>?;

        final uploaderName =
            uploader != null ? (uploader['full_name'] as String? ?? '') : '';
        final firstName =
            patient != null ? (patient['first_name'] as String? ?? '') : '';
        final lastName =
            patient != null ? (patient['last_name'] as String? ?? '') : '';

        final patientName = (firstName.isEmpty && lastName.isEmpty)
            ? 'Unknown Patient'
            : '$firstName $lastName'.trim();

        final dbStatus = doc['status'] as String? ?? 'pending';
        final docStatus = SubmissionStatus.fromDbStatus(dbStatus);

        submissions.add(Submission(
          id: doc['id'] as String,
          patientId: doc['patient_id'] as String?,
          patientName: patientName,
          fileName: doc['file_name'] as String? ?? '',
          fileType: doc['file_type'] as String? ?? '',
          uploadedAt: DateTime.parse(doc['created_at'] as String),
          uploadedBy: uploaderName,
          status: docStatus,
        ));
      }

      return SubmissionsPage(submissions: submissions, total: read.total);
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

      final doc = response;
      final uploader = doc['uploader'] as Map<String, dynamic>?;
      final patient = doc['patient'] as Map<String, dynamic>?;

      final uploaderName =
          uploader != null ? (uploader['full_name'] as String? ?? '') : '';
      final firstName =
          patient != null ? (patient['first_name'] as String? ?? '') : '';
      final lastName =
          patient != null ? (patient['last_name'] as String? ?? '') : '';

      final patientName = (firstName.isEmpty && lastName.isEmpty)
          ? 'Unknown Patient'
          : '$firstName $lastName'.trim();

      final dbStatus = doc['status'] as String? ?? 'pending';
      final docStatus = SubmissionStatus.fromDbStatus(dbStatus);

      final submission = Submission(
        id: doc['id'] as String,
        patientId: doc['patient_id'] as String?,
        patientName: patientName,
        fileName: doc['file_name'] as String? ?? '',
        fileType: doc['file_type'] as String? ?? '',
        uploadedAt: DateTime.parse(doc['created_at'] as String),
        uploadedBy: uploaderName,
        status: docStatus,
      );

      // Handle null patient fields gracefully (shows "Unknown Patient" + "—")
      final String patientDob =
          patient != null ? (patient['date_of_birth'] as String? ?? '—') : '—';
      final String patientGender =
          patient != null ? (patient['gender'] as String? ?? '—') : '—';
      final String patientContact =
          patient != null ? (patient['contact_number'] as String? ?? '—') : '—';
      final String patientEmail =
          patient != null ? (patient['email'] as String? ?? '—') : '—';
      final String patientAddress =
          patient != null ? (patient['address'] as String? ?? '—') : '—';

      final Map<String, dynamic>? extractedMetadata = doc['extracted_metadata'] != null
          ? doc['extracted_metadata'] as Map<String, dynamic>?
          : null;

      return SubmissionDetail(
        submission: submission,
        ocrText: doc['ocr_text'] as String?,
        storagePath: doc['file_path'] as String? ?? '',
        patientDob: patientDob,
        patientGender: patientGender,
        patientContact: patientContact,
        patientEmail: patientEmail,
        patientAddress: patientAddress,
        extractedMetadata: extractedMetadata,
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

  /// Route through the authenticated, atomic allocator before approving.
  /// Queue creation and document approval are separate transactions. If approval
  /// fails, the queue remains; a repeated route is refused by the server's open
  /// entry guard. Recover the document separately rather than creating a queue.
  Future<void> approveAndRoute({
    required String documentId,
    required String patientId,
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) async {
    try {
      final vitals = <String, dynamic>{};
      if (bloodPressure != null && bloodPressure.trim().isNotEmpty) {
        vitals['blood_pressure'] = bloodPressure.trim();
      }
      if (weightKg != null) vitals['weight_kg'] = weightKg;
      if (temperatureC != null) vitals['temperature_c'] = temperatureC;

      await _client
          .rpc(
            'triage_patient',
            params: {
              'p_patient_id': patientId,
              'p_department': department,
              'p_priority_level': priority,
              'p_vitals': vitals,
              'p_notes': triageNotes?.trim() ?? '',
            },
          )
          .single();
    } on PostgrestException catch (e) {
      if (e.code == 'PT409') {
        const departments = {
          'laboratory': 'Laboratory',
          'imaging': 'Imaging',
          'ultrasound': 'Ultrasound',
          'ecg': 'ECG',
        };
        final departmentLabel = departments[e.details];
        throw DatabaseFailure(
          'Patient already has an open queue entry'
          '${departmentLabel == null ? '' : ' in $departmentLabel'}. '
          'Resolve the existing entry before routing a new one.',
        );
      }
      throw FailureMapper.fromException(e);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }

    try {
      // Require a returned row: RLS can silently hide a document from UPDATE.
      await _client
          .from('documents')
          .update({'status': 'approved'})
          .eq('id', documentId)
          .select('id')
          .single();
    } catch (e) {
      throw DatabaseFailure(
        'Patient was routed, but document approval could not be confirmed. '
        'Refresh and resolve the document approval separately; '
        'do not route the patient again. ${FailureMapper.fromException(e)}',
      );
    }
  }

  /// Reject a clinical document submission with a reason.
  /// Sets documents.status='rejected' and documents.rejection_reason=reason.
  /// Does NOT modify the patient_queue table.
  Future<void> rejectDocument({
    required String documentId,
    required String reason,
  }) async {
    try {
      await _client
          .from('documents')
          .update({
            'status': 'rejected',
            'rejection_reason': reason,
          })
          .eq('id', documentId);
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Counts active queue entries (waiting or in_progress).
  Future<int> countActiveQueue() async {
    try {
      final res = await _client
          .from('patient_queue')
          .select('id')
          .inFilter('status', ['waiting', 'in_progress'])
          .count(CountOption.exact);
      return res.count;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Counts pending document submissions.
  Future<int> countPendingSubmissions() async {
    try {
      final res = await _client
          .from('documents')
          .select('id')
          .eq('status', 'pending')
          .count(CountOption.exact);
      return res.count;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Counts total queue entries routed since PHT start-of-today.
  Future<int> countRoutedToday() async {
    try {
      final startOfToday = phtStartOfTodayUtc();
      final res = await _client
          .from('patient_queue')
          .select('id')
          .gte('created_at', startOfToday.toIso8601String())
          .count(CountOption.exact);
      return res.count;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }

  /// Retrieves the last N triage entries ordered by created_at DESC.
  Future<List<RecentTriageEntry>> getRecentTriage({int limit = 5}) async {
    try {
      final List<dynamic> rows = await _client
          .from('patient_queue')
          .select('id, patient_id, department, status, created_at, patients(first_name, last_name)')
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map((row) {
        final patientsData = row['patients'];
        String patientName = 'Unknown Patient';
        if (patientsData != null) {
          if (patientsData is Map) {
            final firstName = patientsData['first_name'] as String? ?? '';
            final lastName = patientsData['last_name'] as String? ?? '';
            final joined = '$firstName $lastName'.trim();
            if (joined.isNotEmpty) {
              patientName = joined;
            }
          } else if (patientsData is List && patientsData.isNotEmpty) {
            final firstMap = patientsData.first;
            if (firstMap is Map) {
              final firstName = firstMap['first_name'] as String? ?? '';
              final lastName = firstMap['last_name'] as String? ?? '';
              final joined = '$firstName $lastName'.trim();
              if (joined.isNotEmpty) {
                patientName = joined;
              }
            }
          }
        }

        return RecentTriageEntry(
          patientName: patientName,
          department: row['department'] as String? ?? 'laboratory',
          status: QueueStatus.fromString(row['status'] as String? ?? 'waiting'),
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
