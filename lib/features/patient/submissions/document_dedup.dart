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

Future<String?> checkPendingDuplicate(String patientId, String category) async {
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
        return formattedDate;
      }
    }
  } catch (e, stack) {
    print("checkPendingDuplicate error: $e\n$stack");
  }
  return null;
}
