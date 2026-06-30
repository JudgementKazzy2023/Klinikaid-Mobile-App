import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';

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

  late LocalDatabase db;
  late DocumentSubmissionProvider provider;

  setUp(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    db = LocalDatabase(NativeDatabase.memory());
    provider = DocumentSubmissionProvider(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 4: OCR Pre-Screen Parser Logic', () {
    final patient = Patient(
      id: 'patient-uuid-123',
      profileId: 'user-uuid-123',
      firstName: 'Jane',
      lastName: 'Miller',
      dateOfBirth: DateTime(1988, 3, 14),
      gender: Gender.female,
      contactNumber: '09887766554',
      address: 'Rizal, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Identifies all fields correctly when all are present', () {
      const ocrText = 
          'Bloodcare Medical Laboratory\n'
          'Date: 10/12/2026\n'
          'Patient Name: Jane Miller\n'
          'Requesting Physician: Dr. Robert Cruz, M.D.\n'
          'Test Required: CBC Laboratory Blood Test';

      final results = provider.preScreenOcrText(ocrText, patient.firstName, patient.lastName);
      expect(results['identity_match'], true);
      expect(results['ocr_text'], ocrText);
    });

    test('Correctly identifies missing date and doctor fields but matching name', () {
      const ocrText = 
          'Klinik Diagnostic Center\n'
          'Name: Jane Miller\n'
          'Referred for an ECG checkup';

      final results = provider.preScreenOcrText(ocrText, patient.firstName, patient.lastName);
      expect(results['identity_match'], true);
    });

    test('Correctly flags patient name mismatch', () {
      const ocrText = 
          'Date: 2026-06-02\n'
          'Dr. Santos, M.D.\n'
          'Patient Name: Alice Smith\n'
          'Lab Request: Urine analysis';

      final results = provider.preScreenOcrText(ocrText, patient.firstName, patient.lastName);
      expect(results['identity_match'], false); // Jane Miller is not in the text
    });
  });

  group('Phase 4: Offline Queueing & Account Matching', () {
    final patient = Patient(
      id: 'patient-uuid-123',
      profileId: 'user-uuid-123',
      firstName: 'Jane',
      lastName: 'Miller',
      dateOfBirth: DateTime(1988, 3, 14),
      gender: Gender.female,
      contactNumber: '09887766554',
      address: 'Rizal, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Queues file to Drift SQLite when offline exception occurs', () async {
      // Create a temporary mock file locally
      final tempDir = Directory.systemTemp.createTempSync();
      final localFile = File('${tempDir.path}/test_referral.jpg');
      localFile.writeAsBytesSync([0, 1, 2, 3]);

      // Call submitDocument. Since we are running in tests and offline (or not logged in),
      // it will fail remote upload and queue the item.
      final success = await provider.submitDocument(
        localFilePath: localFile.path,
        originalFileName: 'test_referral.jpg',
        fileExtension: 'jpg',
        patient: patient,
        isTest: true,
      );

      expect(success, true);
      expect(provider.errorMessage, contains('offline'));

      // Check Drift SQLite queue directly
      final allQueued = await db.getQueuedDocuments();
      expect(allQueued.length, 1);
      expect(allQueued[0].fileName, 'test_referral.jpg');
      expect(allQueued[0].fileType, 'jpg');

      // Cleanup local temp file
      tempDir.deleteSync(recursive: true);
    });

    test('Orphans and blocks submission when uploader_id does not match active auth uid', () async {
      final now = DateTime.now();
      
      // Inject a queued document belonging to a different user ID (foreign uploader id)
      final foreignDoc = OfflineDocument(
        id: 'offline-uuid-999',
        patientId: 'patient-uuid-123',
        uploaderId: 'foreign-user-uuid',
        fileName: 'another_user_file.jpg',
        localFilePath: '/mock/path/another_user_file.jpg',
        fileType: 'jpg',
        ocrText: 'Dr. Cruz referral',
        extractedMetadata: jsonEncode({'matched_fields': ['doctor']}),
        createdAt: now,
      );
      await db.queueOfflineDocument(foreignDoc);

      // Trigger sync
      await provider.syncOfflineQueue();

      // Verify it was filtered to orphaned submissions and not uploaded/removed from local SQLite
      expect(provider.orphanedSubmissions.length, 1);
      expect(provider.orphanedSubmissions[0].id, 'offline-uuid-999');
      expect(provider.queuedSubmissions.isEmpty, true);

      // Verify it still remains in Drift SQLite queue
      final remaining = await db.getQueuedDocuments();
      expect(remaining.length, 1);
      expect(remaining[0].id, 'offline-uuid-999');
    });
  });
}
