import 'package:flutter/widgets.dart';
import '../../../../core/models/profile.dart';
import '../presentation/providers/auth_provider.dart';
import 'session_activity_service.dart';

class SessionLifecycleObserver with WidgetsBindingObserver {
  final SessionActivityService activity;
  final AuthProvider auth;

  SessionLifecycleObserver(this.activity, this.auth);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        activity.persistLastActivity();
        break;
      case AppLifecycleState.resumed:
        _checkOnResume();
        break;
      default:
        break;
    }
  }

  Future<void> _checkOnResume() async {
    if (!auth.isAuthenticated) return;
    await activity.restoreLastActivity();
    
    final role = auth.profile?.role;
    final timeout = (role == UserRole.patient)
        ? const Duration(minutes: 20)
        : const Duration(minutes: 10);

    if (activity.idleTime > timeout) {
      auth.handleInactivityLogout();
    }
  }
}
