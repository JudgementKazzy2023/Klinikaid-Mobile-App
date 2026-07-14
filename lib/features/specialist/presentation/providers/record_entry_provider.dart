import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/specialist_patient.dart';
import '../../../department/domain/lab_reference_ranges.dart';
import '../../../department/domain/flag_calculator.dart';
import '../../data/specialist_repository.dart';
import 'specialist_provider.dart';
import '../../../../core/utils/lab_validators.dart';

class RecordEntryProvider extends ChangeNotifier {
  final SpecialistRepository _repo;

  RecordEntryProvider({SpecialistRepository? repository})
      : _repo = repository ?? SpecialistRepository();

  SpecialistPatient? _patient;
  SpecialistPatient? get patient => _patient;

  String? _selectedTestType;
  String? get selectedTestType => _selectedTestType;

  final Map<String, TextEditingController> _controllers = {};
  Map<String, TextEditingController> get controllers => _controllers;

  final TextEditingController notesController = TextEditingController();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Initializes the provider with the patient context by loading it from the database.
  Future<void> init(String patientId) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedTestType = null;
    notesController.clear();
    _clearControllers();
    notifyListeners();

    try {
      _patient = await _repo.getPatientById(patientId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _clearControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  /// Sets the active diagnostic group and initializes parameter text fields.
  void selectTestType(String testType) {
    _selectedTestType = testType;
    _clearControllers();

    final params = kLabTestGroups[testType] ?? [];
    for (final param in params) {
      _controllers[param] = TextEditingController();
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Performs client-side validation and inserts structural rows into the database.
  Future<bool> submit(BuildContext context, SpecialistProvider specialistProvider) async {
    if (_selectedTestType == null) {
      _errorMessage = 'Please select a diagnostic group.';
      notifyListeners();
      return false;
    }

    if (_patient == null) {
      _errorMessage = 'Patient details not loaded.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final List<SpecialistRecordRow> rows = [];
      final params = kLabTestGroups[_selectedTestType!] ?? [];

      for (final paramName in params) {
        final controller = _controllers[paramName];
        final textValue = controller?.text.trim() ?? '';
        if (textValue.isEmpty) continue;

        // Shared validation check
        final error = validateLabValue(textValue);
        if (error != null) {
          throw Exception('Value for $paramName must be a valid number.');
        }

        // Numeric parsing check
        final double? parsedVal = double.tryParse(textValue);
        if (parsedVal == null) {
          throw Exception('Value for $paramName must be a valid number.');
        }

        // Find reference range for gender-aware comparison & storage
        final range = kLabReferenceRanges.firstWhere(
          (r) => r.parameter == paramName,
          orElse: () => throw Exception('Reference range not found for $paramName.'),
        );

        final isFemale = _patient!.gender.toLowerCase() == 'female';
        final refMin = isFemale ? range.femaleMin : range.maleMin;
        final refMax = isFemale ? range.femaleMax : range.maleMax;

        // Perform range flagging
        final isFlagged = isValueFlagged(parsedVal, range, _patient!.gender);

        rows.add(SpecialistRecordRow(
          testName: paramName,
          testValue: textValue, // Stored as stringified value (Constraint #2 parity)
          unit: range.unit,
          referenceRangeMin: refMin,
          referenceRangeMax: refMax,
          isFlagged: isFlagged,
        ));
      }

      if (rows.isEmpty) {
        throw Exception('Please enter at least one parameter value.');
      }

      await _repo.submitRecord(
        specialistPatientId: _patient!.id,
        testType: _selectedTestType!,
        rows: rows,
        notes: notesController.text,
      );

      // Refresh parent specialist provider metrics and lists
      await specialistProvider.loadDirectory();
      await specialistProvider.loadDashboard();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
      notifyListeners();
      return false;
    }
  }

  void setErrorMessage(String? msg) {
    _errorMessage = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearControllers();
    notesController.dispose();
    super.dispose();
  }
}
