import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../records/domain/record_grouper.dart';
import '../../data/repositories/staff_queue_repository.dart';

class DepartmentProvider extends ChangeNotifier {
  final _repo = StaffQueueRepository();
  final String department;

  bool _isLoading = false;
  String? _errorMessage;
  List<PatientQueue> _queueEntries = [];
  List<DepartmentRecord> _recentRecords = [];

  RealtimeChannel? _queueChannel;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<PatientQueue> get queueEntries => _queueEntries;
  List<DepartmentRecord> get recentRecords => _recentRecords;
  List<GroupedRecord> get groupedRecords => groupRecords(_recentRecords);

  /// Instantiate with the staff member's department, enforcing security constraint.
  DepartmentProvider(this.department);

  /// Loads today's department-scoped queue and recent records.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final queueFuture = _repo.getQueueForToday(department: department);
      final recordsFuture = _repo.getRecentDepartmentRecords(department);

      final results = await Future.wait([queueFuture, recordsFuture]);

      _queueEntries = results[0] as List<PatientQueue>;
      _recentRecords = results[1] as List<DepartmentRecord>;

      _isLoading = false;
      notifyListeners();

      // Subscribe to department queue updates
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
      final queue = await _repo.getQueueForToday(department: department);
      _queueEntries = queue;
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('Realtime department queue refresh failed: $e');
    }
  }

  /// Subscribes to realtime events for today's queue scoped strictly to this department.
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
