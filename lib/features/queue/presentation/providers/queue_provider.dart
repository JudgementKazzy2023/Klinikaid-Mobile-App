import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/repositories/patient_queue_repository.dart';
import '../../../../core/supabase/supabase_client.dart';

class QueueProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _queueRepo = PatientQueueRepository();

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  List<PatientQueue> _queueEntries = [];
  RealtimeChannel? _realtimeChannel;

  QueueProvider(this._localDb);

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  List<PatientQueue> get queueEntries => _queueEntries;

  /// Returns the current active queue entry (waiting or in progress) if any.
  PatientQueue? get activeEntry {
    try {
      return _queueEntries.firstWhere(
        (q) => q.status == QueueStatus.waiting || q.status == QueueStatus.inProgress,
      );
    } catch (_) {
      return _queueEntries.isNotEmpty ? _queueEntries.first : null;
    }
  }

  /// Fetches the queue entries for [patientId] and subscribes to Realtime updates.
  Future<void> fetchQueueAndSubscribe(String patientId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remoteQueue = await _queueRepo.getQueueForPatient(patientId);
      _queueEntries = remoteQueue;
      _isOffline = false;

      // Cache queue entries locally
      final cachedQueue = remoteQueue.map((q) => CachedPatientQueue(
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

      await _localDb.cacheQueueEntries(cachedQueue);
      _isLoading = false;
      notifyListeners();

      // Subscribe to Realtime changes (RLS enforces patient only sees own rows)
      subscribeToQueueUpdates(patientId);
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
      final cachedQueue = await _localDb.getQueueForPatient(patientId);
      _queueEntries = cachedQueue.map((driftQ) => PatientQueue(
        id: driftQ.id,
        patientId: driftQ.patientId,
        status: QueueStatus.fromString(driftQ.status),
        department: Department.fromString(driftQ.department) ?? Department.laboratory,
        triageNotes: driftQ.triageNotes,
        priorityLevel: PriorityLevel.fromString(driftQ.priorityLevel),
        estimatedWaitMinutes: driftQ.estimatedWaitMinutes,
        createdAt: driftQ.createdAt,
        updatedAt: driftQ.updatedAt,
      )).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to load cached queue: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Sets up the Supabase Realtime channel for live inserts and updates on the patient_queue table
  void subscribeToQueueUpdates(String patientId) {
    if (_realtimeChannel != null) {
      return; // Already subscribed
    }

    _realtimeChannel = SupabaseService.client
        .channel('public:patient_queue:patient_id=eq.$patientId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patient_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'patient_id',
            value: patientId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            final eventType = payload.eventType;

            if (newRecord.isEmpty) return;

            final updatedEntry = PatientQueue.fromJson(newRecord);

            if (eventType == PostgresChangeEvent.insert) {
              // Add to local state (most recent first)
              _queueEntries.insert(0, updatedEntry);
            } else if (eventType == PostgresChangeEvent.update) {
              final index = _queueEntries.indexWhere((q) => q.id == updatedEntry.id);
              if (index != -1) {
                _queueEntries[index] = updatedEntry;
              } else {
                _queueEntries.insert(0, updatedEntry);
              }
            } else if (eventType == PostgresChangeEvent.delete) {
              final oldRecord = payload.oldRecord;
              if (oldRecord.isNotEmpty) {
                final deletedId = oldRecord['id'];
                _queueEntries.removeWhere((q) => q.id == deletedId);
              }
            }

            // Sync to local Drift database
            final cachedItem = CachedPatientQueue(
              id: updatedEntry.id,
              patientId: updatedEntry.patientId,
              status: updatedEntry.status.name,
              department: updatedEntry.department.name,
              triageNotes: updatedEntry.triageNotes,
              priorityLevel: updatedEntry.priorityLevel.name,
              estimatedWaitMinutes: updatedEntry.estimatedWaitMinutes,
              createdAt: updatedEntry.createdAt,
              updatedAt: updatedEntry.updatedAt,
            );
            await _localDb.cacheQueueEntries([cachedItem]);

            notifyListeners();
          },
        );

    _realtimeChannel?.subscribe();
  }

  /// Unsubscribes from the realtime updates.
  void unsubscribe() {
    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
