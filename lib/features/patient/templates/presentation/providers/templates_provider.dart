import 'package:flutter/foundation.dart';
import '../../../../../core/patient_submission_containment.dart';
import '../../../../../core/utils/uuid_generator.dart';
import '../../data/templates_repository.dart';
import '../../../submissions/document_dedup.dart';

enum TemplateRemediation { none, signIn, verifyEmail, consent, changePassword }

class TemplatesProvider extends ChangeNotifier {
  final TemplatesRepository _repository;
  final Future<String?> Function(String, String) _checkDuplicate;
  TemplatesProvider({
    TemplatesRepository? repository,
    Future<String?> Function(String, String)? checkDuplicate,
  }) : _repository = repository ?? TemplatesRepository(),
       _checkDuplicate =
           checkDuplicate ??
           ((patientId, category) async =>
               (await checkPendingDuplicate(patientId, category)).duplicateDate);

  bool _isLoading = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _success = false;
  String? _errorMessage;
  TemplateSubmissionError? _error;
  TemplateSubmissionSuccess? _result;
  String? _requestId;
  // The request whose outcome is unknown: asked about (/status) before any
  // further send, so edited answers cannot become a second submission.
  String? _uncertainRequestId;
  String? _draftOwner;
  String? _draftTemplate;
  Map<String, String> _answers = {};
  String? _advisoryMessage;
  final Map<String, String> _fieldErrors = {};
  TemplateRemediation _remediation = TemplateRemediation.none;

  bool get isLoading => _isLoading;
  bool get success => _success;
  String? get errorMessage => _errorMessage;
  String? get requestId => _requestId;
  String? get errorCode => _error?.code;
  String? get duplicateDocumentId =>
      _error?.code == 'DUPLICATE_PENDING' ? _error?.documentId : null;
  TemplateSubmissionSuccess? get result => _result;
  Map<String, String> get fieldErrors => Map.unmodifiable(_fieldErrors);
  String? get advisoryMessage => _advisoryMessage;
  TemplateRemediation get remediation => _remediation;
  bool get outcomeUnknown => _error?.code == 'SERVER_ERROR';
  bool get canSubmit =>
      !_isLoading &&
      !_success &&
      (_error == null ||
          outcomeUnknown ||
          _error?.code == 'FIELD_REQUIRED' ||
          _error?.code == 'FIELD_INVALID');

  void resetState() {
    // UI status resets must not erase an uncertain request's identity.
    if (_isLoading ||
        outcomeUnknown ||
        _error?.code == 'IDEMPOTENCY_CONFLICT' ||
        _error?.code == 'RECONCILIATION_REQUIRED') {
      return;
    }
    _error = null;
    _errorMessage = null;
    _success = false;
    _result = null;
    _fieldErrors.clear();
    _remediation = TemplateRemediation.none;
  }

  void answersChanged(Map<String, String> answers) {
    if (mapEquals(_answers, answers)) return;
    _answers = Map.unmodifiable(answers);
    _requestId = UuidGenerator.generateV4();
    _fieldErrors.clear();
    // Reconciliation errors remain blocked even if the patient edits.
    if (_error?.code == 'FIELD_REQUIRED' ||
        _error?.code == 'FIELD_INVALID' ||
        outcomeUnknown) {
      _error = null;
      _errorMessage = null;
    }
    notifyListeners();
  }

  void resumeAfterAccountFlow() {
    if (_remediation == TemplateRemediation.none) return;
    _error = null;
    _errorMessage = null;
    _remediation = TemplateRemediation.none;
    notifyListeners();
  }

  void _applyError(TemplateSubmissionError error, String templateName) {
    _error = error;
    _errorMessage = error.message;
    switch (error.code) {
      case 'FIELD_REQUIRED':
      case 'FIELD_INVALID':
        if (error.field != null) _fieldErrors[error.field!] = error.message;
      case 'DUPLICATE_PENDING':
        _errorMessage = 'You already have a pending $templateName';
      case 'IDEMPOTENCY_CONFLICT':
      case 'RECONCILIATION_REQUIRED':
        _errorMessage =
            'Please contact the clinic before submitting again. '
            'Your answers are still here.';
      case 'UNAUTHENTICATED':
        _remediation = TemplateRemediation.signIn;
      case 'EMAIL_NOT_CONFIRMED':
        _remediation = TemplateRemediation.verifyEmail;
      case 'CONSENT_REQUIRED':
        _remediation = TemplateRemediation.consent;
      case 'PASSWORD_CHANGE_REQUIRED':
        _remediation = TemplateRemediation.changePassword;
      case 'UNKNOWN_TEMPLATE':
      case 'UNKNOWN_FIELD':
      case 'METHOD_NOT_ALLOWED':
        _errorMessage = 'This app version is out of date.';
      case 'PATIENT_ACCOUNT_REQUIRED':
      case 'NO_PATIENT_RECORD':
      case 'PROFILE_INACTIVE':
      case 'SERVER_DATA_INVALID':
      case 'AGE_REQUIREMENT_NOT_MET':
        break; // Preserve the server's safe message; no retry.
      default:
        _error = TemplateSubmissionError.unknown;
        _errorMessage = TemplateSubmissionError.unknown.message;
    }
  }

  Future<bool> submitTemplate({
    required String patientId,
    required String uploaderId,
    required String templateId,
    required String templateName,
    required Map<String, dynamic> formValues,
    // Retained for existing containment callers; never transmitted or injected.
    String? patientName,
    String? dob,
    String? contactNumber,
    String? address,
  }) async {
    if (PatientSubmissionContainment.isActive) {
      _isLoading = false;
      _success = false;
      _errorMessage = PatientSubmissionContainment.message;
      notifyListeners();
      return false;
    }
    if (_isLoading) return false;
    final owner = '$uploaderId/$patientId';
    if (_draftOwner != owner || _draftTemplate != templateId) {
      if (_draftOwner != null &&
          (outcomeUnknown ||
              _error?.code == 'IDEMPOTENCY_CONFLICT' ||
              _error?.code == 'RECONCILIATION_REQUIRED')) {
        return false;
      }
      _draftOwner = owner;
      _draftTemplate = templateId;
      _requestId = null;
      _uncertainRequestId = null;
      _answers = {};
      resetState();
    }
    final answers = Map<String, String>.from(formValues);
    answersChanged(answers);
    _requestId ??= UuidGenerator.generateV4();
    if (!canSubmit) return false;
    final retry = outcomeUnknown;
    var requestId = _requestId!;
    final snapshot = Map<String, String>.unmodifiable(answers);
    _isLoading = true;
    _error = null;
    _errorMessage = null;
    _fieldErrors.clear();
    _remediation = TemplateRemediation.none;
    _advisoryMessage = null;
    notifyListeners();
    try {
      final uncertain = _uncertainRequestId;
      if (uncertain != null) {
        final known = await _repository.lookupTemplateOutcome(uncertain);
        if (known == null) {
          _applyError(TemplateSubmissionError.unknown, templateName);
          return false;
        }
        _uncertainRequestId = null;
        switch (known.state) {
          case TemplateLookupState.committed:
            _result = TemplateSubmissionSuccess(
              known.documentId!,
              known.status ?? 'pending',
              true,
            );
            _success = true;
            return true;
          case TemplateLookupState.withdrawn:
            // The patient cancelled it; that id now needs reconciliation.
            if (requestId == uncertain) {
              requestId = _requestId = UuidGenerator.generateV4();
            }
          case TemplateLookupState.notFound:
            break;
        }
      }
      // Advisory only: it must never mask a replay or the authoritative result.
      if (!retry && templateId != 'other') {
        try {
          final duplicate = await _checkDuplicate(patientId, templateId);
          if (duplicate != null) {
            _advisoryMessage =
                'You may already have a pending $templateName. '
                'Checking with the clinic server.';
            notifyListeners();
          }
        } catch (_) {
          /* The submission endpoint remains authoritative. */
        }
      }
      final result = await _repository.submitTemplateDocument(
        requestId: requestId,
        templateId: templateId,
        fields: snapshot,
      );
      switch (result) {
        case TemplateSubmissionSuccess():
          _result = result;
          _success = true;
        case TemplateSubmissionError():
          _applyError(result, templateName);
      }
    } catch (_) {
      _applyError(TemplateSubmissionError.unknown, templateName);
    } finally {
      if (outcomeUnknown) _uncertainRequestId ??= requestId;
      _isLoading = false;
      notifyListeners();
    }
    return _success;
  }
}
