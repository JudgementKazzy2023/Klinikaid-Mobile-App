import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/repositories/department_records_repository.dart';

class RecordsProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _recordsRepo = DepartmentRecordsRepository();

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  List<DepartmentRecord> _records = [];

  RecordsProvider(this._localDb);

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  List<DepartmentRecord> get records => _records;

  /// Fetches clinical records for [patientId]. Online reads are cached locally; offline falls back to cached records.
  Future<void> fetchRecords(String patientId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remoteRecords = await _recordsRepo.getRecordsForPatient(patientId);
      _records = remoteRecords;
      _isOffline = false;

      // Cache records locally
      final cachedRecords = remoteRecords.map((r) => CachedDepartmentRecord(
        id: r.id,
        patientId: r.patientId,
        recorderId: r.recorderId,
        department: r.department.name,
        testType: r.testType,
        testResults: jsonEncode(r.testResults),
        referenceRangeStatus: r.referenceRangeStatus.name,
        notes: r.notes,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      )).toList();

      await _localDb.cacheDepartmentRecords(cachedRecords);
      _isLoading = false;
      notifyListeners();
    } on NetworkFailure catch (_) {
      _isOffline = true;
      await _loadFromCache(patientId);
    } catch (e) {
      _errorMessage = FailureMapper.fromException(e).message;
      await _loadFromCache(patientId);
    }
  }

  Future<void> _loadFromCache(String patientId) async {
    try {
      final cachedList = await _localDb.getRecordsForPatient(patientId);
      _records = cachedList.map((driftRec) => DepartmentRecord(
        id: driftRec.id,
        patientId: driftRec.patientId,
        recorderId: driftRec.recorderId,
        department: Department.fromString(driftRec.department) ?? Department.laboratory,
        testType: driftRec.testType,
        testResults: jsonDecode(driftRec.testResults) as Map<String, dynamic>,
        referenceRangeStatus: ReferenceRangeStatus.fromString(driftRec.referenceRangeStatus),
        notes: driftRec.notes,
        createdAt: driftRec.createdAt,
        updatedAt: driftRec.updatedAt,
      )).toList();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to load cached records: ${e.toString()}';
      notifyListeners();
    }
  }
}
