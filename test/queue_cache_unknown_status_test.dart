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

/// The queue snapshot's status column stores the RAW status the server
/// spelled, in every writer. Both the dashboard and the queue screen cache
/// paths write `PatientQueue.rawStatus`, and every reader keeps it verbatim,
/// so a status this client does not recognise can never canonicalise into
/// `waiting` and read back offline as an active queue entry.
///
/// Only the live WebSocket is suppressed; repositories, HTTP parsing, the
/// cache and the production read paths stay real. No network, no production
/// writes.
class LocalQueueProvider extends QueueProvider {
  LocalQueueProvider(super.db);
  @override
  void subscribeToQueueUpdates(String patientId) {}
}

class ScreenAuth extends ChangeNotifier implements AuthProvider {
  // Screens start provider fetches from post-frame callbacks when a patient is
  // present; those fetches cannot complete inside the fake widget-test zone
  // and would deadlock the provider's serialized refresh chain. Expose a
  // patient only while DashboardScreen (which blocks on it) is mounted; user
  // stays null so no screen triggers an in-zone fetch.
  Patient? current;

  @override
  Patient? get patient => current;
  @override
  User? get user => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A `patient_queue` row in the shape the server returns it, newest first.
Map<String, dynamic> row(
  int id,
  String status, {
  String createdAt = '2026-10-20T10:00:00Z',
}) => {
  'id': id,
  'patient_id': 'A',
  'status': status,
  'department': 'lab',
  'priority_level': 'routine',
  'created_at': createdAt,
  'updated_at': createdAt,
};

Patient fixturePatient() => Patient.fromJson(const {
  'id': 'A',
  'first_name': 'Queue',
  'last_name': 'Patient',
  'date_of_birth': '2000-01-01',
  'gender': 'other',
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase db;
  late SupabaseClient client;
  late List<Map<String, dynamic>> remote;
  bool offline = false;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    remote = [];
    offline = false;
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (offline) throw const SocketException('offline fixture');
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
        return http.Response(
          jsonEncode(snapshot),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    SupabaseService.mockClient = client;
  });

  tearDown(() async {
    await db.close();
    await client.dispose();
    SupabaseService.mockClient = null;
  });

  test(
    'an unknown status cached by the queue provider never reads back as waiting',
    () async {
      remote = [row(1, 'transferred')];

      final queue = LocalQueueProvider(db);
      await queue.fetchQueueAndSubscribe('A');
      expect(queue.errorMessage, isNull);
      expect(queue.queueEntries.single.rawStatus, 'transferred');

      // The queue provider's cache write stores the server's spelling instead
      // of canonicalising the unknown value into `waiting`.
      expect(
        (await db.getQueueForPatient('A')).single.status,
        'transferred',
      );

      // Offline reload through the queue provider: not an active entry.
      offline = true;
      final freshQueue = LocalQueueProvider(db);
      await freshQueue.fetchQueueAndSubscribe('A');
      expect(freshQueue.isOffline, isTrue);
      expect(freshQueue.queueEntries.single.rawStatus, 'transferred');
      expect(
        isActiveQueueStatus(freshQueue.queueEntries.single.rawStatus),
        isFalse,
      );

      // The dashboard reading the same snapshot agrees: no current queue.
      final dashboard = DashboardProvider(db);
      await dashboard.fetchDashboardData('A', 'uploader-A');
      expect(dashboard.isOffline, isTrue);
      expect(dashboard.activeQueueEntry, isNull);

      freshQueue.dispose();
      queue.dispose();
      dashboard.dispose();
    },
  );

  testWidgets(
    'after the queue provider caches an unknown status, offline screens never show it as waiting',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      remote = [row(1, 'transferred')];
      final queue = LocalQueueProvider(db);
      final dashboard = DashboardProvider(db);
      await tester.runAsync(() => queue.fetchQueueAndSubscribe('A'));
      await tester.runAsync(() => dashboard.fetchDashboardData('A', 'uploader-A'));
      offline = true;
      await tester.runAsync(() => queue.fetchQueueAndSubscribe('A'));
      await tester.runAsync(() => dashboard.fetchDashboardData('A', 'uploader-A'));

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

      // Queue screen: the entry appears as history spelled exactly as the
      // server spelled it, never as the active queue.
      await tester.pumpWidget(screen(const QueueScreen()));
      await tester.pumpAndSettle();
      expect(find.text('OFFLINE MODE - Caching active'), findsOneWidget);
      expect(find.text('TRANSFERRED'), findsOneWidget);
      expect(find.text('IN QUEUE'), findsNothing);
      expect(find.text('NOW CALLING'), findsNothing);
      expect(find.text('Waiting in Queue'), findsNothing);
      expect(find.text('Now Being Called'), findsNothing);
      expect(tester.takeException(), isNull);

      // Dashboard: the same snapshot reads as Not In Queue.
      auth.current = fixturePatient();
      await tester.pumpWidget(screen(const DashboardScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Not In Queue'), findsOneWidget);
      expect(find.text('Waiting in Queue'), findsNothing);
      expect(find.text('Now Being Called'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      queue.dispose();
      dashboard.dispose();
    },
  );

  test(
    'known statuses round-trip through the queue provider cache unchanged',
    () async {
      remote = [
        row(1, 'waiting', createdAt: '2026-10-20T10:00:00Z'),
        row(2, 'in_progress', createdAt: '2026-10-20T09:00:00Z'),
        row(3, 'completed', createdAt: '2026-10-20T08:00:00Z'),
        row(4, 'cancelled', createdAt: '2026-10-20T07:00:00Z'),
      ];

      final queue = LocalQueueProvider(db);
      await queue.fetchQueueAndSubscribe('A');
      expect(queue.errorMessage, isNull);

      // Nothing is rewritten on the way in: the cache stores exactly what the
      // server spelled for every known status.
      expect(
        (await db.getQueueForPatient('A')).map((r) => r.status).toList(),
        ['waiting', 'in_progress', 'completed', 'cancelled'],
      );

      // Nothing changes on the way back out, offline.
      offline = true;
      final freshQueue = LocalQueueProvider(db);
      await freshQueue.fetchQueueAndSubscribe('A');
      expect(freshQueue.isOffline, isTrue);
      expect(
        freshQueue.queueEntries
            .map((e) => (e.id, e.status, e.rawStatus))
            .toList(),
        [
          (1, QueueStatus.waiting, 'waiting'),
          (2, QueueStatus.inProgress, 'in_progress'),
          (3, QueueStatus.completed, 'completed'),
          (4, QueueStatus.cancelled, 'cancelled'),
        ],
      );

      // The active-only rule still picks the newest active entry.
      expect(freshQueue.activeEntry!.id, 1);
      final dashboard = DashboardProvider(db);
      await dashboard.fetchDashboardData('A', 'uploader-A');
      expect(dashboard.activeQueueEntry!.id, 1);
      expect(dashboard.activeQueueEntry!.status, QueueStatus.waiting);

      freshQueue.dispose();
      queue.dispose();
      dashboard.dispose();
    },
  );
}
