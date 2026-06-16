import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/department_record.dart';
import '../../data/repositories/staff_queue_repository.dart';

class SpecialistProvider extends ChangeNotifier {
  final _repo = StaffQueueRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<Patient> _searchResults = [];
  Patient? _selectedPatient;
  List<DepartmentRecord> _patientTimeline = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Patient> get searchResults => _searchResults;
  Patient? get selectedPatient => _selectedPatient;
  List<DepartmentRecord> get patientTimeline => _patientTimeline;

  /// Searches patients by query in first name / last name.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _searchResults = await _repo.searchPatients(query);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Selects a patient and fetches their complete cross-department timeline of department records.
  Future<void> selectPatient(Patient patient) async {
    _selectedPatient = patient;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _patientTimeline = await _repo.getDepartmentRecordsForPatient(patient.id);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Clears selected patient timeline view and returns to search results.
  void clearSelection() {
    _selectedPatient = null;
    _patientTimeline = [];
    notifyListeners();
  }

  /// Clears search queries and selected patient.
  void clearAll() {
    _searchResults = [];
    _selectedPatient = null;
    _patientTimeline = [];
    _errorMessage = null;
    notifyListeners();
  }
}
