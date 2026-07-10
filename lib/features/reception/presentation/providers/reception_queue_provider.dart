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

  ReceptionQueueProvider({required ReceptionRepository repository})
      : _repository = repository;

  List<Submission> get submissions => _submissions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  SubmissionDetail? get selectedDetail => _selectedDetail;

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
}
