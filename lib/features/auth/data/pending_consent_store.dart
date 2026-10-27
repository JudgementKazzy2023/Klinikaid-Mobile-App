import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Privacy consent the patient gave on this phone that the server has not
/// stored yet, kept per account so it can be sent again later.
///
/// shortcut: exists because the server currently refuses a patient's own
/// `profiles` update (web PR #255). Remove once that fix is live and every
/// pending consent has synced.
class PendingConsentStore {
  static String _key(String userId) => 'pending_privacy_consent_$userId';

  Future<DateTime?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key(userId));
      return value == null ? null : DateTime.tryParse(value);
    } catch (e) {
      debugPrint('[PendingConsentStore] read failed: $e');
      return null;
    }
  }

  Future<void> save(String userId, DateTime acceptedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), acceptedAt.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('[PendingConsentStore] save failed: $e');
    }
  }

  Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (e) {
      debugPrint('[PendingConsentStore] clear failed: $e');
    }
  }
}
