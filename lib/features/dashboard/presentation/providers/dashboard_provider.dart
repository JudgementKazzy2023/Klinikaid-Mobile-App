import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/models/document.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/repositories/department_records_repository.dart';
import '../../../../core/repositories/documents_repository.dart';
import '../../../../core/repositories/patient_queue_repository.dart';

/// Where the dashboard data currently on screen comes from.
enum DashboardDataState {
  /// The last read succeeded: the numbers are the server's.
  live,

  /// The last read failed: the dashboard shows a cached copy, not the
  /// server's answer. The reason for the failure is kept.
  stale,

  /// The last read succeeded and there is nothing to show.
  empty,

  /// The last read failed and there was nothing cached to show.
  error,
}

class DashboardProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final DocumentsRepository _docsRepo;
  final _queueRepo = PatientQueueRepository();
  final _recordsRepo = DepartmentRecordsRepository();

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  DashboardDataState _dataState = DashboardDataState.empty;

  int _pendingDocumentsCount = 0;
  PatientQueue? _activeQueueEntry;
  DepartmentRecord? _latestRecord;

  DashboardProvider(
    this._localDb, {
    DocumentsRepository? documentsRepository,
  }) : _docsRepo = documentsRepository ?? DocumentsRepository();

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;

  /// The state of the dashboard data currently on screen.
  DashboardDataState get dataState => _dataState;

  /// True when the dashboard shows a cached copy because the last server read
  /// failed. It must never be presented as the server's answer.
  bool get isStale => _dataState == DashboardDataState.stale;

  int get pendingDocumentsCount => _pendingDocumentsCount;
  PatientQueue? get activeQueueEntry => _activeQueueEntry;
  DepartmentRecord? get latestRecord => _latestRecord;

  Future<void> fetchDashboardData(String patientId, String uploaderId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Try fetching from remote Supabase repositories
      final List<dynamic> results = await Future.wait([
        _docsRepo.getDocumentsForPatient(uploaderId),
        _queueRepo.getQueueForPatient(patientId),
        _recordsRepo.getRecordsForPatient(patientId),
      ]);

      final documents = results[0] as List<Document>;
      final queueEntries = results[1] as List<PatientQueue>;
      final records = results[2] as List<DepartmentRecord>;

      _isOffline = false;
      _errorMessage = null;

      // Calculate stats
      _pendingDocumentsCount = documents
          .where((d) => d.status == DocumentStatus.pending)
          .length;

      // The current queue entry is the newest entry still in the queue, the
      // rule the web patient dashboard applies with
      // `status IN ('waiting','in_progress') ORDER BY created_at DESC LIMIT 1`.
      // There is no fallback to the most recent entry: a completed or
      // cancelled visit is history, not the queue the patient is in now.
      _activeQueueEntry = _newestActiveEntry(queueEntries);

      _latestRecord = records.isEmpty ? null : records.first;

      _dataState = (documents.isEmpty && queueEntries.isEmpty && records.isEmpty)
          ? DashboardDataState.empty
          : DashboardDataState.live;

      // 2. Cache the fetched data locally in Drift
      await _cacheDataLocally(patientId, uploaderId, documents, queueEntries, records);
    } on Failure catch (e) {
      // Every read failure is the same for the patient: the server's answer is
      // unknown, so the cached copy is shown as stale with the reason.
      _isOffline = e is NetworkFailure;
      _errorMessage = e.message;
      await _loadFromLocalCache(patientId, uploaderId);
    } catch (e) {
      _errorMessage = FailureMapper.fromException(e).message;
      await _loadFromLocalCache(patientId, uploaderId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The newest entry that is still in the queue, or null when there is none.
  ///
  /// This is the web patient dashboard's rule -- the newest row whose status is
  /// `waiting` or `in_progress` -- so completed and cancelled history is never
  /// the current queue, and neither is a status neither this client nor the
  /// server recognizes. [entries] is normally already newest-first from the
  /// repository; `createdAt` decides anyway, as the server's ordering does.
  PatientQueue? _newestActiveEntry(Iterable<PatientQueue> entries) {
    PatientQueue? newest;
    for (final entry in entries) {
      if (!isActiveQueueStatus(entry.rawStatus)) continue;
      if (newest == null || entry.createdAt.isAfter(newest.createdAt)) {
        newest = entry;
      }
    }
    return newest;
  }

  /// Rebuilds the domain model for a cached queue row. The raw status string
  /// is kept so an unrecognized cached value stays unrecognized instead of
  /// reading back as `waiting`.
  PatientQueue _queueFromCached(CachedPatientQueue row) {
    return PatientQueue(
      id: row.id,
      patientId: row.patientId,
      status: QueueStatus.fromString(row.status),
      rawStatus: row.status,
      department: Department.fromString(row.department) ?? Department.laboratory,
      triageNotes: row.triageNotes,
      priorityLevel: PriorityLevel.fromString(row.priorityLevel),
      estimatedWaitMinutes: row.estimatedWaitMinutes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> _cacheDataLocally(
    String patientId,
    String uploaderId,
    List<Document> docs,
    List<PatientQueue> queueEntries,
    List<DepartmentRecord> records,
  ) async {
    try {
      // Map domain models to Drift cached models
      final cachedDocs = docs
          .map(
            (doc) => CachedDocument(
              id: doc.id,
              patientId: doc.patientId,
              uploaderId: doc.uploaderId,
              fileName: doc.fileName,
              filePath: doc.filePath,
              fileType: doc.fileType,
              status: doc.status.name,
              ocrText: doc.ocrText,
              extractedMetadata: doc.extractedMetadata != null
                  ? jsonEncode(doc.extractedMetadata)
                  : null,
              rejectionReason: doc.rejectionReason,
              createdAt: doc.createdAt,
              updatedAt: doc.updatedAt,
            ),
          )
          .toList();

      final cachedQueue = queueEntries
          .map(
            (q) => CachedPatientQueue(
              id: q.id,
              patientId: q.patientId,
              status: q.rawStatus,
              department: q.department.name,
              triageNotes: q.triageNotes,
              priorityLevel: q.priorityLevel.name,
              estimatedWaitMinutes: q.estimatedWaitMinutes,
              createdAt: q.createdAt,
              updatedAt: q.updatedAt,
            ),
          )
          .toList();

      final cachedRecords = records
          .map(
            (r) => CachedDepartmentRecord(
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
            ),
          )
          .toList();

      // Write to Drift. A successful read replaces the uploader's cached
      // documents, so rows the server no longer returns cannot resurface later
      // on.
      await _localDb.replaceDocumentsForUploader(uploaderId, cachedDocs);
      await _localDb.replaceQueueForPatient(patientId, cachedQueue);
      await _localDb.replaceDepartmentRecords(patientId, cachedRecords);
    } catch (e) {
      debugPrint('Error caching dashboard data: $e');
    }
  }

  Future<void> _loadFromLocalCache(String patientId, String uploaderId) async {
    try {
      final cachedDocs = await _localDb.getDocumentsForPatient(uploaderId);
      final cachedQueue = await _localDb.getQueueForPatient(patientId);
      final cachedRecords = await _localDb.getRecordsForPatient(patientId);

      _pendingDocumentsCount = cachedDocs
          .where((d) => d.status == 'pending')
          .length;

      // The same active-only rule as the live read, applied to the cached
      // snapshot: an offline dashboard must not promote a finished visit to
      // the queue the patient is in now.
      _activeQueueEntry = _newestActiveEntry(
        cachedQueue.map(_queueFromCached),
      );

      if (cachedRecords.isNotEmpty) {
        final latestDriftRec = cachedRecords.first;
        _latestRecord = DepartmentRecord(
          id: latestDriftRec.id,
          patientId: latestDriftRec.patientId,
          recorderId: latestDriftRec.recorderId,
          department:
              Department.fromString(latestDriftRec.department) ??
              Department.laboratory,
          testType: latestDriftRec.testType,
          testResults:
              jsonDecode(latestDriftRec.testResults) as Map<String, dynamic>,
          referenceRangeStatus: ReferenceRangeStatus.fromString(
            latestDriftRec.referenceRangeStatus,
          ),
          notes: latestDriftRec.notes,
          createdAt: latestDriftRec.createdAt,
          updatedAt: latestDriftRec.updatedAt,
        );
      } else {
        _latestRecord = null;
      }

      // The cached copy is shown as stale data: the server's answer is unknown.
      // With nothing cached there is nothing to show at all, which is an error
      // and not an empty dashboard.
      _dataState = (cachedDocs.isEmpty &&
              cachedQueue.isEmpty &&
              cachedRecords.isEmpty)
          ? DashboardDataState.error
          : DashboardDataState.stale;
    } catch (e) {
      debugPrint('Error loading dashboard from local cache: $e');
      _dataState = DashboardDataState.error;
      _errorMessage =
          '${_errorMessage ?? 'The server could not be reached.'}. The cached dashboard could not be read either: ${e.toString()}';
    }
  }
}
