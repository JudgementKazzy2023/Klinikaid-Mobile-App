import 'dart:async';
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
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:klinikaid_mobile/features/queue/presentation/providers/queue_provider.dart';
import 'package:klinikaid_mobile/features/queue/presentation/screens/queue_screen.dart';

// Only the live WebSocket is suppressed; repositories, HTTP parsing, cache and
// the production realtime handler remain real. No network or production writes.
class LocalQueueProvider extends QueueProvider {
  LocalQueueProvider(super.db);
  @override
  void subscribeToQueueUpdates(String patientId) {}
}

class ScreenAuth extends ChangeNotifier implements AuthProvider {
  // Screens start provider fetches from post-frame callbacks when a patient is
  // present; those fetches cannot complete inside the fake widget-test zone and
  // would deadlock the provider's serialized refresh chain. Expose a patient
  // only while DashboardScreen (which blocks on it) is mounted; user stays null
  // so no screen triggers an in-zone fetch.
  Patient? current;

  @override
  Patient? get patient => current;
  @override
  User? get user => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> row(int id, String patient, [String status = 'waiting']) =>
    {
      'id': id,
      'patient_id': patient,
      'status': status,
      'department': 'laboratory',
      'priority_level': 'routine',
      'created_at': '2026-10-19T00:00:00Z',
      'updated_at': '2026-10-20T00:00:00Z',
    };

CachedPatientQueue cached(
  int id,
  String patient, [
  String status = 'waiting',
]) => CachedPatientQueue(
  id: id,
  patientId: patient,
  status: status,
  department: 'laboratory',
  priorityLevel: 'routine',
  createdAt: DateTime.utc(2026, 10, 19),
  updatedAt: DateTime.utc(2026, 10, 20),
);

Patient fixturePatient() => Patient.fromJson(const {
  'id': 'A',
  'first_name': 'Queue',
  'last_name': 'Patient',
  'date_of_birth': '2000-01-01',
  'gender': 'other',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

PostgresChangePayload event(
  PostgresChangeEvent type, {
  Map<String, dynamic> old = const {},
  Map<String, dynamic> next = const {},
}) => PostgresChangePayload(
  schema: 'public',
  table: 'patient_queue',
  commitTimestamp: DateTime.utc(2026, 10, 20),
  eventType: type,
  newRecord: next,
  oldRecord: old,
  errors: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase db;
  late SupabaseClient client;
  late LocalQueueProvider queue;
  late DashboardProvider dashboard;
  late List<Map<String, dynamic>> remote;
  late List<Uri> requests;
  bool offline = false;
  bool denied = false;
  Completer<void>? block;
  Completer<void>? queueRequestStarted;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    remote = [];
    requests = [];
    offline = false;
    denied = false;
    block = null;
    queueRequestStarted = null;
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        requests.add(request.url);
        if (offline) throw const SocketException('offline fixture');
        if (denied) {
          return http.Response('{"code":"42501","message":"denied"}', 403, request: request);
        }
        final isQueue = request.url.path.endsWith('/patient_queue');
        final snapshot = isQueue
            ? remote
                  .where(
                    (r) =>
                        'eq.${r['patient_id']}' ==
                        request.url.queryParameters['patient_id'],
                  )
                  .toList()
            : [];
        if (isQueue && block != null) {
          queueRequestStarted?.complete();
          await block!.future;
        }
        return http.Response(
          jsonEncode(snapshot),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    SupabaseService.mockClient = client;
    queue = LocalQueueProvider(db);
    dashboard = DashboardProvider(db);
  });

  tearDown(() async {
    queue.dispose();
    dashboard.dispose();
    await db.close();
    await client.dispose();
    SupabaseService.mockClient = null;
  });

  for (final status in QueueStatus.values) {
    test(
      'queue ${status.name}: remote -> canonical cache -> fresh offline provider',
      () async {
        remote = [row(1, 'A', status.toJsonValue())];
        await queue.fetchQueueAndSubscribe('A');
        expect(queue.errorMessage, isNull);
      expect(queue.queueEntries.single.status, status);
        expect(
          (await db.getQueueForPatient('A')).single.status,
          status.toJsonValue(),
        );
        offline = true;
        final fresh = LocalQueueProvider(db);
        await fresh.fetchQueueAndSubscribe('A');
        expect(fresh.isOffline, isTrue);
        expect(fresh.queueEntries.single.status, status);
        fresh.dispose();
      },
    );
    test(
      'dashboard ${status.name}: remote -> canonical cache -> fresh offline provider',
      () async {
        remote = [row(1, 'A', status.toJsonValue())];
        await dashboard.fetchDashboardData('A', 'uploader-A');
        expect(dashboard.errorMessage, isNull);
      expect(dashboard.activeQueueEntry!.status, status);
        expect(
          (await db.getQueueForPatient('A')).single.status,
          status.toJsonValue(),
        );
        offline = true;
        final fresh = DashboardProvider(db);
        await fresh.fetchDashboardData('A', 'uploader-A');
        expect(fresh.isOffline, isTrue);
        expect(fresh.activeQueueEntry!.status, status);
        fresh.dispose();
      },
    );
  }

  test(
    'legacy inProgress parses and stays active ahead of completed history',
    () async {
      expect(QueueStatus.fromString('inProgress'), QueueStatus.inProgress);
      await db.cacheQueueEntries([
        cached(1, 'A', 'completed'),
        cached(2, 'A', 'inProgress'),
      ]);
      offline = true;
      await queue.fetchQueueAndSubscribe('A');
      await dashboard.fetchDashboardData('A', 'uploader-A');
      expect(queue.activeEntry!.status, QueueStatus.inProgress);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.inProgress);
    },
  );

  for (final source in ['queue', 'dashboard']) {
    test(
      '$source reconciles subset then empty only for A, preserves B offline',
      () async {
        await db.cacheQueueEntries([
          cached(1, 'A'),
          cached(2, 'A'),
          cached(3, 'B'),
        ]);
        Future<void> refresh() => source == 'queue'
            ? queue.fetchQueueAndSubscribe('A')
            : dashboard.fetchDashboardData('A', 'uploader-A');
        remote = [row(2, 'A', 'in_progress'), row(3, 'B')];
        await refresh();
        expect((await db.getQueueForPatient('A')).map((r) => r.id), [2]);
        remote = [row(3, 'B')];
        await refresh();
        offline = true;
        await refresh();
        expect(await db.getQueueForPatient('A'), isEmpty);
        expect((await db.getQueueForPatient('B')).single.id, 3);
        if (source == 'queue') {
          expect(queue.queueEntries, isEmpty);
        } else {
          expect(dashboard.activeQueueEntry, isNull);
        }
        expect(
          requests
              .where((u) => u.path.endsWith('/patient_queue'))
              .every((u) => u.queryParameters['patient_id'] == 'eq.A'),
          isTrue,
        );
      },
    );
    test('$source failed remote read never replaces cached snapshot', () async {
      await db.cacheQueueEntries([cached(1, 'A'), cached(3, 'B')]);
      denied = true;
      if (source == 'queue') {
        await queue.fetchQueueAndSubscribe('A');
        expect(queue.errorMessage, isNotNull);
        expect(queue.queueEntries.single.id, 1);
      } else {
        await dashboard.fetchDashboardData('A', 'uploader-A');
        expect(dashboard.errorMessage, isNotNull);
        expect(dashboard.activeQueueEntry!.id, 1);
      }
      expect((await db.getQueueForPatient('A')).single.id, 1);
      expect((await db.getQueueForPatient('B')).single.id, 3);
    });
  }

  test('snapshot rejects cross-patient input without deleting anything; upsert API stays incremental', () async {
    await db.cacheQueueEntries([
      cached(1, 'A'),
      cached(2, 'A'),
      cached(3, 'B'),
    ]);
    await expectLater(
      db.replaceQueueForPatient('A', [cached(4, 'B')]),
      throwsArgumentError,
    );
    await db.cacheQueueEntries([cached(1, 'A', 'in_progress')]);
    expect((await db.getQueueForPatient('A')).length, 2);
    expect((await db.getQueueForPatient('B')).single.id, 3);
  });

  for (final old in [
    <String, dynamic>{'id': 1, 'patient_id': 'A'},
    {'id': 1},
    <String, dynamic>{},
  ]) {
    test(
      'DELETE oldRecord=$old empty newRecord removes visible/cache and stays absent offline',
      () async {
        remote = [row(1, 'A'), row(3, 'B')];
        await db.cacheQueueEntries([cached(3, 'B')]);
        await queue.fetchQueueAndSubscribe('A');
        remote = [row(3, 'B')];
        await queue.handleQueueChange(
          'A',
          event(PostgresChangeEvent.delete, old: old),
        );
        expect(queue.queueEntries, isEmpty);
        expect(await db.getQueueForPatient('A'), isEmpty);
        expect((await db.getQueueForPatient('B')).single.id, 3);
        offline = true;
        await queue.fetchQueueAndSubscribe('A');
        expect(queue.queueEntries, isEmpty);
        await dashboard.fetchDashboardData('A', 'uploader-A');
        expect(dashboard.activeQueueEntry, isNull);
      },
    );
  }

  test('duplicate INSERT, UPDATE and delayed stale payload never duplicate or resurrect', () async {
    await queue.fetchQueueAndSubscribe('A');
    remote = [row(1, 'A')];
    final insert = event(PostgresChangeEvent.insert, next: row(1, 'A'));
    await queue.handleQueueChange('A', insert);
    await queue.handleQueueChange('A', insert);
    remote = [row(1, 'A', 'in_progress')];
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.update, next: row(1, 'A')),
    );
    expect(queue.queueEntries.single.status, QueueStatus.inProgress);
    expect((await db.getQueueForPatient('A')).single.status, 'in_progress');
    remote = [];
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.delete, old: {'id': 1}),
    );
    await queue.handleQueueChange('A', insert);
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.update, next: row(1, 'A')),
    );
    expect(queue.queueEntries, isEmpty);
    expect(await db.getQueueForPatient('A'), isEmpty);
  });

  test('unknown DELETE failure preserves cache and unrelated scoped events are ignored', () async {
    remote = [row(1, 'A')];
    await queue.fetchQueueAndSubscribe('A');
    final count = requests.length;
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.delete, old: {'id': 3, 'patient_id': 'B'}),
    );
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.insert, next: row(3, 'B')),
    );
    expect(requests.length, count);
    offline = true;
    await queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.delete, old: {'id': 99}),
    );
    expect(queue.queueEntries.single.id, 1);
    expect((await db.getQueueForPatient('A')).single.id, 1);
  });

  test('overlapping events serialize snapshots; old completion cannot restore a deletion', () async {
    remote = [row(1, 'A')];
    await queue.fetchQueueAndSubscribe('A');
    block = Completer<void>();
    final first = queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.update, next: row(1, 'A')),
    );
    await Future<void>.delayed(Duration.zero);
    remote = [];
    final second = queue.handleQueueChange(
      'A',
      event(PostgresChangeEvent.delete, old: {'id': 1}),
    );
    block!.complete();
    block = null;
    await Future.wait([first, second]);
    expect(queue.queueEntries, isEmpty);
    expect(await db.getQueueForPatient('A'), isEmpty);
  });

  test('account switch drops a delayed A snapshot and old A events', () async {
    remote = [row(1, 'A')];
    await queue.fetchQueueAndSubscribe('A');
    final pending = Completer<void>();
    block = pending;
    queueRequestStarted = Completer<void>();
    remote = [];
    final aRefresh = queue.fetchQueueAndSubscribe('A');
    await queueRequestStarted!.future;
    remote = [row(3, 'B', 'in_progress')];
    final bRefresh = queue.fetchQueueAndSubscribe('B');
    expect(queue.queueEntries, isEmpty);
    block = null;
    pending.complete();
    await Future.wait([aRefresh, bRefresh]);
    expect(queue.queueEntries.single.patientId, 'B');
    expect(queue.queueEntries.single.id, 3);
    expect((await db.getQueueForPatient('A')).single.id, 1);
    expect((await db.getQueueForPatient('B')).single.id, 3);
    final count = requests.length;
    await queue.handleQueueChange(
      'A', event(PostgresChangeEvent.update, next: row(1, 'A')),
    );
    expect(requests.length, count);
    expect(queue.queueEntries.single.id, 3);
  });

  testWidgets(
    'queue and dashboard show offline Now Being Called; deletion removes queue card',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      remote = [row(1, 'A', 'in_progress')];
      await tester.runAsync(() => queue.fetchQueueAndSubscribe('A'));
      await tester.runAsync(
        () => dashboard.fetchDashboardData('A', 'uploader-A'),
      );
      offline = true;
      await tester.runAsync(() => queue.fetchQueueAndSubscribe('A'));
      await tester.runAsync(
        () => dashboard.fetchDashboardData('A', 'uploader-A'),
      );
      final auth = ScreenAuth();
      Widget screen(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<QueueProvider>.value(value: queue),
          ChangeNotifierProvider<DashboardProvider>.value(value: dashboard),
          Provider<SessionActivityService>(
            create: (_) => SessionActivityService(),
          ),
        ],
        child: MaterialApp(home: child),
      );
      await tester.pumpWidget(screen(const QueueScreen()));
      await tester.pumpAndSettle();
      expect(find.text('NOW CALLING'), findsOneWidget);
      expect(find.text('OFFLINE MODE - Caching active'), findsOneWidget);
      auth.current = fixturePatient();
      await tester.pumpWidget(screen(const DashboardScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Now Being Called'), findsOneWidget);
      expect(find.text('Offline Mode'), findsOneWidget);
      offline = false;
      remote = [];
      await tester.runAsync(
        () => queue.handleQueueChange(
          'A',
          event(PostgresChangeEvent.delete, old: {'id': 1}),
        ),
      );
      auth.current = null;
      await tester.pumpWidget(screen(const QueueScreen()));
      await tester.pumpAndSettle();
      expect(find.text('NOW CALLING'), findsNothing);
      expect(find.text('Queue History'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
}
