import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';
import '../security/secure_key_value_store.dart';
import 'secure_supabase_local_storage.dart';
import 'supabase_session_migration.dart';

/// Service class that manages the lifecycle and access of the Supabase Client.
class SupabaseService {
  /// Initializes the Supabase instance using credentials from [Env].
  static Future<void> initialize({
    LocalStorage? localStorage,
    bool autoRefreshToken = true,
    SecureKeyValueStore? secureStore,
  }) async {
    final resolvedSecureStore = secureStore ?? FlutterSecureKeyValueStore();
    final resolvedLocalStorage = localStorage ??
        SecureSupabaseLocalStorage(
          secureStore: resolvedSecureStore,
        );

    if (localStorage == null) {
      await const SupabaseSessionMigration().migrateLegacyPrefsSession(
        supabaseUrl: Env.supabaseUrl,
        secureStore: resolvedSecureStore,
      );
    }

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: resolvedLocalStorage,
        autoRefreshToken: autoRefreshToken,
      ),
    );
  }

  static SupabaseClient? _mockClient;
  static set mockClient(SupabaseClient? mock) => _mockClient = mock;

  /// Returns the singleton [SupabaseClient] instance.
  static SupabaseClient get client => _mockClient ?? Supabase.instance.client;
}
