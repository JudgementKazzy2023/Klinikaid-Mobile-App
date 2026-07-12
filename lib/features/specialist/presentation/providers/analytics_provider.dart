import 'package:flutter/material.dart';
import '../../../../core/models/specialist_patient.dart';
import '../../../../core/models/specialist_record.dart';
import '../../data/specialist_repository.dart';
import '../../domain/analytics_series.dart';

class AnalyticsProvider extends ChangeNotifier {
  final SpecialistRepository _repo;

  AnalyticsProvider({SpecialistRepository? repository})
      : _repo = repository ?? SpecialistRepository();

  SpecialistPatient? _patient;
  SpecialistPatient? get patient => _patient;

  List<SpecialistRecord> _records = [];
  List<SpecialistRecord> get records => _records;

  List<String> _parameters = [];
  List<String> get parameters => _parameters;

  String? _selectedParameter;
  String? get selectedParameter => _selectedParameter;

  ParameterSeries? _series;
  ParameterSeries? get series => _series;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Initializes the provider by loading patient details and record history.
  Future<void> init(String patientId) async {
    _isLoading = true;
    _errorMessage = null;
    _patient = null;
    _records = [];
    _parameters = [];
    _selectedParameter = null;
    _series = null;
    notifyListeners();

    try {
      // 1. Fetch Patient
      _patient = await _repo.getPatientById(patientId);

      // 2. Fetch records
      _records = await _repo.getPatientRecords(patientId);

      // 3. Derive unique parameters
      _parameters = availableParameters(_records);

      if (_parameters.isNotEmpty) {
        // Default to the first available parameter alphabetically
        _selectedParameter = _parameters.first;
        _series = buildSeries(_records, _selectedParameter!);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Changes the tracked diagnostic parameter and updates the time-series points.
  void selectParameter(String testName) {
    if (!_parameters.contains(testName)) return;
    _selectedParameter = testName;
    _series = buildSeries(_records, testName);
    notifyListeners();
  }
}
