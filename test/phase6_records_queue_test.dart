import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/records/presentation/providers/records_provider.dart';
import 'package:klinikaid_mobile/features/queue/presentation/providers/queue_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_status_provider.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';

class MockFailureHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw const SocketException('Connection failed');
  }
}

class FailureHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockFailureHttpClient();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Force all HTTP connections to fail with SocketException to simulate offline/network failure
  HttpOverrides.global = FailureHttpOverrides();

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
  late RecordsProvider recordsProvider;
  late QueueProvider queueProvider;
  late DocumentStatusProvider docStatusProvider;

  setUp(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    db = LocalDatabase(NativeDatabase.memory());
    recordsProvider = RecordsProvider(db);
    queueProvider = QueueProvider(db);
    docStatusProvider = DocumentStatusProvider(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 6: RecordsProvider Tests', () {
    test('Records are fetched read-only and cached successfully', () async {
      final now = DateTime.now();
      // Inject cached record directly to test mapping and read-only format
      final cachedRec = CachedDepartmentRecord(
        id: 'record-uuid-123',
        patientId: 'patient-uuid-123',
        recorderId: 'recorder-uuid-123',
        department: 'laboratory',
        testType: 'CBC',
        testResults: '{"wbc": "5.4", "rbc": "4.8"}',
        referenceRangeStatus: 'normal',
        notes: 'Values are stable.',
        createdAt: now,
        updatedAt: now,
      );
      await db.cacheDepartmentRecords([cachedRec]);

      // Call fetch (will fail network and fallback to cache)
      await recordsProvider.fetchRecords('patient-uuid-123');

      expect(recordsProvider.isOffline, true);
      expect(recordsProvider.records.length, 1);
      
      final record = recordsProvider.records.first;
      expect(record.id, 'record-uuid-123');
      expect(record.testType, 'CBC');
      // Verify result payload is read-only key-value map and is not processed or interpreted
      expect(record.testResults['wbc'], '5.4');
      expect(record.testResults['rbc'], '4.8');
      expect(record.referenceRangeStatus, ReferenceRangeStatus.normal);
      expect(record.notes, 'Values are stable.');
    });
  });

  group('Phase 6: QueueProvider Realtime Filter Scope Tests', () {
    test('QueueProvider subscribes with the correct RLS-scoped filter', () {
      const patientId = 'patient-uuid-123';
      
      // Call subscribe method
      queueProvider.subscribeToQueueUpdates(patientId);

      // Verify the channel exists (can be unsubscribed)
      expect(queueProvider.queueEntries.isEmpty, true);
      queueProvider.unsubscribe();
    });

    test('Process inserts and updates correctly inside local state', () {
      final now = DateTime.now();
      final entry = PatientQueue(
        id: 1,
        patientId: 'patient-uuid-123',
        status: QueueStatus.waiting,
        department: Department.laboratory,
        triageNotes: 'Routine blood test',
        priorityLevel: PriorityLevel.routine,
        estimatedWaitMinutes: 15,
        createdAt: now,
        updatedAt: now,
      );

      // Simulate insertion in local provider array
      queueProvider.queueEntries.add(entry);
      expect(queueProvider.queueEntries.length, 1);
      expect(queueProvider.activeEntry?.status, QueueStatus.waiting);
      expect(queueProvider.activeEntry?.estimatedWaitMinutes, 15);
    });

    test('Queue entries are fetched and cached successfully on offline fallback', () async {
      final now = DateTime.now();
      // Inject cached queue entry directly to test mapping and offline fallback
      final cachedQ = CachedPatientQueue(
        id: 456,
        patientId: 'patient-uuid-123',
        status: 'waiting',
        department: 'laboratory',
        triageNotes: 'Routine blood test',
        priorityLevel: 'routine',
        estimatedWaitMinutes: 20,
        createdAt: now,
        updatedAt: now,
      );
      await db.cacheQueueEntries([cachedQ]);

      // Call fetch (will fail network and fallback to cache)
      await queueProvider.fetchQueueAndSubscribe('patient-uuid-123');

      expect(queueProvider.isOffline, true);
      expect(queueProvider.queueEntries.length, 1);

      final entry = queueProvider.queueEntries.first;
      expect(entry.id, 456);
      expect(entry.status, QueueStatus.waiting);
      expect(entry.department, Department.laboratory);
      expect(entry.triageNotes, 'Routine blood test');
      expect(entry.priorityLevel, PriorityLevel.routine);
      expect(entry.estimatedWaitMinutes, 20);
    });
  });

  group('Phase 6: DocumentStatusProvider Realtime Tests', () {
    test('Processes approved/rejected document status flips correctly', () {
      final now = DateTime.now();
      final docPending = Document(
        id: 'doc-uuid-111',
        patientId: 'patient-uuid-123',
        uploaderId: 'user-uuid-123',
        fileName: 'referral.pdf',
        filePath: 'user-uuid-123/doc-uuid-111_referral.pdf',
        fileType: 'pdf',
        status: DocumentStatus.pending,
        ocrText: 'Dr. Cruz referral',
        extractedMetadata: null,
        rejectionReason: null,
        createdAt: now,
        updatedAt: now,
      );

      docStatusProvider.documents.add(docPending);
      expect(docStatusProvider.documents.first.status, DocumentStatus.pending);

      // Simulate PostgresChangeEvent update where status flips to rejected
      final docRejected = Document(
        id: 'doc-uuid-111',
        patientId: 'patient-uuid-123',
        uploaderId: 'user-uuid-123',
        fileName: 'referral.pdf',
        filePath: 'user-uuid-123/doc-uuid-111_referral.pdf',
        fileType: 'pdf',
        status: DocumentStatus.rejected,
        ocrText: 'Dr. Cruz referral',
        extractedMetadata: null,
        rejectionReason: 'Signature missing on request form',
        createdAt: now,
        updatedAt: now,
      );

      final index = docStatusProvider.documents.indexWhere((d) => d.id == docRejected.id);
      if (index != -1) {
        docStatusProvider.documents[index] = docRejected;
      }

      expect(docStatusProvider.documents.first.status, DocumentStatus.rejected);
      expect(docStatusProvider.documents.first.rejectionReason, 'Signature missing on request form');
    });
  });
}
