import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionActivityService {
  final DateTime Function() _clock;
  DateTime _lastActivityAt;
  bool _exempt = false;
  Timer? _checkTimer;

  SessionActivityService({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now()),
        _lastActivityAt = (clock ?? (() => DateTime.now()))();

  bool get isExempt => _exempt;
  DateTime get lastActivityAt => _lastActivityAt;

  void recordActivity() {
    if (!_exempt) {
      _lastActivityAt = _clock();
    }
  }

  void setExempt(bool exempt) {
    _exempt = exempt;
    if (exempt) {
      _lastActivityAt = _clock(); // Reset when entering exempt zone
    }
  }

  Duration get idleTime => _clock().difference(_lastActivityAt);

  void startMonitoring({
    required Duration timeout,
    required VoidCallback onTimeout,
  }) {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_exempt && idleTime > timeout) {
        onTimeout();
      }
    });
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> persistLastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_activity_ms', _lastActivityAt.millisecondsSinceEpoch);
  }

  Future<void> restoreLastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_activity_ms');
    if (ms != null) {
      _lastActivityAt = DateTime.fromMillisecondsSinceEpoch(ms);
    }
  }
}
