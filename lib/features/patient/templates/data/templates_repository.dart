import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/uuid_generator.dart';

class TemplatesRepository {
  final _client = SupabaseService.client;

  Future<String> submitTemplateDocument({
    required String patientId,
    required String uploaderId,
    required String templateId,
    required String templateName,
    required Map<String, dynamic> extractedMetadata,
  }) async {
    try {
      final timestampMs = DateTime.now().millisecondsSinceEpoch;
      
      // Date format MMM DD, YYYY (e.g. Jul 14, 2026) to match web's short date formatted string
      final date = DateTime.now();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final formattedDate = "${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}";
      
      final fileName = "$templateName - $formattedDate";
      final filePath = "template://$templateId-$timestampMs";
      final uuid = UuidGenerator.generateV4();

      final docPayload = {
        'id': uuid,
        'patient_id': patientId,
        'uploader_id': uploaderId,
        'file_name': fileName,
        'file_path': filePath,
        'file_type': 'template',
        'status': 'pending',
        'extracted_metadata': extractedMetadata,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await _client
          .from('documents')
          .insert(docPayload)
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      throw FailureMapper.fromException(e);
    }
  }
}
