import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/repositories/department_records_repository.dart';
import '../../domain/record_grouper.dart';

/// Where the records currently on screen come from.
enum RecordsDataState {
  /// The last read succeeded: the records are the server's.
  fresh,

  /// The last read failed: the records are a cached copy, not the server's.
  stale,

  /// The last read failed and there was nothing cached to show.
  failed,
}

class RecordsProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final DepartmentRecordsRepository _recordsRepo;

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  RecordsDataState _dataState = RecordsDataState.fresh;
  List<DepartmentRecord> _records = [];

  RecordsProvider(this._localDb, {DepartmentRecordsRepository? recordsRepository})
      : _recordsRepo = recordsRepository ?? DepartmentRecordsRepository();

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  List<DepartmentRecord> get records => _records;
  List<GroupedRecord> get groupedRecords => groupRecords(_records);

  /// The state of the data currently on screen.
  RecordsDataState get dataState => _dataState;

  /// True when the records on screen come from the cache because the last
  /// server read failed. They must never be presented as the server's answer.
  bool get isStale => _dataState == RecordsDataState.stale;

  /// Fetches clinical records for [patientId]. Online reads are cached locally; offline falls back to cached records.
  Future<void> fetchRecords(String patientId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remoteRecords = await _recordsRepo.getRecordsForPatient(patientId);
      _records = remoteRecords;
      _isOffline = false;
      _dataState = RecordsDataState.fresh;

      // Cache records locally. A successful read replaces the patient's cache,
      // so rows the server no longer returns cannot resurface later on.
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

      await _localDb.replaceDepartmentRecords(patientId, cachedRecords);
    } on NetworkFailure catch (e) {
      _isOffline = true;
      await _loadFromCache(patientId, e.message);
    } on Failure catch (e) {
      await _loadFromCache(patientId, e.message);
    } catch (e) {
      await _loadFromCache(patientId, FailureMapper.fromException(e).message);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Falls back to the cached records of [patientId] after a failed read.
  ///
  /// The cached rows are shown, but only as stale ones: the caller is told
  /// why the server could not be read so the screen can say so.
  Future<void> _loadFromCache(String patientId, String reason) async {
    _errorMessage = reason;
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

      _dataState = _records.isEmpty
          ? RecordsDataState.failed
          : RecordsDataState.stale;
    } catch (e) {
      _records = [];
      _dataState = RecordsDataState.failed;
      _errorMessage = 'Failed to load cached records: ${e.toString()}';
    }
  }
}
