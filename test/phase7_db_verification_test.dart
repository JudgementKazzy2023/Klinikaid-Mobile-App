import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  test('Verification of Database Profile Row Insertion and Patient Role', () async {
    print('=== Initializing Supabase ===');
    await Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );

    final client = Supabase.instance.client;
    final rand = Random().nextInt(1000000);
    final email = 'evidence.test.$rand@gmail.com';
    final password = 'Password123!';
    final fullName = 'Evidence Verification User';

    print('=== Registering User via auth.signUp: $email ===');
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': 'patient',
      },
    );

    final userId = response.user?.id;
    expect(userId, isNotNull);
    print('User registered successfully in Auth. User ID: $userId');

    // Wait a brief moment for database trigger to run
    await Future.delayed(const Duration(milliseconds: 2500));

    print('=== Querying profiles table for User ID: $userId ===');
    final profile = await client
        .from('profiles')
        .select()
        .eq('id', userId!)
        .single();

    print('DATABASE_EVIDENCE_START');
    print(profile);
    print('DATABASE_EVIDENCE_END');

    expect(profile['role'], 'patient');
    expect(profile['full_name'], fullName);

    // Clean up
    await client.auth.signOut();
  });
}
