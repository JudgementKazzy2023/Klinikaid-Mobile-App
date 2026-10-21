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
import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/repositories/department_records_repository.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/records/domain/record_grouper.dart';
import 'package:klinikaid_mobile/features/records/presentation/providers/records_provider.dart';
import 'package:klinikaid_mobile/features/records/presentation/screens/records_screen.dart';
import 'package:klinikaid_mobile/features/records/presentation/widgets/grouped_record_detail_modal.dart';

/// A repository that fails the way a broken server does, so the provider's
/// fallbacks can be exercised without a network round trip.
class FailingRecordsRepository extends DepartmentRecordsRepository {
  FailingRecordsRepository(this.error);

  final Object error;

  @override
  Future<List<DepartmentRecord>> getRecordsForPatient(String patientId) async {
    throw error;
  }
}

class MockAuthProvider extends AuthProvider {
  MockAuthProvider(SupabaseClient client) : super(client: client);

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

/// A row of the `department_records` table, in the shape the server returns
/// it: one measurement per row, with the unit and the reference bounds as
/// columns of the row itself.
Map<String, dynamic> serverRow({
  String id = 'rec-1',
  String patientId = 'patient-1',
  String testName = 'Hemoglobin',
  String testValue = '14.2',
  String unit = 'g/dL',
  double referenceRangeMin = 13.5,
  double referenceRangeMax = 17.5,
  bool isFlagged = false,
  String createdAt = '2026-10-20T09:22:13Z',
}) {
  return {
    'id': id,
    'patient_id': patientId,
    'recorder_id': 'recorder-1',
    'department': 'laboratory',
    'test_type': 'CBC',
    'test_name': testName,
    'test_value': testValue,
    'unit': unit,
    'reference_range_min': referenceRangeMin,
    'reference_range_max': referenceRangeMax,
    'is_flagged': isFlagged,
    'notes': null,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

/// A cached row, as the local database stores it.
CachedDepartmentRecord cachedRow({
  String id = 'rec-1',
  String patientId = 'patient-1',
  String testName = 'Hemoglobin',
  String testValue = '14.2',
  String unit = 'g/dL',
  double referenceRangeMin = 13.5,
  double referenceRangeMax = 17.5,
  String referenceRangeStatus = 'normal',
  DateTime? createdAt,
}) {
  return CachedDepartmentRecord(
    id: id,
    patientId: patientId,
    recorderId: 'recorder-1',
    department: 'laboratory',
    testType: 'CBC',
    testResults: jsonEncode({
      'test_name': testName,
      'test_value': testValue,
      'unit': unit,
      'reference_range_min': referenceRangeMin,
      'reference_range_max': referenceRangeMax,
    }),
    referenceRangeStatus: referenceRangeStatus,
    notes: null,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 20, 9, 22, 13),
    updatedAt: createdAt ?? DateTime.utc(2026, 10, 20, 9, 22, 13),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase localDb;
  late SupabaseClient client;
  late List<Map<String, dynamic>> serverRows;
  int? serverStatus;
  Object? serverTransportError;
  final requests = <http.Request>[];

  setUp(() {
    serverRows = [];
    serverStatus = null;
    serverTransportError = null;
    requests.clear();

    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (serverTransportError != null) throw serverTransportError!;
        if (serverStatus != null) {
          return http.Response(
            jsonEncode({'message': 'permission denied', 'code': '42501'}),
            serverStatus!,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        final patientId = request.url.queryParameters['patient_id']?.replaceFirst('eq.', '');
        final rows = serverRows
            .where((row) => patientId == null || row['patient_id'] == patientId)
            .toList();
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
    await localDb.close();
    await client.dispose();
    SupabaseService.mockClient = null;
  });

  RecordsProvider providerWith({DepartmentRecordsRepository? repository}) {
    return RecordsProvider(
      localDb,
      recordsRepository: repository ?? DepartmentRecordsRepository(client: client),
    );
  }

  group('Records cache honesty', () {
    test('a network failure leaves the provider stale, never fresh', () async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      final provider = providerWith(
        repository: FailingRecordsRepository(
          const NetworkFailure('Connection failed: Please check your internet connection.'),
        ),
      );

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.records, hasLength(1));
      expect(provider.errorMessage, isNotNull);
    });

    test('a permission failure leaves the provider stale with the reason', () async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      final provider = providerWith(
        repository: FailingRecordsRepository(
          const DatabaseFailure(
            'Access denied: You do not have permission to view or modify this data.',
          ),
        ),
      );

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.errorMessage, contains('Access denied'));
      expect(provider.records, hasLength(1));
    });

    test('a denied server read (RLS) leaves the provider stale', () async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      serverStatus = 403;
      final provider = providerWith();

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.errorMessage, contains('Access denied'));
      expect(provider.records, hasLength(1));
    });

    test('a malformed server row leaves the provider stale', () async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      final malformed = serverRow();
      malformed['created_at'] = 'not-a-timestamp';
      serverRows = [malformed];
      final provider = providerWith();

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.stale);
      expect(provider.isStale, isTrue);
      expect(provider.records, hasLength(1));
      expect(provider.errorMessage, isNotNull);
    });

    test('a failed read with nothing cached is an error state, not an empty list', () async {
      final provider = providerWith(
        repository: FailingRecordsRepository(
          const NetworkFailure('Connection failed: Please check your internet connection.'),
        ),
      );

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.failed);
      expect(provider.isStale, isFalse);
      expect(provider.records, isEmpty);
      expect(provider.errorMessage, isNotNull);
    });

    test('a successful empty read clears the cache of that patient only', () async {
      await localDb.cacheDepartmentRecords([
        cachedRow(id: 'rec-1', patientId: 'patient-1'),
        cachedRow(id: 'rec-2', patientId: 'patient-2'),
      ]);
      serverRows = [];
      final provider = providerWith();

      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.fresh);
      expect(provider.records, isEmpty);
      expect(await localDb.getRecordsForPatient('patient-1'), isEmpty);
      expect(await localDb.getRecordsForPatient('patient-2'), hasLength(1));
    });

    test('a successful read replaces the rows the server no longer returns', () async {
      await localDb.cacheDepartmentRecords([
        cachedRow(id: 'rec-1', patientId: 'patient-1'),
        cachedRow(id: 'rec-gone', patientId: 'patient-1'),
      ]);
      serverRows = [serverRow(id: 'rec-1')];
      final provider = providerWith();

      await provider.fetchRecords('patient-1');

      final cached = await localDb.getRecordsForPatient('patient-1');
      expect(cached.map((row) => row.id), ['rec-1']);
      expect(provider.records, hasLength(1));
    });
  });

  group('Records screen states', () {
    Future<void> pumpRecordsScreen(WidgetTester tester, RecordsProvider provider) async {
      final auth = MockAuthProvider(client);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<RecordsProvider>.value(value: provider),
          ],
          child: const MaterialApp(home: RecordsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a stale cache is shown as stale, with a retry, never as online',
        (tester) async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      final provider = providerWith(
        repository: FailingRecordsRepository(
          const NetworkFailure('Connection failed: Please check your internet connection.'),
        ),
      );

      await pumpRecordsScreen(tester, provider);

      expect(find.text('Showing cached results'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
    });

    testWidgets('a failed read with nothing cached shows the error, not an empty list',
        (tester) async {
      final provider = providerWith(
        repository: FailingRecordsRepository(
          const NetworkFailure('Connection failed: Please check your internet connection.'),
        ),
      );

      await pumpRecordsScreen(tester, provider);

      expect(find.text('Could not load your records'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No Records Found'), findsNothing);
    });

    testWidgets('a successful empty read shows the empty state', (tester) async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      serverRows = [];
      final provider = providerWith();

      await pumpRecordsScreen(tester, provider);

      expect(find.text('No Records Found'), findsOneWidget);
      expect(find.text('Showing cached results'), findsNothing);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('retrying a stale screen reads the server again', (tester) async {
      await localDb.cacheDepartmentRecords([cachedRow()]);
      serverStatus = 403;
      final provider = providerWith();

      await pumpRecordsScreen(tester, provider);
      expect(find.text('Showing cached results'), findsOneWidget);

      serverStatus = null;
      serverRows = [serverRow()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(provider.dataState, RecordsDataState.fresh);
      expect(find.text('Showing cached results'), findsNothing);
      expect(find.text('Online'), findsOneWidget);
    });
  });

  group('Reference ranges survive parse, cache and display', () {
    test('a server row keeps its unit, bounds and flag', () {
      final record = DepartmentRecord.fromJson(
        serverRow(isFlagged: true, testValue: '19.1'),
      );

      expect(record.unit, 'g/dL');
      expect(record.referenceRangeMin, 13.5);
      expect(record.referenceRangeMax, 17.5);
      expect(record.isFlagged, isTrue);
      expect(record.referenceRangeStatus, ReferenceRangeStatus.flagged);
    });

    test('the unit, bounds and flag survive a cache round trip', () async {
      serverRows = [serverRow(isFlagged: true, testValue: '19.1')];
      final provider = providerWith();

      await provider.fetchRecords('patient-1');

      // The record read back from the cache is the one a later failed read
      // would show, so it has to carry the same facts.
      serverStatus = 403;
      await provider.fetchRecords('patient-1');

      expect(provider.dataState, RecordsDataState.stale);
      final record = provider.records.single;
      expect(record.unit, 'g/dL');
      expect(record.referenceRangeMin, 13.5);
      expect(record.referenceRangeMax, 17.5);
      expect(record.isFlagged, isTrue);
    });

    testWidgets('the detail view shows the unit and the reference range',
        (tester) async {
      final record = DepartmentRecord.fromJson(
        serverRow(isFlagged: true, testValue: '19.1'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupedRecordDetailModal(
              groupedRecord: groupRecords([record]).single,
              scrollController: ScrollController(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('REFERENCE RANGE'), findsOneWidget);
      expect(find.text('13.5 - 17.5 g/dL'), findsOneWidget);
      expect(find.text('FLAGGED'), findsOneWidget);
    });

    testWidgets('a grouped panel shows the unit and the reference range of each parameter',
        (tester) async {
      final records = [
        DepartmentRecord.fromJson(serverRow(
          id: 'rec-1',
          testName: 'Hemoglobin',
          testValue: '14.2',
          isFlagged: false,
        )),
        DepartmentRecord.fromJson(serverRow(
          id: 'rec-2',
          testName: 'Hematocrit',
          testValue: '19.1',
          isFlagged: true,
          createdAt: '2026-10-20T09:24:00Z',
        )),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupedRecordDetailModal(
              groupedRecord: groupRecords(records).single,
              scrollController: ScrollController(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('14.2 g/dL'), findsOneWidget);
      expect(find.text('19.1 g/dL'), findsOneWidget);
      expect(find.text('Reference range: 13.5 - 17.5 g/dL'), findsNWidgets(2));
      expect(find.text('FLAGGED'), findsOneWidget);
    });
  });
}
