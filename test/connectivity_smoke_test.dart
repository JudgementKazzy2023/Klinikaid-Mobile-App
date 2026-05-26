import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/repositories/profiles_repository.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/core/repositories/documents_repository.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';

/// Standard UUID v4 generator helper for creating unique IDs in pure Dart
String generateUuid() {
  final random = Random();
  String hexDigit(int value) => value.toRadixString(16);
  final buffer = StringBuffer();
  for (var i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      buffer.write('-');
    } else if (i == 14) {
      buffer.write('4');
    } else if (i == 19) {
      buffer.write(hexDigit((random.nextInt(4) + 8)));
    } else {
      buffer.write(hexDigit(random.nextInt(16)));
    }
  }
  return buffer.toString();
}

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

  test('Connectivity and RLS Smoke Test (Two-Patient Isolation)', () async {
    // ignore: avoid_print
    print('=== Starting Connectivity & RLS Smoke Test ===');
    
    try {
      // 1. Initialize Supabase with EmptyLocalStorage to run in test environment
      await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
      
      final client = SupabaseService.client;
      final rand = Random().nextInt(1000000);
      final password = 'Password123!';
      
      final emailA = 'patient.a.$rand@gmail.com';
      final emailB = 'patient.b.$rand@gmail.com';

      // 2. Register Patient A
      // ignore: avoid_print
      print('1. Registering Patient A: $emailA...');
      final authResponseA = await client.auth.signUp(
        email: emailA,
        password: password,
        data: {'full_name': 'Patient A'},
      );
      final patientAId = authResponseA.user!.id;
      // ignore: avoid_print
      print('   Patient A registered. User ID: $patientAId');

      // Sign out A so we can sign up B
      await client.auth.signOut();

      // 3. Register Patient B
      // ignore: avoid_print
      print('2. Registering Patient B: $emailB...');
      final authResponseB = await client.auth.signUp(
        email: emailB,
        password: password,
        data: {'full_name': 'Patient B'},
      );
      final patientBId = authResponseB.user!.id;
      // ignore: avoid_print
      print('   Patient B registered. User ID: $patientBId');

      // Wait a moment for trigger execution to complete in the database (profile creation)
      await Future.delayed(const Duration(milliseconds: 1500));

      // 4. Create document data as Patient B (since Patient B is currently logged in)
      // ignore: avoid_print
      print('3. Inserting clinical document for Patient B...');
      final docsRepo = DocumentsRepository();
      final docId = generateUuid();
      final documentB = Document(
        id: docId,
        uploaderId: patientBId,
        fileName: 'patient_b_doc.pdf',
        filePath: 'uploads/patient_b_doc.pdf',
        fileType: 'pdf',
        status: DocumentStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final insertedDoc = await docsRepo.insertDocument(documentB);
      if (insertedDoc.id != docId) {
        throw Exception('Document creation failed: ID mismatch');
      }
      // ignore: avoid_print
      print('   Patient B document created successfully: ${insertedDoc.fileName}');

      // Sign out B so we can sign back in as A
      await client.auth.signOut();

      // 5. Sign back in as Patient A
      // ignore: avoid_print
      print('4. Logging back in as Patient A...');
      final authSignInA = await client.auth.signInWithPassword(
        email: emailA,
        password: password,
      );
      if (authSignInA.user?.id != patientAId) {
        throw Exception('Login failed: user ID mismatch');
      }
      // ignore: avoid_print
      print('   Logged in as Patient A.');

      final profilesRepo = ProfilesRepository();

      // 6. Fetch own profile (Patient A)
      // ignore: avoid_print
      print('5. Fetching Patient A\'s own profile...');
      final profileA = await profilesRepo.getProfile(patientAId);
      if (profileA.fullName != 'Patient A') {
        throw Exception('Data mismatch: expected "Patient A", got "${profileA.fullName}"');
      }
      // ignore: avoid_print
      print('   Patient A profile fetched successfully: ${profileA.fullName}');

      // 7. Attempt to SELECT Patient B's profile (should be blocked by RLS)
      // ignore: avoid_print
      print('6. Attempting to SELECT Patient B\'s profile (Patient A is authenticated)...');
      try {
        await profilesRepo.getProfile(patientBId);
        throw Exception('Security Failure: Patient A successfully selected Patient B\'s profile!');
      } on DatabaseFailure catch (e) {
        // ignore: avoid_print
        print('   SELECT blocked as expected. Exception: $e');
      }

      // 8. Attempt to SELECT Patient B's documents (should return empty list)
      // ignore: avoid_print
      print('7. Attempting to SELECT Patient B\'s documents (Patient A is authenticated)...');
      final patientBDocs = await docsRepo.getDocumentsForPatient(patientBId);
      if (patientBDocs.isNotEmpty) {
        throw Exception('Security Failure: Patient A successfully selected ${patientBDocs.length} documents belonging to Patient B!');
      }
      // ignore: avoid_print
      print('   SELECT returned empty list (0 rows) as expected due to RLS filtering.');

      // 9. Attempt to INSERT a document for Patient B (violating INSERT WITH CHECK policy, expecting code 42501)
      // ignore: avoid_print
      print('8. Attempting to INSERT a document for Patient B as Patient A (violating WITH CHECK)...');
      final hackDoc = Document(
        id: generateUuid(),
        uploaderId: patientBId, // Foreign uploader id
        fileName: 'hacked_doc.pdf',
        filePath: 'uploads/hacked_doc.pdf',
        fileType: 'pdf',
        status: DocumentStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      try {
        await docsRepo.insertDocument(hackDoc);
        throw Exception('Security Failure: Patient A successfully inserted a document for Patient B!');
      } on DatabaseFailure catch (e) {
        // Check that the mapped error maps code 42501 (contains "Access denied")
        if (!e.message.contains('Access denied')) {
          throw Exception('Assert Failure: Expected RLS violation message containing "Access denied", got "$e"');
        }
        // ignore: avoid_print
        print('   INSERT blocked with RLS violation code 42501 as expected. Exception: $e');
      }

      // 10. Check clinical patient onboarding row status
      // ignore: avoid_print
      print('9. Checking clinical patient onboarding row status...');
      final patientsRepo = PatientsRepository();
      final patientRecord = await patientsRepo.getPatientByProfileId(patientAId);
      if (patientRecord != null) {
        throw Exception('Expected null patient record for new user, but got one.');
      }
      // ignore: avoid_print
      print('   Onboarding row is null as expected (patient requires onboarding).');

      // Clean up
      await client.auth.signOut();
      // ignore: avoid_print
      print('\n=== Smoke Test: SUCCESS (All RLS checks passed) ===');
      
    } catch (e, stack) {
      // ignore: avoid_print
      print('\n=== Smoke Test: FAILED ===');
      // ignore: avoid_print
      print(e);
      // ignore: avoid_print
      print(stack);
      // Exit with error code to signal failure to the runner
      throw Exception('Smoke test execution failed: $e');
    }
  });
}
