import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/specialist_patient.dart';
import '../../../../core/models/specialist_record.dart';
import '../../data/specialist_repository.dart';

class SpecialistProvider extends ChangeNotifier {
  final SpecialistRepository _repo;

  SpecialistProvider({SpecialistRepository? repository})
      : _repo = repository ?? SpecialistRepository();

  SpecialistRepository get repository => _repo;

  bool _isLoading = false;
  String? _errorMessage;

  List<SpecialistPatient> _directoryPatients = [];
  List<SpecialistPatient> _searchResults = [];
  String _currentQuery = '';

  // Dashboard Aggregates
  int _totalPatients = 0;
  int _flaggedResults7Days = 0;
  int _activeModalities = 0;
  List<Map<String, dynamic>> _criticalFlaggedResults = [];
  List<SpecialistPatient> _recentlyUpdatedPatients = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<SpecialistPatient> get directoryPatients => _directoryPatients;
  List<SpecialistPatient> get searchResults => _searchResults;
  String get currentQuery => _currentQuery;

  int get totalPatients => _totalPatients;
  int get flaggedResults7Days => _flaggedResults7Days;
  int get activeModalities => _activeModalities;
  List<Map<String, dynamic>> get criticalFlaggedResults => _criticalFlaggedResults;
  List<SpecialistPatient> get recentlyUpdatedPatients => _recentlyUpdatedPatients;

  /// The exact number of private patients the server counted, not the number
  /// that happened to fit in one response.
  int get directoryTotal => _directoryPatients.length;

  /// Loads the private patient directory.
  Future<void> loadDirectory() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _directoryPatients = await _repo.getMyPatients();
      _isLoading = false;
      if (_currentQuery.isNotEmpty) {
        search(_currentQuery);
      } else {
        _searchResults = List.from(_directoryPatients);
      }
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Loads the dashboard data and computes aggregates.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _repo.getDashboardRawData();
      _computeDashboardAggregates(data);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Derives dashboard aggregates client-side.
  void _computeDashboardAggregates(Map<String, dynamic> rawData) {
    final patients = rawData['patients'] as List<SpecialistPatient>;
    final records = rawData['records'] as List<SpecialistRecord>;
    final rawRecords = rawData['raw_records'] as List<dynamic>;

    // The server's exact count, so the tile does not report the size of one page.
    _totalPatients = rawData['total_patients'] as int? ?? patients.length;

    // Flagged results in last 7 days
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    _flaggedResults7Days = records
        .where((r) => r.isFlagged && r.createdAt.isAfter(sevenDaysAgo))
        .length;

    // Active modalities (distinct test_type)
    _activeModalities = records.map((r) => r.testType).toSet().length;

    // Critical flagged results list (recent flagged records, joined to patient name, limit 10)
    final List<Map<String, dynamic>> criticalList = [];
    for (final raw in rawRecords) {
      if (raw['is_flagged'] == true) {
        final patientJson = raw['patient'];
        String patientName = 'Unknown Patient';
        if (patientJson != null) {
          final first = patientJson['first_name'] as String? ?? '';
          final last = patientJson['last_name'] as String? ?? '';
          patientName = '$first $last'.trim();
        }
        criticalList.add({
          'record': SpecialistRecord.fromJson(raw as Map<String, dynamic>),
          'patient_name': patientName,
        });
      }
    }
    _criticalFlaggedResults = criticalList.take(10).toList();

    // Recently updated patients (sort by updated_at DESC, take top 5)
    final sortedPatients = List<SpecialistPatient>.from(patients);
    sortedPatients.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _recentlyUpdatedPatients = sortedPatients.take(5).toList();
  }

  /// Client-side term-based and code-based search.
  void search(String query) {
    _currentQuery = query;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResults = List.from(_directoryPatients);
      notifyListeners();
      return;
    }

    final terms = trimmed
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (terms.isEmpty) {
      _searchResults = List.from(_directoryPatients);
    } else {
      _searchResults = _directoryPatients.where((p) {
        final first = p.firstName.toLowerCase();
        final last = p.lastName.toLowerCase();
        final code = p.patientCode.toLowerCase();
        
        return terms.every((t) =>
            first.contains(t) || last.contains(t) || code.contains(t));
      }).toList();
    }
    notifyListeners();
  }

  /// Adds a new private patient and refreshes dashboard + directory.
  Future<bool> addPatient({
    required String firstName,
    required String lastName,
    required DateTime dob,
    required String gender,
    String? contactNumber,
    String? email,
    String? address,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repo.addPatient(
        firstName: firstName,
        lastName: lastName,
        dob: dob,
        gender: gender,
        contactNumber: contactNumber,
        email: email,
        address: address,
      );
      // Refresh directory and dashboard raw states
      await loadDirectory();
      final dashboardData = await _repo.getDashboardRawData();
      _computeDashboardAggregates(dashboardData);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
      return false;
    }
  }

  bool _isArchiving = false;
  bool get isArchiving => _isArchiving;

  /// A confirmed archive remains successful even if a subsequent read fails.
  Future<bool> archivePatient(String patientId) async {
    if (_isArchiving) return false;
    _isArchiving = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final archived = await _repo.archivePatient(patientId);
      if (!archived) {
        await loadDirectory();
        _errorMessage = 'Patient could not be archived, refresh and try again.';
        return false;
      }
      _directoryPatients.removeWhere((p) => p.id == patientId);
      _searchResults.removeWhere((p) => p.id == patientId);
      _recentlyUpdatedPatients.removeWhere((p) => p.id == patientId);
      _criticalFlaggedResults = [];
      _totalPatients = _directoryPatients.length;
      _flaggedResults7Days = 0;
      _activeModalities = 0;
      try {
        _directoryPatients = await _repo.getMyPatients();
        search(_currentQuery);
        _computeDashboardAggregates(await _repo.getDashboardRawData());
      } catch (_) {
        _errorMessage = 'Patient archived, but the latest data could not be loaded. Refresh to update the view.';
      }
      return true;
    } catch (e) {
      _errorMessage = 'Archive could not be confirmed. Refresh to check the patient before trying again.';
      return false;
    } finally {
      _isArchiving = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset provider state.
  void clearAll() {
    _directoryPatients = [];
    _searchResults = [];
    _currentQuery = '';
    _totalPatients = 0;
    _flaggedResults7Days = 0;
    _activeModalities = 0;
    _criticalFlaggedResults = [];
    _recentlyUpdatedPatients = [];
    _errorMessage = null;
    notifyListeners();
  }
}
