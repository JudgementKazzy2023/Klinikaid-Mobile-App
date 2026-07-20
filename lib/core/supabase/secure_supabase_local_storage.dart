import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/secure_key_value_store.dart';

class SecureSupabaseLocalStorage extends LocalStorage {
  static const sessionKey = 'supabase_session';

  const SecureSupabaseLocalStorage({
    required this.secureStore,
  });

  final SecureKeyValueStore secureStore;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final value = await secureStore.read(key: sessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> accessToken() {
    return secureStore.read(key: sessionKey);
  }

  @override
  Future<void> removePersistedSession() {
    return secureStore.delete(key: sessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return secureStore.write(
      key: sessionKey,
      value: persistSessionString,
    );
  }
}
