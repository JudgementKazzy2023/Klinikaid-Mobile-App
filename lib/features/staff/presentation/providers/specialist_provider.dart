import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/repositories/patients_repository.dart';
import '../../data/repositories/staff_queue_repository.dart';
import '../../../records/domain/record_grouper.dart';

class SpecialistProvider extends ChangeNotifier {
  final StaffQueueRepository _repo;
  final PatientsRepository _patientsRepo;

  SpecialistProvider({
    StaffQueueRepository? staffRepo,
    PatientsRepository? patientsRepo,
  })  : _repo = staffRepo ?? StaffQueueRepository(),
        _patientsRepo = patientsRepo ?? PatientsRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<Patient> _searchResults = [];
  Patient? _selectedPatient;
  List<DepartmentRecord> _patientTimeline = [];
  List<GroupedRecord> _groupedPatientTimeline = [];

  List<Patient> _allPatients = [];
  String _currentQuery = '';

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Patient> get searchResults => _searchResults;
  Patient? get selectedPatient => _selectedPatient;
  List<DepartmentRecord> get patientTimeline => _patientTimeline;
  List<GroupedRecord> get groupedPatientTimeline => _groupedPatientTimeline;

  /// Loads all patients once on mount/sign-in.
  Future<void> loadAllPatients() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _allPatients = await _patientsRepo.getAllPatients();
      _isLoading = false;
      if (_currentQuery.trim().isNotEmpty) {
        search(_currentQuery);
      }
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Searches patients by query in first name / last name client-side using term-based AND logic.
  void search(String query) {
    _currentQuery = query;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    final terms = trimmed
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (terms.isEmpty) {
      _searchResults = List.from(_allPatients);
    } else {
      _searchResults = _allPatients.where((p) {
        final first = p.firstName.toLowerCase();
        final last = p.lastName.toLowerCase();
        return terms.every((t) => first.contains(t) || last.contains(t));
      }).toList();
    }
    notifyListeners();
  }

  /// Selects a patient and fetches their complete cross-department timeline of department records.
  Future<void> selectPatient(Patient patient) async {
    _selectedPatient = patient;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _patientTimeline = await _repo.getDepartmentRecordsForPatient(patient.id);
      _groupedPatientTimeline = groupRecords(_patientTimeline);
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
    _groupedPatientTimeline = [];
    notifyListeners();
  }

  /// Clears search queries and selected patient.
  void clearAll() {
    _searchResults = [];
    _selectedPatient = null;
    _patientTimeline = [];
    _groupedPatientTimeline = [];
    _errorMessage = null;
    _currentQuery = '';
    notifyListeners();
  }
}

