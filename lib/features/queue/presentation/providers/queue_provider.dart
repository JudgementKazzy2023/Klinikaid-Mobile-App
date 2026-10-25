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
  String? _patientId;
  bool _disposed = false;
  Future<void> _refreshes = Future.value();

  QueueProvider(this._localDb);

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  List<PatientQueue> get queueEntries => _queueEntries;

  /// Returns the current active queue entry (waiting or in progress) if any.
  ///
  /// The rule runs on [PatientQueue.rawStatus], so a status this client does
  /// not recognise is never active -- not even though it parses to
  /// [QueueStatus.waiting].
  PatientQueue? get activeEntry {
    try {
      return _queueEntries.firstWhere((q) => isActiveQueueStatus(q.rawStatus));
    } catch (_) {
      return _queueEntries.isNotEmpty ? _queueEntries.first : null;
    }
  }

  /// Fetches the queue entries for [patientId] and subscribes to Realtime updates.
  Future<void> fetchQueueAndSubscribe(String patientId) {
    if (_patientId != patientId) {
      unsubscribe();
      _patientId = patientId;
      _queueEntries = [];
    }
    // Serialize snapshots so a slower earlier fetch cannot restore deleted rows.
    _refreshes = _refreshes.then((_) => _fetchQueue(patientId));
    return _refreshes;
  }

  Future<void> _fetchQueue(String patientId) async {
    if (_disposed || _patientId != patientId) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remoteQueue = await _queueRepo.getQueueForPatient(patientId);
      if (_disposed || _patientId != patientId) return;

      // Cache queue entries locally
      final cachedQueue = remoteQueue
          .map(
            (q) => CachedPatientQueue(
              id: q.id,
              patientId: q.patientId,
              // The raw server status, the same the dashboard caches: writing
              // the canonicalised value here would turn an unknown status into
              // `waiting` for every later offline read.
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

      await _localDb.replaceQueueForPatient(patientId, cachedQueue);
      if (_disposed || _patientId != patientId) return;
      _queueEntries = remoteQueue;
      _isOffline = false;
      _isLoading = false;
      notifyListeners();

      // Subscribe to Realtime changes (RLS enforces patient only sees own rows)
      subscribeToQueueUpdates(patientId);
    } on NetworkFailure catch (_) {
      if (_disposed || _patientId != patientId) return;
      _isOffline = true;
      await _loadFromCache(patientId);
    } catch (e) {
      if (_disposed || _patientId != patientId) return;
      _errorMessage = FailureMapper.fromException(e).message;
      await _loadFromCache(patientId);
    }
  }

  Future<void> _loadFromCache(String patientId) async {
    try {
      final cachedQueue = await _localDb.getQueueForPatient(patientId);
      if (_disposed || _patientId != patientId) return;
      _queueEntries = cachedQueue
          .map(
            (driftQ) => PatientQueue(
              id: driftQ.id,
              patientId: driftQ.patientId,
              status: QueueStatus.fromString(driftQ.status),
              // Keep the cached string verbatim: [QueueStatus.fromString]
              // maps unknown values to `waiting`, and only the raw spelling
              // tells an unknown status apart from a real waiting one.
              rawStatus: driftQ.status,
              department:
                  Department.fromString(driftQ.department) ??
                  Department.laboratory,
              triageNotes: driftQ.triageNotes,
              priorityLevel: PriorityLevel.fromString(driftQ.priorityLevel),
              estimatedWaitMinutes: driftQ.estimatedWaitMinutes,
              createdAt: driftQ.createdAt,
              updatedAt: driftQ.updatedAt,
            ),
          )
          .toList();

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
          // DELETE may contain only a primary key under RLS. Do not rely on a
          // patient filter or mutate local state from potentially stale payloads.
          callback: (payload) => handleQueueChange(patientId, payload),
        );

    _realtimeChannel?.subscribe();
  }

  @visibleForTesting
  Future<void> handleQueueChange(
    String patientId,
    PostgresChangePayload payload,
  ) async {
    if (_disposed || _patientId != patientId) return;
    final record = payload.eventType == PostgresChangeEvent.delete
        ? payload.oldRecord
        : payload.newRecord;
    final recordPatientId = record['patient_id'];
    if (recordPatientId != null && recordPatientId != patientId) return;
    // Unknown identity (notably DELETE oldRecord:{id}) requires an authoritative
    // scoped read. The same read prevents delayed INSERT/UPDATE resurrection.
    await fetchQueueAndSubscribe(patientId);
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
    _disposed = true;
    unsubscribe();
    super.dispose();
  }
}
