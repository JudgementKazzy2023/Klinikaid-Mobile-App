import 'dart:convert';
import 'dart:io';

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
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';

/// Active-only queue summary for the patient dashboard.
///
/// The issue's checkbox ("Agree active-only versus historical queue summary
/// semantics") is answered by web as active-only, so this file pins the same
/// rule on mobile. The web reference is
/// `src/app/(dashboard)/patient/dashboard/page.tsx`:
///
/// * lines 62-70: `patient_queue` filtered with
///   `eq("patient_id", ...).in("status", ["waiting", "in_progress"])`,
///   `order("created_at", { ascending: false })`, `limit(1)` -- the current
///   queue is the newest row whose status is exactly `waiting` or
///   `in_progress`, with no fallback to a finished visit;
/// * line 97: `activeQueue = data?.[0] || null`;
/// * lines 106-108 / 154-160: a read error surfaces as an error, never as
///   "no queue";
/// * line 188: with no active row the tile reads `Not In Queue`.
///
/// Only the live WebSocket is suppressed. Repositories, HTTP parsing, the
/// cache and the production read path stay real: no network, no production
/// writes.
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

/// A `patient_queue` row in the shape the server returns it. Rows are listed
/// newest-first, the order the repository asks for.
Map<String, dynamic> queueRow({
  int id = 1,
  String status = 'waiting',
  String createdAt = '2026-10-20T10:00:00Z',
}) {
  return {
    'id': id,
    'patient_id': 'patient-1',
    'status': status,
    'department': 'laboratory',
    'triage_notes': null,
    'priority_level': 'routine',
    'estimated_wait_minutes': 15,
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

/// A cached queue row, as the local database stores it.
CachedPatientQueue cachedQueueRow({
  int id = 1,
  String status = 'waiting',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 10, 20, 10);
  return CachedPatientQueue(
    id: id,
    patientId: 'patient-1',
    status: status,
    department: 'laboratory',
    priorityLevel: 'routine',
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase localDb;
  late SupabaseClient client;
  late List<Map<String, dynamic>> queueRows;
  int? serverStatus;
  bool offline = false;

  setUp(() {
    queueRows = [];
    serverStatus = null;
    offline = false;

    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (offline) throw const SocketException('offline fixture');
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
          case 'patient_queue':
            final patientId = params['patient_id']?.replaceFirst('eq.', '');
            rows = queueRows
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
    await localDb.close();
    await client.dispose();
    SupabaseService.mockClient = null;
  });

  DashboardProvider provider() => DashboardProvider(localDb);

  Future<void> pumpDashboard(
    WidgetTester tester,
    DashboardProvider dashboard,
  ) async {
    // The dashboard is a long scroll view; give it room so every summary card
    // is actually built.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = MockAuthProvider(client);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<DashboardProvider>.value(value: dashboard),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Active-only queue summary', () {
    test('a waiting entry older than a newer completed one is the current queue',
        () async {
      queueRows = [
        queueRow(id: 1, status: 'completed', createdAt: '2026-10-20T10:00:00Z'),
        queueRow(id: 2, status: 'waiting', createdAt: '2026-10-20T09:00:00Z'),
      ];

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(dashboard.errorMessage, isNull);
      expect(dashboard.dataState, DashboardDataState.live);
      expect(dashboard.activeQueueEntry, isNotNull);
      expect(dashboard.activeQueueEntry!.id, 2);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.waiting);
      dashboard.dispose();
    });

    test('an in_progress entry is the current queue', () async {
      queueRows = [queueRow(id: 5, status: 'in_progress')];

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(dashboard.activeQueueEntry, isNotNull);
      expect(dashboard.activeQueueEntry!.id, 5);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.inProgress);
      dashboard.dispose();
    });

    test('completed and cancelled history alone leaves no current queue',
        () async {
      queueRows = [
        queueRow(id: 1, status: 'completed', createdAt: '2026-10-20T10:00:00Z'),
        queueRow(id: 2, status: 'cancelled', createdAt: '2026-10-20T09:00:00Z'),
      ];

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      // The rows are real data, so the read is live -- it is not an error,
      // not a loading state and not a stale one.
      expect(dashboard.dataState, DashboardDataState.live);
      expect(dashboard.isStale, isFalse);
      expect(dashboard.errorMessage, isNull);
      expect(dashboard.activeQueueEntry, isNull);
      dashboard.dispose();
    });

    test('an unknown status never counts as a current queue entry', () async {
      queueRows = [
        queueRow(id: 1, status: 'no_show', createdAt: '2026-10-20T10:00:00Z'),
        queueRow(id: 2, status: 'completed', createdAt: '2026-10-20T09:00:00Z'),
      ];

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(dashboard.dataState, DashboardDataState.live);
      expect(dashboard.activeQueueEntry, isNull);

      // The unknown status survives the cache write as itself instead of being
      // canonicalised into `waiting`, so the offline read agrees.
      expect(
        (await localDb.getQueueForPatient('patient-1'))
            .map((row) => row.status),
        ['no_show', 'completed'],
      );

      offline = true;
      final offlineDashboard = provider();
      await offlineDashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(offlineDashboard.isOffline, isTrue);
      expect(offlineDashboard.activeQueueEntry, isNull);
      dashboard.dispose();
      offlineDashboard.dispose();
    });

    test('the newest of two active entries wins', () async {
      // Deliberately listed oldest first: `created_at` decides, the same
      // ordering the server applies before web takes `limit(1)`.
      queueRows = [
        queueRow(id: 1, status: 'waiting', createdAt: '2026-10-20T09:00:00Z'),
        queueRow(
          id: 2,
          status: 'in_progress',
          createdAt: '2026-10-20T10:00:00Z',
        ),
      ];

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(dashboard.activeQueueEntry, isNotNull);
      expect(dashboard.activeQueueEntry!.id, 2);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.inProgress);
      dashboard.dispose();
    });

    test('the offline cache applies the same active-only rule', () async {
      await localDb.cacheQueueEntries([
        cachedQueueRow(
          id: 1,
          status: 'completed',
          createdAt: DateTime.utc(2026, 10, 20, 10),
        ),
        cachedQueueRow(
          id: 2,
          status: 'waiting',
          createdAt: DateTime.utc(2026, 10, 20, 9),
        ),
      ]);
      offline = true;

      final dashboard = provider();
      await dashboard.fetchDashboardData('patient-1', 'uploader-1');

      expect(dashboard.isOffline, isTrue);
      expect(dashboard.isStale, isTrue);
      expect(dashboard.activeQueueEntry, isNotNull);
      expect(dashboard.activeQueueEntry!.id, 2);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.waiting);
      dashboard.dispose();

      // Cache holding nothing but finished visits: still no current queue.
      await localDb.replaceQueueForPatient('patient-1', [
        cachedQueueRow(
          id: 3,
          status: 'cancelled',
          createdAt: DateTime.utc(2026, 10, 20, 8),
        ),
      ]);
      final offlineOnly = provider();
      await offlineOnly.fetchDashboardData('patient-1', 'uploader-1');

      expect(offlineOnly.isOffline, isTrue);
      expect(offlineOnly.activeQueueEntry, isNull);
      offlineOnly.dispose();
    });

    testWidgets('completed history reads as Not In Queue on the dashboard',
        (tester) async {
      queueRows = [
        queueRow(id: 1, status: 'completed', createdAt: '2026-10-20T10:00:00Z'),
        queueRow(id: 2, status: 'cancelled', createdAt: '2026-10-20T09:00:00Z'),
      ];
      final dashboard = provider();

      await pumpDashboard(tester, dashboard);

      expect(find.text('Triage Queue Status'), findsOneWidget);
      expect(find.text('Not In Queue'), findsOneWidget);
      // History is not shown as the current queue, and the empty tile is not
      // confused with loading, an error or a stale read.
      expect(find.text('Waiting in Queue'), findsNothing);
      expect(find.text('Now Being Called'), findsNothing);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Cancelled'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Could not load your clinic data'), findsNothing);
      expect(find.text('Showing cached clinic data'), findsNothing);
      expect(tester.takeException(), isNull);
      dashboard.dispose();
    });

    testWidgets('an unknown status also reads as Not In Queue',
        (tester) async {
      queueRows = [queueRow(id: 1, status: 'no_show')];
      final dashboard = provider();

      await pumpDashboard(tester, dashboard);

      expect(find.text('Not In Queue'), findsOneWidget);
      expect(find.text('Waiting in Queue'), findsNothing);
      expect(find.text('Now Being Called'), findsNothing);
      dashboard.dispose();
    });

    testWidgets('an active entry still shows its queue state', (tester) async {
      queueRows = [
        queueRow(id: 1, status: 'completed', createdAt: '2026-10-20T11:00:00Z'),
        queueRow(id: 2, status: 'in_progress', createdAt: '2026-10-20T10:00:00Z'),
      ];
      final dashboard = provider();

      await pumpDashboard(tester, dashboard);

      expect(find.text('Now Being Called'), findsOneWidget);
      expect(find.text('Not In Queue'), findsNothing);
      dashboard.dispose();
    });
  });

  group('Read failures are never reported as queue membership', () {
    testWidgets('a failed read with nothing cached is an error, not Not In Queue',
        (tester) async {
      serverStatus = 403;
      final dashboard = provider();

      await pumpDashboard(tester, dashboard);

      expect(find.text('Could not load your clinic data'), findsOneWidget);
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // The summary cards are withheld: the data is unknown, not empty.
      expect(find.text('Not In Queue'), findsNothing);
      expect(find.text('Triage Queue Status'), findsNothing);
      expect(dashboard.dataState, DashboardDataState.error);
      expect(dashboard.activeQueueEntry, isNull);
      dashboard.dispose();
    });

    testWidgets('a failed read with cached history is shown as stale',
        (tester) async {
      await localDb.cacheQueueEntries([
        cachedQueueRow(
          id: 1,
          status: 'completed',
          createdAt: DateTime.utc(2026, 10, 20, 10),
        ),
      ]);
      serverStatus = 403;
      final dashboard = provider();

      await pumpDashboard(tester, dashboard);

      // The failure itself is what the patient is told about: the copy below
      // is labelled as cached data with the reason it could not be refreshed.
      expect(dashboard.dataState, DashboardDataState.stale);
      expect(dashboard.isStale, isTrue);
      expect(find.text('Showing cached clinic data'), findsOneWidget);
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(dashboard.activeQueueEntry, isNull);
      expect(find.text('Waiting in Queue'), findsNothing);
      expect(find.text('Now Being Called'), findsNothing);
      dashboard.dispose();
    });
  });
}
