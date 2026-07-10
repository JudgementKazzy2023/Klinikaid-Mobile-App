import 'package:flutter/material.dart';
import '../../data/reception_repository.dart';
import '../../domain/submission.dart';
import '../../domain/submission_detail.dart';
import '../../domain/submission_status.dart';

class ReceptionQueueProvider extends ChangeNotifier {
  final ReceptionRepository _repository;

  List<Submission> _submissions = [];
  bool _isLoading = false;
  String? _errorMessage;
  SubmissionDetail? _selectedDetail;

  bool _isRouting = false;
  String? _routingError;

  ReceptionQueueProvider({required ReceptionRepository repository})
      : _repository = repository;

  List<Submission> get submissions => _submissions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  SubmissionDetail? get selectedDetail => _selectedDetail;
  bool get isRouting => _isRouting;
  String? get routingError => _routingError;

  List<Submission> get pendingSubmissions =>
      _submissions.where((s) => s.status == SubmissionStatus.submitted).toList();

  List<Submission> get submittedSubmissions =>
      _submissions.where((s) => s.status == SubmissionStatus.submitted).toList();

  List<Submission> get approvedSubmissions =>
      _submissions.where((s) => s.status == SubmissionStatus.approved).toList();

  List<Submission> get rejectedSubmissions =>
      _submissions.where((s) => s.status == SubmissionStatus.rejected).toList();

  /// Loads all submissions to populate the queue lists and badge counts.
  Future<void> loadSubmissions() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _submissions = await _repository.getSubmissions();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Loads the details of a single document submission.
  Future<SubmissionDetail?> loadSubmissionDetail(String id) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedDetail = null;
    notifyListeners();

    try {
      _selectedDetail = await _repository.getSubmissionDetail(id);
      _isLoading = false;
      notifyListeners();
      return _selectedDetail;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Fetches a signed storage URL for a document.
  Future<String> getOriginalDocumentUrl(String id) async {
    return await _repository.getOriginalDocumentUrl(id);
  }

  /// Approves a document and routes the patient to a department.
  /// On success, refreshes the queue so Pending −1, Approved +1 without
  /// requiring a manual pull-to-refresh.
  /// Returns true on success, false on failure (error available via [routingError]).
  Future<bool> approveAndRoute({
    required String documentId,
    required String patientId,
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) async {
    _isRouting = true;
    _routingError = null;
    notifyListeners();

    try {
      await _repository.approveAndRoute(
        documentId: documentId,
        patientId: patientId,
        department: department,
        priority: priority,
        bloodPressure: bloodPressure,
        weightKg: weightKg,
        temperatureC: temperatureC,
        triageNotes: triageNotes,
      );
      _isRouting = false;
      notifyListeners();
      // Refresh queue so Pending −1, Approved +1 automatically.
      await loadSubmissions();
      return true;
    } catch (e) {
      _isRouting = false;
      _routingError = e.toString();
      notifyListeners();
      return false;
    }
  }

  bool _isRejecting = false;
  String? _rejectError;

  bool get isRejecting => _isRejecting;
  String? get rejectError => _rejectError;

  /// Rejects a document and records the reason.
  /// On success, refreshes the queue lists automatically.
  /// Returns true on success, false on failure (error available via [rejectError]).
  Future<bool> rejectDocument({
    required String documentId,
    required String reason,
  }) async {
    _isRejecting = true;
    _rejectError = null;
    notifyListeners();

    try {
      await _repository.rejectDocument(
        documentId: documentId,
        reason: reason,
      );
      _isRejecting = false;
      notifyListeners();
      // Refresh queue lists so Pending -1, Rejected +1 automatically.
      await loadSubmissions();
      return true;
    } catch (e) {
      _isRejecting = false;
      _rejectError = e.toString();
      notifyListeners();
      return false;
    }
  }
}
