import 'package:flutter/material.dart';
import '../../data/templates_repository.dart';

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
