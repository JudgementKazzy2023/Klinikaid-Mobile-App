import 'package:shared_preferences/shared_preferences.dart';

import '../security/secure_key_value_store.dart';
import 'secure_supabase_local_storage.dart';

class SupabaseSessionMigration {
  const SupabaseSessionMigration();

  static String legacyPrefsKeyFromUrl(String supabaseUrl) {
    final host = Uri.parse(supabaseUrl).host;
    final projectRef = host.split('.').first;
    return 'sb-$projectRef-auth-token';
  }

  Future<bool> migrateLegacyPrefsSession({
    required String supabaseUrl,
    required SecureKeyValueStore secureStore,
    SharedPreferences? sharedPreferences,
  }) async {
    final prefs = sharedPreferences ?? await SharedPreferences.getInstance();
    final legacyKey = legacyPrefsKeyFromUrl(supabaseUrl);
    final legacySession = prefs.getString(legacyKey);

    if (legacySession == null || legacySession.isEmpty) {
      return false;
    }

    final existingSecureSession = await secureStore.read(
      key: SecureSupabaseLocalStorage.sessionKey,
    );
    if (existingSecureSession == null || existingSecureSession.isEmpty) {
      await secureStore.write(
        key: SecureSupabaseLocalStorage.sessionKey,
        value: legacySession,
      );
    }

    await prefs.remove(legacyKey);
    return true;
  }
}
