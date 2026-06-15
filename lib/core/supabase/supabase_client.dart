import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Service class that manages the lifecycle and access of the Supabase Client.
class SupabaseService {
  /// Initializes the Supabase instance using credentials from [Env].
  static Future<void> initialize({LocalStorage? localStorage, bool autoRefreshToken = true}) async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: localStorage,
        autoRefreshToken: autoRefreshToken,
      ),
    );
  }

  /// Returns the singleton [SupabaseClient] instance.
  static SupabaseClient get client => Supabase.instance.client;
}
