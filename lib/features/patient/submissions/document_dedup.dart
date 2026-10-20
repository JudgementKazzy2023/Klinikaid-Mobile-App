import '../../../../core/errors/failures.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../templates/document_templates.dart';

String resolveDocumentCategory(String fileType, Map<String, dynamic>? metadata) {
  if (fileType == 'template') {
    return metadata?['template_id'] as String? ?? 'other';
  } else {
    return metadata?['document_type'] as String? ?? 'other';
  }
}

String getCategoryLabel(String category) {
  if (category == 'other') {
    return 'Other';
  }
  final match = clinicTemplates.where((t) => t.id == category);
  if (match.isNotEmpty) {
    return match.first.name;
  }
  return category;
}

/// The three outcomes of a pending-duplicate check.
///
/// There is deliberately no outcome meaning "the read failed but treat it as
/// clear": a read that never completed is not evidence that the patient has no
/// pending document in the category.
enum DuplicateCheckState {
  /// A pending document in the same category already exists.
  duplicate,

  /// The read succeeded and no pending document in the category exists.
  clear,

  /// The read failed, so the duplicate status is unknown.
  failed,
}

/// The result of [checkPendingDuplicate].
class DuplicateCheckResult {
  /// Which of the three outcomes the check produced.
  final DuplicateCheckState state;

  /// Formatted submission date of the matching pending document.
  /// Only set when [state] is [DuplicateCheckState.duplicate].
  final String? duplicateDate;

  /// The error that stopped the check.
  /// Only set when [state] is [DuplicateCheckState.failed].
  final Object? error;

  /// Whether the failed read was a connectivity failure, i.e. the device
  /// could not reach the server at all.
  ///
  /// Only meaningful when [state] is [DuplicateCheckState.failed]. A
  /// connectivity failure means the check says nothing about duplicates (the
  /// server was never reached), while any other failure means the server was
  /// reached but the read was refused or could not be parsed.
  final bool isNetworkFailure;

  const DuplicateCheckResult._(
    this.state,
    this.duplicateDate,
    this.error,
    this.isNetworkFailure,
  );

  /// A pending document in the same category exists, submitted on [date].
  const DuplicateCheckResult.duplicate(String date)
      : this._(DuplicateCheckState.duplicate, date, null, false);

  /// The read succeeded and no pending document in the category exists.
  const DuplicateCheckResult.clear()
      : this._(DuplicateCheckState.clear, null, null, false);

  /// The read failed with [error]; the duplicate status is unknown.
  ///
  /// [isNetworkFailure] reports whether the read failed because the device was
  /// offline rather than because the server refused or returned bad data.
  DuplicateCheckResult.failed(Object error)
      : this._(
          DuplicateCheckState.failed,
          null,
          error,
          FailureMapper.isNetworkFailure(error),
        );
}

/// Checks whether the patient already has a pending document in [category].
///
/// Returns [DuplicateCheckState.duplicate] with the submission date when one
/// exists, [DuplicateCheckState.clear] when the read succeeded and none
/// exists, and [DuplicateCheckState.failed] when the read could not be
/// completed. A failed read is never reported as "no duplicate": callers must
/// not submit a document as unique while the check is unverified.
///
/// When the read failed because the device was offline, the result reports
/// [DuplicateCheckResult.isNetworkFailure] so the caller can take the same
/// offline branch it takes for a failed upload instead of blocking the
/// submission.
Future<DuplicateCheckResult> checkPendingDuplicate(String patientId, String category) async {
  try {
    final response = await SupabaseService.client
        .from('documents')
        .select('file_type, status, extracted_metadata, created_at')
        .eq('patient_id', patientId)
        .eq('status', 'pending');

    for (final doc in response as List) {
      final fileType = doc['file_type'] as String? ?? '';
      final metadata = doc['extracted_metadata'] as Map<String, dynamic>?;
      final resolvedCategory = resolveDocumentCategory(fileType, metadata);

      final status = doc['status'] as String? ?? '';
      if (status == 'pending' && resolvedCategory == category) {
        final createdAtStr = doc['created_at'] as String;
        final date = DateTime.parse(createdAtStr).toLocal();
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final formattedDate = "${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}";
        return DuplicateCheckResult.duplicate(formattedDate);
      }
    }
    return const DuplicateCheckResult.clear();
  } catch (e, stack) {
    print("checkPendingDuplicate error: $e\n$stack");
    return DuplicateCheckResult.failed(e);
  }
}
