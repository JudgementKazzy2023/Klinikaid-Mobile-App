import 'package:flutter/material.dart';
import '../../data/templates_repository.dart';
import '../../document_templates.dart';
import '../../template_answers.dart';
import '../../../submissions/document_dedup.dart';

class TemplatesProvider extends ChangeNotifier {
  final _repository = TemplatesRepository();

  bool _isLoading = false;
  String? _errorMessage;
  bool _success = false;

  /// The consent fields the patient declined in the last submission.
  List<String> _declinedConsentFields = const <String>[];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get success => _success;

  /// The consent fields the patient declined in the last submission.
  ///
  /// A declined form consent is a valid answer, not a failure: the form is
  /// submitted and reception reviews the decline. It is kept apart from the
  /// account's data-privacy consent, which the auth provider tracks on its
  /// own — declining a clinic form never withdraws the account consent and
  /// never trips the account consent gate.
  List<String> get lastDeclinedConsentFields => _declinedConsentFields;

  void resetState() {
    _isLoading = false;
    _errorMessage = null;
    _success = false;
    _declinedConsentFields = const <String>[];
  }

  /// The consent fields of [templateId] the patient declined in [formValues].
  List<String> declinedFormConsentFields(
    String templateId,
    Map<String, dynamic> formValues,
  ) {
    final template = clinicTemplateById(templateId);
    if (template == null) return const <String>[];
    return declinedConsentFields(template, formValues)
        .map((field) => field.key)
        .toList();
  }

  /// The metadata stored with a template submission.
  ///
  /// Answers are stored trimmed, the way the shared rules count them, and a
  /// declined consent is stored as the declined answer it is: the patient may
  /// decline a clinic form, and reception reviews it. Only the form's own
  /// questions are stored, so the shared review on the other client sees the
  /// same fields the patient answered.
  Map<String, dynamic> buildExtractedMetadata({
    required String templateId,
    required String templateName,
    required Map<String, dynamic> formValues,
    required String patientName,
    String? dob,
    String? contactNumber,
    String? address,
  }) {
    final Map<String, dynamic> answers = {
      for (final entry in formValues.entries)
        entry.key: entry.value.toString().trim(),
    };

    final Map<String, dynamic> extractedMetadata = {
      'template_id': templateId,
      'template_name': templateName,
      'submission_type': 'template',
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'patient_name': patientName,
      ...answers,
    };

    if (templateId == 'patient-intake') {
      extractedMetadata['date_of_birth'] = dob ?? '';
      extractedMetadata['contact_number'] = contactNumber ?? '';
      extractedMetadata['address'] = address ?? '';
    }

    return extractedMetadata;
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
        // unknown. Do not submit as if it were unique: ask the patient to
        // retry.
        //
        // Unlike the document upload path, template submissions have no
        // offline queue to fall back on (TemplatesRepository only inserts the
        // row in Postgres), so a failed check blocks the submission whatever
        // the cause of the failure is.
        throw Exception("Could not check for a pending [$label] submission. Please check your connection and try again.");
      }
      final extractedMetadata = buildExtractedMetadata(
        templateId: templateId,
        templateName: templateName,
        formValues: formValues,
        patientName: patientName,
        dob: dob,
        contactNumber: contactNumber,
        address: address,
      );

      // A declined consent travels with the form; it never blocks the
      // submission and it never touches the account's privacy consent.
      _declinedConsentFields = declinedFormConsentFields(templateId, formValues);

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
