import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
  late DashboardProvider provider;

  setUp(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    db = LocalDatabase(NativeDatabase.memory());
    provider = DashboardProvider(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Local Cache Unit Tests', () {
    test('Can write and read CachedPatient', () async {
      final dob = DateTime(1995, 8, 20);
      final now = DateTime.now();
      
      final patient = CachedPatient(
        id: 'patient-123',
        profileId: 'profile-123',
        firstName: 'Alice',
        lastName: 'Smith',
        dateOfBirth: dob,
        gender: 'female',
        contactNumber: '09776655443',
        email: 'alice@test.com',
        address: '123 Health Ave, Manila',
        createdAt: now,
        updatedAt: now,
      );

      await db.cachePatient(patient);
      final retrieved = await db.getPatient('patient-123');

      expect(retrieved, isNotNull);
      expect(retrieved!.firstName, 'Alice');
      expect(retrieved.lastName, 'Smith');
      expect(retrieved.dateOfBirth, dob);
      expect(retrieved.gender, 'female');
    });

    test('Can write and read CachedDocuments', () async {
      final now = DateTime.now();
      final doc1 = CachedDocument(
        id: 'doc-1',
        patientId: 'patient-123',
        uploaderId: 'user-123',
        fileName: 'referral.pdf',
        filePath: 'uploads/referral.pdf',
        fileType: 'pdf',
        status: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      final doc2 = CachedDocument(
        id: 'doc-2',
        patientId: 'patient-123',
        uploaderId: 'user-123',
        fileName: 'results.pdf',
        filePath: 'uploads/results.pdf',
        fileType: 'pdf',
        status: 'approved',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      );

      await db.cacheDocuments([doc1, doc2]);
      final docs = await db.getDocumentsForPatient('user-123');

      expect(docs.length, 2);
      expect(docs[0].id, 'doc-1');
      expect(docs[0].status, 'pending');
      expect(docs[1].id, 'doc-2');
      expect(docs[1].status, 'approved');
    });

    test('Can write and read CachedPatientQueues', () async {
      final now = DateTime.now();
      final entry = CachedPatientQueue(
        id: 456,
        patientId: 'patient-123',
        status: 'waiting',
        department: 'laboratory',
        priorityLevel: 'routine',
        estimatedWaitMinutes: 25,
        createdAt: now,
        updatedAt: now,
      );

      await db.cacheQueueEntries([entry]);
      final queue = await db.getQueueForPatient('patient-123');

      expect(queue.length, 1);
      expect(queue[0].id, 456);
      expect(queue[0].status, 'waiting');
      expect(queue[0].estimatedWaitMinutes, 25);
    });

    test('Can write and read CachedDepartmentRecords', () async {
      final now = DateTime.now();
      final record = CachedDepartmentRecord(
        id: 'rec-99',
        patientId: 'patient-123',
        recorderId: 'staff-789',
        department: 'laboratory',
        testType: 'Complete Blood Count',
        testResults: jsonEncode({'hemoglobin': 14.2, 'wbc': 6.5}),
        referenceRangeStatus: 'normal',
        createdAt: now,
        updatedAt: now,
      );

      await db.cacheDepartmentRecords([record]);
      final results = await db.getRecordsForPatient('patient-123');

      expect(results.length, 1);
      expect(results[0].id, 'rec-99');
      expect(results[0].testType, 'Complete Blood Count');
      expect(jsonDecode(results[0].testResults)['hemoglobin'], 14.2);
    });
  });

  group('DashboardProvider Cache Fallback Tests', () {
    test('Falls back to local cache when remote calls fail', () async {
      final now = DateTime.now();

      // Pre-populate database cache
      final doc1 = CachedDocument(
        id: 'doc-1',
        patientId: 'patient-123',
        uploaderId: 'user-123',
        fileName: 'referral.pdf',
        filePath: 'uploads/referral.pdf',
        fileType: 'pdf',
        status: 'pending',
        createdAt: now,
        updatedAt: now,
      );
      
      final queue = CachedPatientQueue(
        id: 777,
        patientId: 'patient-123',
        status: 'in_progress',
        department: 'imaging',
        priorityLevel: 'urgent',
        estimatedWaitMinutes: 15,
        createdAt: now,
        updatedAt: now,
      );

      final record = CachedDepartmentRecord(
        id: 'rec-10',
        patientId: 'patient-123',
        recorderId: 'staff-789',
        department: 'imaging',
        testType: 'Chest X-Ray',
        testResults: jsonEncode({'status': 'clear'}),
        referenceRangeStatus: 'normal',
        createdAt: now,
        updatedAt: now,
      );

      await db.cacheDocuments([doc1]);
      await db.cacheQueueEntries([queue]);
      await db.cacheDepartmentRecords([record]);

      // Call fetchDashboardData. Since we are not authenticated in tests, the remote repositories' 
      // Supabase calls will throw error, forcing fallback to cache.
      await provider.fetchDashboardData('patient-123', 'user-123');

      // Verify that provider state loaded correctly from cache
      expect(provider.pendingDocumentsCount, 1);
      
      expect(provider.activeQueueEntry, isNotNull);
      expect(provider.activeQueueEntry!.id, 777);
      expect(provider.activeQueueEntry!.status, QueueStatus.inProgress);
      expect(provider.activeQueueEntry!.estimatedWaitMinutes, 15);

      expect(provider.latestRecord, isNotNull);
      expect(provider.latestRecord!.id, 'rec-10');
      expect(provider.latestRecord!.testType, 'Chest X-Ray');
      expect(provider.latestRecord!.testResults['status'], 'clear');
    });
  });
}
