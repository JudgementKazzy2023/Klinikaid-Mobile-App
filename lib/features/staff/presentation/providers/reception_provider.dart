import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/document.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../data/repositories/staff_queue_repository.dart';

class ReceptionProvider extends ChangeNotifier {
  final _repo = StaffQueueRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<PatientQueue> _queueEntries = [];
  List<Document> _pendingDocuments = [];

  RealtimeChannel? _queueChannel;
  RealtimeChannel? _documentsChannel;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<PatientQueue> get queueEntries => _queueEntries;
  List<Document> get pendingDocuments => _pendingDocuments;

  /// Loads today's queue and pending documents, then sets up independent realtime subscriptions.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queueFuture = _repo.getQueueForToday();
      final docsFuture = _repo.getPendingDocuments();

      final results = await Future.wait([queueFuture, docsFuture]);

      _queueEntries = results[0] as List<PatientQueue>;
      _pendingDocuments = results[1] as List<Document>;

      _isLoading = false;
      notifyListeners();

      // Subscribe to live database updates independently
      subscribeQueue();
      subscribeDocuments();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Silently refreshes today's queue.
  Future<void> quietFetchQueue() async {
    try {
      final queue = await _repo.getQueueForToday();
      _queueEntries = queue;
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('Realtime queue refresh failed: $e');
    }
  }

  /// Silently refreshes pending documents.
  Future<void> quietFetchDocuments() async {
    try {
      final docs = await _repo.getPendingDocuments();
      _pendingDocuments = docs;
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('Realtime documents refresh failed: $e');
    }
  }

  /// Updates queue status.
  Future<bool> updateQueueStatus(int queueId, QueueStatus status) async {
    try {
      await _repo.updateQueueStatus(queueId, status);
      // Quietly update local list to reflect changes immediately
      final index = _queueEntries.indexWhere((q) => q.id == queueId);
      if (index != -1) {
        final entry = _queueEntries[index];
        _queueEntries[index] = PatientQueue(
          id: entry.id,
          patientId: entry.patientId,
          status: status,
          department: entry.department,
          triageNotes: entry.triageNotes,
          priorityLevel: entry.priorityLevel,
          estimatedWaitMinutes: entry.estimatedWaitMinutes,
          createdAt: entry.createdAt,
          updatedAt: DateTime.now(),
          patient: entry.patient,
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
      return false;
    }
  }

  /// Approves or rejects a document.
  Future<bool> updateDocumentStatus(
    String documentId,
    DocumentStatus status, {
    String? rejectionReason,
  }) async {
    try {
      await _repo.updateDocumentStatus(documentId, status, rejectionReason: rejectionReason);
      // Quietly update local list
      _pendingDocuments.removeWhere((d) => d.id == documentId);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
      return false;
    }
  }

  /// Set up patient_queue realtime channel.
  void subscribeQueue() {
    if (_queueChannel != null) return;

    _queueChannel = SupabaseService.client
        .channel('public:reception_queue_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patient_queue',
          callback: (payload) async {
            await quietFetchQueue();
          },
        );

    _queueChannel?.subscribe((status, [error]) {
      if (error != null) {
        // ignore: avoid_print
        print('Queue channel subscription error: $error');
      }
    });
  }

  /// Set up documents realtime channel.
  void subscribeDocuments() {
    if (_documentsChannel != null) return;

    _documentsChannel = SupabaseService.client
        .channel('public:reception_documents_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'documents',
          callback: (payload) async {
            await quietFetchDocuments();
          },
        );

    _documentsChannel?.subscribe((status, [error]) {
      if (error != null) {
        // ignore: avoid_print
        print('Documents channel subscription error: $error');
      }
    });
  }

  /// Unsubscribe queue.
  void unsubscribeQueue() {
    if (_queueChannel != null) {
      SupabaseService.client.removeChannel(_queueChannel!);
      _queueChannel = null;
    }
  }

  /// Unsubscribe documents.
  void unsubscribeDocuments() {
    if (_documentsChannel != null) {
      SupabaseService.client.removeChannel(_documentsChannel!);
      _documentsChannel = null;
    }
  }

  /// Unsubscribe all.
  void unsubscribeAll() {
    unsubscribeQueue();
    unsubscribeDocuments();
  }

  @override
  void dispose() {
    unsubscribeAll();
    super.dispose();
  }
}
