import 'package:flutter/material.dart';
import '../../../../core/errors/failures.dart';
import '../../data/department_repository.dart';
import '../../domain/flag_calculator.dart';
import '../../domain/lab_reference_ranges.dart';

class ResultEntryProvider extends ChangeNotifier {
  final DepartmentRepository _repo;

  ResultEntryProvider([DepartmentRepository? repo]) : _repo = repo ?? DepartmentRepository();

  bool _isLoading = false;
  String? _errorMessage;

  // Form State
  String _selectedLabGroup = 'Complete Blood Count (CBC)';
  final Map<String, String> _parameterValues = {};
  String _findings = '';
  String _impression = '';
  String _notes = '';
  bool _hasOcrAutofill = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  String get selectedLabGroup => _selectedLabGroup;
  Map<String, String> get parameterValues => _parameterValues;
  String get findings => _findings;
  String get impression => _impression;
  String get notes => _notes;
  bool get hasOcrAutofill => _hasOcrAutofill;

  void setLabGroup(String group) {
    if (_selectedLabGroup != group) {
      _selectedLabGroup = group;
      _parameterValues.clear();
      _errorMessage = null;
      _hasOcrAutofill = false;
      notifyListeners();
    }
  }

  void setParameterValue(String parameter, String value) {
    _parameterValues[parameter] = value;
    _errorMessage = null;
    notifyListeners();
  }

  bool applyOcrAutofill({
    required String? panel,
    required Map<String, String> values,
  }) {
    if (panel == null || !kLabTestGroups.containsKey(panel)) {
      _errorMessage = 'No values extracted, enter manually.';
      notifyListeners();
      return false;
    }

    final allowedParameters = kLabTestGroups[panel]!.toSet();
    final filteredValues = <String, String>{};
    for (final entry in values.entries) {
      if (allowedParameters.contains(entry.key) && entry.value.trim().isNotEmpty) {
        filteredValues[entry.key] = entry.value.trim();
      }
    }

    if (filteredValues.isEmpty) {
      _errorMessage = 'No values extracted, enter manually.';
      notifyListeners();
      return false;
    }

    _selectedLabGroup = panel;
    _parameterValues
      ..clear()
      ..addAll(filteredValues);
    _hasOcrAutofill = true;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  void setFindings(String val) {
    _findings = val;
    _errorMessage = null;
    notifyListeners();
  }

  void setImpression(String val) {
    _impression = val;
    _errorMessage = null;
    notifyListeners();
  }

  void setNotes(String val) {
    _notes = val;
    _errorMessage = null;
    notifyListeners();
  }

  void reset() {
    _isLoading = false;
    _errorMessage = null;
    _parameterValues.clear();
    _findings = '';
    _impression = '';
    _notes = '';
    _selectedLabGroup = 'Complete Blood Count (CBC)';
    _hasOcrAutofill = false;
    notifyListeners();
  }

  /// Submits lab results. Returns true on success, false on failure.
  Future<bool> submitLabResults({
    required String patientId,
    required String? gender,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final parameters = kLabTestGroups[_selectedLabGroup] ?? [];
      final List<LabResultRow> rows = [];
      final currentUserId = _repo.currentUserId;
      if (currentUserId == null) {
        throw const AuthFailure('User not authenticated');
      }

      // Validate inputs
      int enteredCount = 0;
      for (final param in parameters) {
        final valStr = _parameterValues[param]?.trim() ?? '';
        if (valStr.isNotEmpty) {
          enteredCount++;
          final parsed = double.tryParse(valStr);
          if (parsed == null) {
            _isLoading = false;
            _errorMessage = 'Invalid numeric input for "$param". Please enter numbers only.';
            notifyListeners();
            return false;
          }
        }
      }

      if (enteredCount == 0) {
        _isLoading = false;
        _errorMessage = 'Please enter at least one parameter value.';
        notifyListeners();
        return false;
      }

      // Build rows
      final sharedNotes = _notes.trim().isEmpty ? null : _notes.trim();

      for (final param in parameters) {
        final valStr = _parameterValues[param]?.trim() ?? '';
        if (valStr.isEmpty) continue;

        final val = double.parse(valStr);
        final range = kLabReferenceRanges.firstWhere(
          (r) => r.parameter == param,
          orElse: () => throw UnknownFailure(
            'Reference range definition not found for parameter: $param',
          ),
        );

        final isFemale = gender?.toLowerCase() == 'female';
        final resolvedMin = isFemale ? range.femaleMin : range.maleMin;
        final resolvedMax = isFemale ? range.femaleMax : range.maleMax;
        final flagged = isValueFlagged(val, range, gender);

        rows.add(LabResultRow(
          patientId: patientId,
          recorderId: currentUserId,
          department: 'laboratory',
          testType: _selectedLabGroup,
          testName: param,
          testValue: val.toString(),
          unit: range.unit,
          referenceRangeMin: resolvedMin,
          referenceRangeMax: resolvedMax,
          isFlagged: flagged,
          notes: sharedNotes,
        ));
      }

      await _repo.submitLabResults(patientId: patientId, rows: rows);
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

  /// Submits free-text results. Returns true on success, false on failure.
  Future<bool> submitFreeTextResult({
    required String patientId,
    required String testName,
  }) async {
    final nameTrimmed = testName.trim();
    final findingsTrimmed = _findings.trim();
    final impressionTrimmed = _impression.trim();

    if (nameTrimmed.isEmpty || findingsTrimmed.isEmpty || impressionTrimmed.isEmpty) {
      _errorMessage = 'All fields (Test Name, Findings, Impression) are required.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repo.submitFreeTextResult(
        patientId: patientId,
        testName: nameTrimmed,
        findings: findingsTrimmed,
        impression: impressionTrimmed,
        notes: _notes,
      );
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
}
