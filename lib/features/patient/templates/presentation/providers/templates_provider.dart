import 'package:flutter/material.dart';
import '../../data/templates_repository.dart';
import '../../../submissions/document_dedup.dart';

class TemplatesProvider extends ChangeNotifier {
  final _repository = TemplatesRepository();

  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get success => _success;

  void resetState() {
    _isLoading = false;
    _errorMessage = null;
    _success = false;
  }

  Future<bool> submitTemplate({
    required String patientId,
    required String uploaderId,
    required String templateId,
    required String templateName,
    required Map<String, dynamic> formValues,
    required String patientName,
    String? dob,
    String? contactNumber,
    String? address,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    _success = false;
    notifyListeners();

    try {
      final duplicateCheck = await checkPendingDuplicate(patientId, templateId);
      final label = getCategoryLabel(templateId);
      if (duplicateCheck.state == DuplicateCheckState.duplicate) {
        throw Exception("You already have a pending [$label] submitted on ${duplicateCheck.duplicateDate}. You can submit a new one once it's reviewed.");
      }
      if (duplicateCheck.state == DuplicateCheckState.failed) {
        // The existing documents could not be read, so the duplicate status is
        // unknown. Do not submit as if it were unique: ask the patient to retry.
        throw Exception("Could not check for a pending [$label] submission. Please check your connection and try again.");
      }
      final Map<String, dynamic> extractedMetadata = {
        'template_id': templateId,
        'template_name': templateName,
        'submission_type': 'template',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'patient_name': patientName,
        ...formValues,
      };

      if (templateId == 'patient-intake') {
        extractedMetadata['date_of_birth'] = dob ?? '';
        extractedMetadata['contact_number'] = contactNumber ?? '';
        extractedMetadata['address'] = address ?? '';
      }

      await _repository.submitTemplateDocument(
        patientId: patientId,
        uploaderId: uploaderId,
        templateId: templateId,
        templateName: templateName,
        extractedMetadata: extractedMetadata,
      );

      _success = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
