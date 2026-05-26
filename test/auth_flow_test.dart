import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Disable Flutter test HTTP overrides so real HTTP calls can go through
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

  test('Comprehensive Auth and Onboarding Flow Test', () async {
    // ignore: avoid_print
    print('=== Starting Comprehensive Auth & Onboarding Flow Test ===');

    try {
      // 1. Initialize Supabase Service
      await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
      
      final provider = AuthProvider();
      final rand = Random().nextInt(1000000);
      final email = 'onboard.test.$rand@gmail.com';
      final password = 'Password123!';
      final fullName = 'John Onboarding Doe';

      // Wait for AuthProvider initial state checks to complete
      await Future.delayed(const Duration(milliseconds: 1000));
      expect(provider.isAuthenticated, false);
      expect(provider.hasConsented, false);
      expect(provider.isOnboarded, false);
      // ignore: avoid_print
      print('   Initial state check passed (unauthenticated).');

      // 2. Perform Sign Up
      // ignore: avoid_print
      print('1. Registering user: $email...');
      final signUpSuccess = await provider.signUp(email, password, fullName);
      if (!signUpSuccess) {
        // ignore: avoid_print
        print('   Sign up failed with error: ${provider.errorMessage}');
      }
      expect(signUpSuccess, true);
      expect(provider.isAuthenticated, true);
      // ignore: avoid_print
      print('   User registered and logged in successfully. User ID: ${provider.user?.id}');

      // Wait a moment for Postgres triggers to complete profiles row insertion
      await Future.delayed(const Duration(milliseconds: 1500));

      // 3. Perform Consent Gate Acceptance (RA 10173)
      // ignore: avoid_print
      print('2. Submitting Data Privacy consent (RA 10173)...');
      expect(provider.hasConsented, false);
      final consentSuccess = await provider.acceptConsent();
      if (!consentSuccess) {
        // ignore: avoid_print
        print('   Consent failed with error: ${provider.errorMessage}');
      }
      expect(consentSuccess, true);
      expect(provider.hasConsented, true);
      // ignore: avoid_print
      print('   Consent accepted and recorded in metadata successfully.');

      // 4. Perform Patient Onboarding Form Submission
      // ignore: avoid_print
      print('3. Submitting Patient Onboarding clinical details...');
      expect(provider.isOnboarded, false);
      
      final onboardingSuccess = await provider.submitOnboarding(
        firstName: 'John',
        lastName: 'Doe',
        dateOfBirth: DateTime(1990, 5, 12),
        gender: Gender.male,
        contactNumber: '09123456789',
        address: '123 test street, Rizal, PH',
      );
      
      if (!onboardingSuccess) {
        // ignore: avoid_print
        print('   Onboarding failed with error: ${provider.errorMessage}');
      }
      expect(onboardingSuccess, true);
      expect(provider.isOnboarded, true);
      // ignore: avoid_print
      print('   Patient onboarding row inserted successfully.');

      // 5. Sign Out and Sign Back In to verify state persistence/recovery
      // ignore: avoid_print
      print('4. Signing out user...');
      await provider.signOut();
      expect(provider.isAuthenticated, false);
      expect(provider.hasConsented, false);
      expect(provider.isOnboarded, false);
      // ignore: avoid_print
      print('   Signed out successfully.');

      // ignore: avoid_print
      print('5. Logging back in with password...');
      final signInSuccess = await provider.signIn(email, password);
      if (!signInSuccess) {
        // ignore: avoid_print
        print('   Sign in failed with error: ${provider.errorMessage}');
      }
      expect(signInSuccess, true);
      
      // Wait for status check
      await Future.delayed(const Duration(milliseconds: 1500));
      
      expect(provider.isAuthenticated, true);
      expect(provider.hasConsented, true);
      expect(provider.isOnboarded, true);
      // ignore: avoid_print
      print('   Logged in and restored states successfully: consented=true, onboarded=true.');

      // Clean up
      await provider.signOut();
      // ignore: avoid_print
      print('\n=== Auth Onboarding Flow Test: SUCCESS ===');

    } catch (e, stack) {
      // ignore: avoid_print
      print('\n=== Auth Onboarding Flow Test: FAILED ===');
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print(stack);
      throw Exception('Onboarding flow test failed: $e');
    }
  });
}
