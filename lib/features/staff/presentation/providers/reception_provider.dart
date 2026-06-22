import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/document.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../data/repositories/staff_queue_repository.dart';

/// Reception provider for the receptionist mobile mode.
///
/// As of 2026-06-22, the Today's Queue tab is hidden from the receptionist
/// UI per joint decision with the web team. The queue list state,
/// loading methods, and Realtime subscription are preserved here so the
/// data is available for derived UI elements (notification badges,
/// summary counts) or for re-enabling the queue tab in a future release.
///
/// State changes (Mark Arrived, Approve, Reject, etc.) remain unsupported.
/// The receptionist mobile mode is fully read-only.
class ReceptionProvider extends ChangeNotifier {
  final _repo = StaffQueueRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<PatientQueue> _queueEntries = [];
  List<Document> _pendingDocuments = [];
  List<Document> _approvedDocuments = [];
  List<Document> _rejectedDocuments = [];

  RealtimeChannel? _queueChannel;
  RealtimeChannel? _documentsChannel;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<PatientQueue> get queueEntries => _queueEntries;
  List<Document> get pendingDocuments => _pendingDocuments;
  List<Document> get approvedDocuments => _approvedDocuments;
  List<Document> get rejectedDocuments => _rejectedDocuments;

  /// Loads today's queue and documents of all statuses, then sets up independent realtime subscriptions.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queueFuture = _repo.getQueueForToday();
      final pendingFuture = _repo.getDocumentsByStatus(status: DocumentStatus.pending);
      final approvedFuture = _repo.getDocumentsByStatus(status: DocumentStatus.approved, maxAge: const Duration(days: 30));
      final rejectedFuture = _repo.getDocumentsByStatus(status: DocumentStatus.rejected, maxAge: const Duration(days: 30));

      final results = await Future.wait([queueFuture, pendingFuture, approvedFuture, rejectedFuture]);

      _queueEntries = results[0] as List<PatientQueue>;
      _pendingDocuments = results[1] as List<Document>;
      _approvedDocuments = results[2] as List<Document>;
      _rejectedDocuments = results[3] as List<Document>;

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

  /// Silently refreshes all documents.
  Future<void> quietFetchDocuments() async {
    try {
      final results = await Future.wait([
        _repo.getDocumentsByStatus(status: DocumentStatus.pending),
        _repo.getDocumentsByStatus(status: DocumentStatus.approved, maxAge: const Duration(days: 30)),
        _repo.getDocumentsByStatus(status: DocumentStatus.rejected, maxAge: const Duration(days: 30)),
      ]);
      _pendingDocuments = results[0];
      _approvedDocuments = results[1];
      _rejectedDocuments = results[2];
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('Realtime documents refresh failed: $e');
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
