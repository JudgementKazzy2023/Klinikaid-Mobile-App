import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../records/domain/record_grouper.dart';
import '../../data/department_repository.dart';

class DepartmentProvider extends ChangeNotifier {
  final _repo = DepartmentRepository();
  final String department;

  bool _isLoading = false;
  String? _errorMessage;
  String? _queueError;
  String? _recordsError;
  List<PatientQueue> _queueEntries = [];
  int _queueTotal = 0;
  List<DepartmentRecord> _recentRecords = [];

  RealtimeChannel? _queueChannel;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// The failure of the queue read, if it failed.
  ///
  /// The queue and the records history keep their failures apart: a broken
  /// records read says nothing about the queue and must not hide it.
  String? get queueError => _queueError;

  /// The failure of the records history read, if it failed.
  String? get recordsError => _recordsError;

  List<PatientQueue> get queueEntries => _queueEntries;

  /// The exact number of open entries the server holds for this department.
  ///
  /// The count comes from the server, not from the length of the list that was
  /// read back, so the workload the screen reports is never the size of one
  /// page.
  int get queueTotal => _queueTotal;

  List<DepartmentRecord> get recentRecords => _recentRecords;
  List<GroupedRecord> get groupedRecords => groupRecords(_recentRecords);

  DepartmentProvider(this.department);

  /// Loads the active department-scoped queue and recent records.
  ///
  /// Both reads run together and each keeps its own failure, so a broken
  /// records read does not take the queue down with it.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    _queueError = null;
    _recordsError = null;
    notifyListeners();

    try {
      final results = await Future.wait(<Future<Object?>>[
        _repo
            .getActiveQueue()
            .then<Object?>((page) => page)
            .catchError((Object e) => e),
        _repo
            .getRecordsHistory()
            .then<Object?>((records) => records)
            .catchError((Object e) => e),
      ]);

      final queue = results[0];
      if (queue is DepartmentQueuePage) {
        _queueEntries = queue.entries;
        _queueTotal = queue.total;
      } else {
        _queueError = FailureMapper.fromException(queue).message;
      }

      final records = results[1];
      if (records is List) {
        _recentRecords = records.cast<DepartmentRecord>();
      } else {
        _recordsError = FailureMapper.fromException(records).message;
      }

      _errorMessage = _queueError ?? _recordsError;

      _isLoading = false;
      notifyListeners();

      // Subscribe to department queue updates in real-time
      subscribeQueue();
    } catch (e) {
      _isLoading = false;
      _errorMessage = FailureMapper.fromException(e).message;
      notifyListeners();
    }
  }

  /// Silently refreshes the department's queue.
  Future<void> quietFetchQueue() async {
    try {
      final queue = await _repo.getActiveQueue();
      _queueEntries = queue.entries;
      _queueTotal = queue.total;
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('Realtime department queue refresh failed: $e');
    }
  }

  /// Subscribes to active queue updates scoped strictly to this department.
  void subscribeQueue() {
    if (_queueChannel != null) return;

    _queueChannel = SupabaseService.client
        .channel('public:department_${department}_queue_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patient_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'department',
            value: department,
          ),
          callback: (payload) async {
            await quietFetchQueue();
          },
        );

    _queueChannel?.subscribe((status, [error]) {
      if (error != null) {
        // ignore: avoid_print
        print('Department queue channel subscription error: $error');
      }
    });
  }

  /// Unsubscribes from realtime updates.
  void unsubscribeQueue() {
    if (_queueChannel != null) {
      SupabaseService.client.removeChannel(_queueChannel!);
      _queueChannel = null;
    }
  }

  @override
  void dispose() {
    unsubscribeQueue();
    super.dispose();
  }
}
