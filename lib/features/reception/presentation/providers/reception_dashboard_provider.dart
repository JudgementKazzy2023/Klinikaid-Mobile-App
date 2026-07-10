import 'package:flutter/material.dart';
import '../../data/reception_repository.dart';
import '../../domain/recent_triage_entry.dart';

class ReceptionDashboardProvider extends ChangeNotifier {
  final ReceptionRepository _repo;

  bool _isLoading = false;
  String? _errorMessage;

  int _activeQueueCount = 0;
  int _pendingSubmissionsCount = 0;
  int _routedTodayCount = 0;
  List<RecentTriageEntry> _recentTriageList = [];

  ReceptionDashboardProvider({ReceptionRepository? repository})
      : _repo = repository ?? ReceptionRepository();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  int get activeQueueCount => _activeQueueCount;
  int get pendingSubmissionsCount => _pendingSubmissionsCount;
  int get routedTodayCount => _routedTodayCount;
  List<RecentTriageEntry> get recentTriageList => _recentTriageList;

  Future<void> loadDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repo.countActiveQueue(),
        _repo.countPendingSubmissions(),
        _repo.countRoutedToday(),
        _repo.getRecentTriage(limit: 5),
      ]);

      _activeQueueCount = results[0] as int;
      _pendingSubmissionsCount = results[1] as int;
      _routedTodayCount = results[2] as int;
      _recentTriageList = results[3] as List<RecentTriageEntry>;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshDashboard() async {
    await loadDashboard();
  }
}
