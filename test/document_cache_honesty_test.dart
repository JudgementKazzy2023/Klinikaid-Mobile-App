import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/repositories/documents_repository.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_status_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/document_status_screen.dart';

/// A documents repository that fails the way a broken server does, so the
/// provider's fallbacks can be exercised without a network round trip.
class FailingDocumentsRepository extends DocumentsRepository {
  FailingDocumentsRepository(this.error);

  final Object error;

  @override
  Future<List<Document>> getDocumentsForPatient(String uploaderId) async {
    throw error;
  }
}

/// Only the live WebSocket is suppressed; repositories, HTTP parsing, cache and
/// the production read path remain real. No network or production writes.
class LocalDocumentProvider extends DocumentStatusProvider {
  LocalDocumentProvider(super.db, {super.documentsRepository});

  @override
  void subscribeToDocumentUpdates(String uploaderId) {}
}

/// An auth provider whose signed-in account and patient row the test controls.
class MockAuthProvider extends AuthProvider {
  MockAuthProvider(SupabaseClient client) : super(client: client);

  @override
  User? get user => User(
        id: 'uploader-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-10-20T00:00:00Z',
        email: 'patient@example.com',
      );

  @override
  Patient? get patient => Patient(
        id: 'patient-1',
        firstName: 'John',
        lastName: 'Doe',
        dateOfBirth: DateTime(1985, 5, 5),
        gender: Gender.male,
        contactNumber: '09123456789',
        address: 'City A',
        createdAt: DateTime.utc(2026, 10, 20),
        updatedAt: DateTime.utc(2026, 10, 20),
      );
}

/// A row of the `documents` table, in the shape the server returns it.
Map<String, dynamic> serverRow({
  String id = 'doc-1',
  String patientId = 'patient-1',
  String uploaderId = 'uploader-1',
  String status = 'pending',
  String createdAt = '2026-10-20T09:22:13Z',
}) {
  return {
    'id': id,
    'patient_id': patientId,
    'uploader_id': uploaderId,
    'file_name': 'referral.pdf',
    'file_path': 'patient-1/referral.pdf',
    'file_type': 'pdf',
    'status': status,
    'ocr_text': null,
    'extracted_metadata': null,
    'rejection_reason': null,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

/// A row of the `patient_queue` table, in the shape the server returns it.
Map<String, dynamic> serverQueueRow({
  int id = 1,
  String patientId = 'patient-1',
}) {
  return {
    'id': id,
    'patient_id': patientId,
    'status': 'waiting',
    'department': 'laboratory',
    'triage_notes': null,
    'priority_level': 'routine',
    'estimated_wait_minutes': 15,
    'created_at': '2026-10-20T09:22:13Z',
    'updated_at': '2026-10-20T09:22:13Z',
  };
}

/// A row of the `department_records` table, in the shape the server returns it.
Map<String, dynamic> serverRecordRow({
  String id = 'rec-1',
  String patientId = 'patient-1',
}) {
  return {
    'id': id,
    'patient_id': patientId,
    'recorder_id': 'recorder-1',
    'department': 'laboratory',
    'test_type': 'CBC',
    'test_name': 'Hemoglobin',
    'test_value': '14.2',
    'notes': null,
    'created_at': '2026-10-20T09:22:13Z',
    'updated_at': '2026-10-20T09:22:13Z',
  };
}

/// A cached document, as the local database stores it.
CachedDocument cachedRow({
  String id = 'doc-1',
  String patientId = 'patient-1',
  String uploaderId = 'uploader-1',
  String status = 'pending',
  DateTime? createdAt,
}) {
  return CachedDocument(
    id: id,
    patientId: patientId,
    uploaderId: uploaderId,
    fileName: 'referral.pdf',
    filePath: 'patient-1/referral.pdf',
    fileType: 'pdf',
    status: status,
    ocrText: null,
    extractedMetadata: null,
    rejectionReason: null,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 20, 9, 22, 13),
    updatedAt: createdAt ?? DateTime.utc(2026, 10, 20, 9, 22, 13),
  );
}

/// A cached queue entry, as the local database stores it.
CachedPatientQueue cachedQueueRow({
  int id = 1,
  String patientId = 'patient-1',
}) {
  return CachedPatientQueue(
    id: id,
    patientId: patientId,
    status: 'waiting',
    department: 'laboratory',
    triageNotes: null,
    priorityLevel: 'routine',
    estimatedWaitMinutes: 15,
    createdAt: DateTime.utc(2026, 10, 20, 9, 22, 13),
    updatedAt: DateTime.utc(2026, 10, 20, 9, 22, 13),
  );
}

/// A cached department record, as the local database stores it.
CachedDepartmentRecord cachedRecordRow({
  String id = 'rec-1',
  String patientId = 'patient-1',
}) {
  return CachedDepartmentRecord(
    id: id,
    patientId: patientId,
    recorderId: 'recorder-1',
    department: 'laboratory',
    testType: 'CBC',
    testResults: jsonEncode({'test_name': 'Hemoglobin', 'test_value': '14.2'}),
    referenceRangeStatus: 'normal',
    notes: null,
    createdAt: DateTime.utc(2026, 10, 20, 9, 22, 13),
    updatedAt: DateTime.utc(2026, 10, 20, 9, 22, 13),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase localDb;
  late SupabaseClient client;
  late List<Map<String, dynamic>> serverRows;
  late List<Map<String, dynamic>> queueRows;
  late List<Map<String, dynamic>> recordRows;
  int? serverStatus;
  final requests = <http.Request>[];
  final providers = <DocumentStatusProvider>[];

  setUp(() {
    serverRows = [];
    queueRows = [];
    recordRows = [];
    serverStatus = null;
    requests.clear();
    providers.clear();

    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (serverStatus != null) {
          return http.Response(
            jsonEncode({'message': 'permission denied', 'code': '42501'}),
            serverStatus!,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }

        final table = request.url.path.split('/').last;
        final params = request.url.queryParameters;
        List<Map<String, dynamic>> rows;
        switch (table) {
          case 'documents':
            final uploaderId = params['uploader_id']?.replaceFirst('eq.', '');
            rows = serverRows
                .where((row) =>
                    uploaderId == null || row['uploader_id'] == uploaderId)
                .toList();
            break;
          case 'patient_queue':
            final patientId = params['patient_id']?.replaceFirst('eq.', '');
            rows = queueRows
                .where((row) =>
                    patientId == null || row['patient_id'] == patientId)
                .toList();
            break;
          case 'department_records':
            final patientId = params['patient_id']?.replaceFirst('eq.', '');
            rows = recordRows
                .where((row) =>
                    patientId == null || row['patient_id'] == patientId)
                .toList();
            break;
          default:
            rows = const [];
        }

        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-${rows.length}/${rows.length}',
          },
        );
      }),
    );
    SupabaseService.mockClient = client;
    localDb = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    for (final provider in providers) {
      provider.unsubscribe();
      provider.dispose();
    }
    await localDb.close();
    await client.dispose();
    SupabaseService.mockClient = null;
  });

  DocumentStatusProvider documentProvider({DocumentsRepository? repository}) {
    final provider = LocalDocumentProvider(
      localDb,
      documentsRepository: repository ?? DocumentsRepository(),
    );
    providers.add(provider);
    return provider;
  }

  group('Document cache honesty', () {
    test('a network failure leaves the provider stale, never live', () async {
      await localDb.cacheDocuments([cachedRow()]);
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.documents, hasLength(1));
      expect(provider.errorMessage, contains('Connection failed'));
    });

    test('a permission failure leaves the provider stale with the reason',
        () async {
      await localDb.cacheDocuments([cachedRow()]);
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const DatabaseFailure(
            'Access denied: You do not have permission to view or modify this data.',
          ),
        ),
      );

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.errorMessage, contains('Access denied'));
      expect(provider.documents, hasLength(1));
    });

    test('a denied server read (RLS) leaves the provider stale', () async {
      await localDb.cacheDocuments([cachedRow()]);
      serverStatus = 403;
      final provider = documentProvider();

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.errorMessage, contains('Access denied'));
      expect(provider.documents, hasLength(1));
    });

    test('a malformed server row leaves the provider stale', () async {
      await localDb.cacheDocuments([cachedRow()]);
      final malformed = serverRow();
      malformed['created_at'] = 'not-a-timestamp';
      serverRows = [malformed];
      final provider = documentProvider();

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.documents, hasLength(1));
      expect(provider.errorMessage, isNotNull);
    });

    test('a failed read with nothing cached is an error state, not an empty list',
        () async {
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.error);
      expect(provider.isStale, isFalse);
      expect(provider.documents, isEmpty);
      expect(provider.errorMessage, isNotNull);
    });

    test('a successful read clears the stale state', () async {
      await localDb.cacheDocuments([cachedRow()]);
      serverRows = [serverRow()];
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await provider.fetchDocumentsAndSubscribe('uploader-1');
      expect(provider.dataState, DocumentDataState.stale);

      final live = documentProvider();
      await live.fetchDocumentsAndSubscribe('uploader-1');

      expect(live.dataState, DocumentDataState.live);
      expect(live.isStale, isFalse);
      expect(live.errorMessage, isNull);
      expect(live.documents, hasLength(1));
    });

    test('a successful empty read clears the cache of that uploader only',
        () async {
      await localDb.cacheDocuments([
        cachedRow(id: 'doc-1', uploaderId: 'uploader-1'),
        cachedRow(id: 'doc-2', uploaderId: 'uploader-2'),
      ]);
      serverRows = [];
      final provider = documentProvider();

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(provider.dataState, DocumentDataState.empty);
      expect(provider.documents, isEmpty);
      expect(await localDb.getDocumentsForPatient('uploader-1'), isEmpty);
      expect(await localDb.getDocumentsForPatient('uploader-2'), hasLength(1));
    });

    test('a successful read drops the rows the server no longer returns',
        () async {
      await localDb.cacheDocuments([
        cachedRow(id: 'doc-1', uploaderId: 'uploader-1'),
        cachedRow(id: 'doc-gone', uploaderId: 'uploader-1'),
      ]);
      serverRows = [serverRow(id: 'doc-1')];
      final provider = documentProvider();

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      final cached = await localDb.getDocumentsForPatient('uploader-1');
      expect(cached.map((row) => row.id), ['doc-1']);
      expect(provider.documents, hasLength(1));
    });

    test('a snapshot replacement leaves the offline upload queue untouched',
        () async {
      await localDb.queueOfflineDocument(OfflineDocument(
        id: 'offline-1',
        patientId: 'patient-1',
        uploaderId: 'uploader-1',
        fileName: 'draft.pdf',
        localFilePath: '/tmp/draft.pdf',
        fileType: 'pdf',
        ocrText: null,
        extractedMetadata: null,
        createdAt: DateTime.utc(2026, 10, 20, 9, 22, 13),
        uploadState: 'draft',
      ));
      await localDb.cacheDocuments([
        cachedRow(id: 'doc-1', uploaderId: 'uploader-1'),
        cachedRow(id: 'doc-2', uploaderId: 'uploader-2'),
      ]);
      serverRows = [];
      final provider = documentProvider();

      await provider.fetchDocumentsAndSubscribe('uploader-1');

      expect(await localDb.getDocumentsForPatient('uploader-1'), isEmpty);
      expect(await localDb.getDocumentsForPatient('uploader-2'), hasLength(1));
      expect(await localDb.getQueuedDocuments('uploader-1'), hasLength(1));
    });
  });

  group('Document screen states', () {
    Future<void> pumpDocumentScreen(
      WidgetTester tester,
      DocumentStatusProvider provider,
    ) async {
      final auth = MockAuthProvider(client);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<DocumentStatusProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: DocumentStatusScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a stale cache is shown as stale, with a retry, never as live',
        (tester) async {
      await localDb.cacheDocuments([cachedRow()]);
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await pumpDocumentScreen(tester, provider);

      expect(find.text('Showing cached documents'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.text('LIVE REALTIME MONITOR ACTIVE'), findsNothing);
    });

    testWidgets('a failed read with nothing cached shows the error, not an empty list',
        (tester) async {
      final provider = documentProvider(
        repository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await pumpDocumentScreen(tester, provider);

      expect(find.text('Could not load your documents'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No Submissions Yet'), findsNothing);
      expect(find.text('LIVE REALTIME MONITOR ACTIVE'), findsNothing);
    });

    testWidgets('a successful empty read shows the empty state', (tester) async {
      await localDb.cacheDocuments([cachedRow()]);
      serverRows = [];
      final provider = documentProvider();

      await pumpDocumentScreen(tester, provider);

      expect(find.text('No Submissions Yet'), findsOneWidget);
      expect(find.text('Showing cached documents'), findsNothing);
      expect(find.text('LIVE REALTIME MONITOR ACTIVE'), findsOneWidget);
    });

    testWidgets('retrying a stale screen reads the server again', (tester) async {
      await localDb.cacheDocuments([cachedRow()]);
      serverStatus = 403;
      final provider = documentProvider();

      await pumpDocumentScreen(tester, provider);
      expect(find.text('Showing cached documents'), findsOneWidget);

      serverStatus = null;
      serverRows = [serverRow()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(provider.dataState, DocumentDataState.live);
      expect(find.text('Showing cached documents'), findsNothing);
      expect(find.text('LIVE REALTIME MONITOR ACTIVE'), findsOneWidget);
    });
  });

  group('Dashboard read honesty', () {
    test('a failed dashboard read leaves the provider stale with the reason',
        () async {
      await localDb.cacheDocuments([cachedRow()]);
      await localDb.cacheQueueEntries([cachedQueueRow()]);
      await localDb.cacheDepartmentRecords([cachedRecordRow()]);
      final provider = DashboardProvider(
        localDb,
        documentsRepository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await provider.fetchDashboardData('patient-1', 'uploader-1');

      expect(provider.dataState, DashboardDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.errorMessage, contains('Connection failed'));
      expect(provider.pendingDocumentsCount, 1);
    });

    test('a denied dashboard read leaves the provider stale with the reason',
        () async {
      await localDb.cacheDocuments([cachedRow()]);
      serverStatus = 403;
      final provider = DashboardProvider(localDb);

      await provider.fetchDashboardData('patient-1', 'uploader-1');

      expect(provider.dataState, DashboardDataState.stale);
      expect(provider.errorMessage, contains('Access denied'));
    });

    test('a failed dashboard read with nothing cached is an error state',
        () async {
      final provider = DashboardProvider(
        localDb,
        documentsRepository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await provider.fetchDashboardData('patient-1', 'uploader-1');

      expect(provider.dataState, DashboardDataState.error);
      expect(provider.isStale, isFalse);
      expect(provider.errorMessage, isNotNull);
    });

    test('a successful dashboard read clears the stale state', () async {
      await localDb.cacheDocuments([cachedRow()]);
      serverRows = [serverRow()];
      queueRows = [serverQueueRow()];
      recordRows = [serverRecordRow()];
      final stale = DashboardProvider(
        localDb,
        documentsRepository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );
      await stale.fetchDashboardData('patient-1', 'uploader-1');
      expect(stale.dataState, DashboardDataState.stale);

      final live = DashboardProvider(localDb);
      await live.fetchDashboardData('patient-1', 'uploader-1');

      expect(live.dataState, DashboardDataState.live);
      expect(live.isStale, isFalse);
      expect(live.errorMessage, isNull);
      expect(live.pendingDocumentsCount, 1);
      expect(live.activeQueueEntry, isNotNull);
      expect(live.latestRecord, isNotNull);
    });

    test('a successful empty dashboard read clears that uploader only',
        () async {
      await localDb.cacheDocuments([
        cachedRow(id: 'doc-1', uploaderId: 'uploader-1'),
        cachedRow(id: 'doc-2', uploaderId: 'uploader-2'),
      ]);
      serverRows = [];
      final provider = DashboardProvider(localDb);

      await provider.fetchDashboardData('patient-1', 'uploader-1');

      expect(provider.dataState, DashboardDataState.empty);
      expect(await localDb.getDocumentsForPatient('uploader-1'), isEmpty);
      expect(await localDb.getDocumentsForPatient('uploader-2'), hasLength(1));
    });
  });

  group('Dashboard screen states', () {
    Future<void> pumpDashboard(
      WidgetTester tester,
      DashboardProvider provider,
    ) async {
      final auth = MockAuthProvider(client);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<DashboardProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a stale dashboard shows the reason and a retry', (tester) async {
      await localDb.cacheDocuments([cachedRow()]);
      await localDb.cacheQueueEntries([cachedQueueRow()]);
      await localDb.cacheDepartmentRecords([cachedRecordRow()]);
      final provider = DashboardProvider(
        localDb,
        documentsRepository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await pumpDashboard(tester, provider);

      expect(find.text('Showing cached clinic data'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Status Summary'), findsOneWidget);
    });

    testWidgets('a failed dashboard read with nothing cached shows the error',
        (tester) async {
      final provider = DashboardProvider(
        localDb,
        documentsRepository: FailingDocumentsRepository(
          const NetworkFailure(
            'Connection failed: Please check your internet connection.',
          ),
        ),
      );

      await pumpDashboard(tester, provider);

      expect(find.text('Could not load your clinic data'), findsOneWidget);
      expect(find.textContaining('Connection failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The summary cards are not shown: the data is unknown, not empty.
      expect(find.text('Pending Submissions'), findsNothing);
      expect(find.text('Latest Lab Result'), findsNothing);
      expect(find.text('No clinical records found.'), findsNothing);
      expect(find.text('Not In Queue'), findsNothing);
    });
  });
}
