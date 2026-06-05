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

class DashboardProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _docsRepo = DocumentsRepository();
  final _queueRepo = PatientQueueRepository();
  final _recordsRepo = DepartmentRecordsRepository();

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;

  int _pendingDocumentsCount = 0;
  PatientQueue? _activeQueueEntry;
  DepartmentRecord? _latestRecord;

  DashboardProvider(this._localDb);

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;

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

      // Calculate stats
      _pendingDocumentsCount = documents.where((d) => d.status == DocumentStatus.pending).length;
      
      // Active queue entry is the first non-completed/non-cancelled one, or just the most recent
      final activeIndex = queueEntries.indexWhere(
          (q) => q.status == QueueStatus.waiting || q.status == QueueStatus.inProgress);
      _activeQueueEntry = activeIndex != -1 
          ? queueEntries[activeIndex]
          : (queueEntries.isEmpty ? null : queueEntries.first);

      _latestRecord = records.isEmpty ? null : records.first;

      // 2. Cache the fetched data locally in Drift
      await _cacheDataLocally(documents, queueEntries, records);

    } on NetworkFailure catch (_) {
      // Handle network drop, fallback to Drift local cache
      _isOffline = true;
      await _loadFromLocalCache(patientId, uploaderId);
    } catch (e) {
      _errorMessage = e.toString();
      // Even for other failures, try loading from cache
      await _loadFromLocalCache(patientId, uploaderId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _cacheDataLocally(
    List<Document> docs,
    List<PatientQueue> queueEntries,
    List<DepartmentRecord> records,
  ) async {
    try {
      // Map domain models to Drift cached models
      final cachedDocs = docs.map((doc) => CachedDocument(
        id: doc.id,
        patientId: doc.patientId,
        uploaderId: doc.uploaderId,
        fileName: doc.fileName,
        filePath: doc.filePath,
        fileType: doc.fileType,
        status: doc.status.name,
        ocrText: doc.ocrText,
        extractedMetadata: doc.extractedMetadata != null ? jsonEncode(doc.extractedMetadata) : null,
        rejectionReason: doc.rejectionReason,
        createdAt: doc.createdAt,
        updatedAt: doc.updatedAt,
      )).toList();

      final cachedQueue = queueEntries.map((q) => CachedPatientQueue(
        id: q.id,
        patientId: q.patientId,
        status: q.status.name,
        department: q.department.name,
        triageNotes: q.triageNotes,
        priorityLevel: q.priorityLevel.name,
        estimatedWaitMinutes: q.estimatedWaitMinutes,
        createdAt: q.createdAt,
        updatedAt: q.updatedAt,
      )).toList();

      final cachedRecords = records.map((r) => CachedDepartmentRecord(
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

      // Write to Drift
      await _localDb.cacheDocuments(cachedDocs);
      await _localDb.cacheQueueEntries(cachedQueue);
      await _localDb.cacheDepartmentRecords(cachedRecords);
    } catch (e) {
      debugPrint('Error caching dashboard data: $e');
    }
  }

  Future<void> _loadFromLocalCache(String patientId, String uploaderId) async {
    try {
      final cachedDocs = await _localDb.getDocumentsForPatient(uploaderId);
      final cachedQueue = await _localDb.getQueueForPatient(patientId);
      final cachedRecords = await _localDb.getRecordsForPatient(patientId);

      _pendingDocumentsCount = cachedDocs.where((d) => d.status == 'pending').length;

      if (cachedQueue.isNotEmpty) {
        final activeIndex = cachedQueue.indexWhere(
          (q) => q.status == 'waiting' || q.status == 'in_progress',
        );
        final activeDriftQueue = activeIndex != -1 ? cachedQueue[activeIndex] : cachedQueue.first;
        
        _activeQueueEntry = PatientQueue(
          id: activeDriftQueue.id,
          patientId: activeDriftQueue.patientId,
          status: QueueStatus.fromString(activeDriftQueue.status),
          department: Department.fromString(activeDriftQueue.department) ?? Department.laboratory,
          triageNotes: activeDriftQueue.triageNotes,
          priorityLevel: PriorityLevel.fromString(activeDriftQueue.priorityLevel),
          estimatedWaitMinutes: activeDriftQueue.estimatedWaitMinutes,
          createdAt: activeDriftQueue.createdAt,
          updatedAt: activeDriftQueue.updatedAt,
        );
      } else {
        _activeQueueEntry = null;
      }

      if (cachedRecords.isNotEmpty) {
        final latestDriftRec = cachedRecords.first;
        _latestRecord = DepartmentRecord(
          id: latestDriftRec.id,
          patientId: latestDriftRec.patientId,
          recorderId: latestDriftRec.recorderId,
          department: Department.fromString(latestDriftRec.department) ?? Department.laboratory,
          testType: latestDriftRec.testType,
          testResults: jsonDecode(latestDriftRec.testResults) as Map<String, dynamic>,
          referenceRangeStatus: ReferenceRangeStatus.fromString(latestDriftRec.referenceRangeStatus),
          notes: latestDriftRec.notes,
          createdAt: latestDriftRec.createdAt,
          updatedAt: latestDriftRec.updatedAt,
        );
      } else {
        _latestRecord = null;
      }
    } catch (e) {
      debugPrint('Error loading dashboard from local cache: $e');
    }
  }
}
