import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_client.dart';
import '../domain/quality_assessment.dart';

class DocumentQualityService {
  static final QualityAssessment fallbackAssessment = QualityAssessment(
    score: 50,
    verdict: QualityVerdict.marginal,
    issues: [
      QualityIssue(
        type: QualityIssueType.other,
        severity: QualityIssueSeverity.low,
        description: 'Quality assessment unavailable. Receptionist will review.',
      ),
    ],
  );

  Future<QualityAssessment> assess({
    required String ocrText,
    required String patientName,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'assess-document-quality',
        body: {
          'ocr_text': ocrText,
          'patient_name': patientName,
        },
      );

      if (response.status != 200) {
        debugPrint('Edge function returned status ${response.status}: ${response.data}');
        return fallbackAssessment;
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return QualityAssessment.fromJson(data);
      } else if (data is String) {
        return QualityAssessment.fromJson(jsonDecode(data) as Map<String, dynamic>);
      }
      return fallbackAssessment;
    } catch (e) {
      debugPrint('Error calling assess-document-quality: $e');
      return fallbackAssessment;
    }
  }
}
