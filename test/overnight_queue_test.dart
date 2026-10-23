import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/result_entry_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/widgets/queue_completion_banner.dart';

class TestAuth extends GoTrueClient {
  TestAuth() : super(autoRefreshToken: false);
  @override
  User? get currentUser => User(id: 'staff', appMetadata: {}, userMetadata: {},
    aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');
}

class TestClient extends SupabaseClient {
  final fakeAuth = TestAuth();
  TestClient(http.Client transport) : super('https://example.supabase.co', 'fake',
    httpClient: transport, authOptions: const AuthClientOptions(autoRefreshToken: false));
  @override
  GoTrueClient get auth => fakeAuth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('active read preserves department/status/order and has no date cutoff', () async {
    final client = TestClient(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/patient_queue');
      expect(request.url.queryParameters['department'], 'eq.laboratory');
      expect(request.url.queryParameters['status'], 'in.("waiting","in_progress")');
      expect(request.url.queryParameters['order'], 'created_at.asc.nullslast');
      expect(request.url.queryParameters.containsKey('created_at'), isFalse);
      final data = [
        for (var i = 1; i <= 2; i++) {
          'id': i, 'patient_id': 'patient-$i', 'department': 'laboratory',
          'status': i == 1 ? 'waiting' : 'in_progress',
          'created_at': i == 1 ? '2026-10-14T15:59:00Z' : '2026-10-14T16:01:00Z',
          'updated_at': '2026-10-14T16:01:00Z',
        },
      ];
      return http.Response(jsonEncode(data), 200, request: request,
        headers: {'content-type': 'application/json'});
    }));
    final repo = DepartmentRepository(client: client)..adminDepartmentOverride = 'laboratory';
    final result = await repo.getActiveQueue();
    expect(result.map((e) => e.id), [1, 2]);
    expect(result.first.createdAt.isBefore(result.last.createdAt), isTrue);
    await client.dispose();
    client.fakeAuth.dispose();
  });

  for (final lab in [true, false]) {
    for (final outcome in ['success', 'insert-failed', 'queue-failed', 'queue-empty']) {
      test('${lab ? 'lab' : 'free text'} $outcome preserves write filters and save outcome', () async {
        final requests = <http.Request>[];
        final dept = lab ? 'laboratory' : 'imaging';
        final client = TestClient(MockClient((request) async {
          requests.add(request);
          final insert = request.url.path.endsWith('/department_records');
          expect(request.method, insert ? 'POST' : 'PATCH');
          if (!insert) {
            expect(request.url.queryParameters, {
              'patient_id': 'eq.patient', 'department': 'eq.$dept',
              'status': 'in.("waiting","in_progress")',
              'select': 'id',
            });
            expect(jsonDecode(request.body), {'status': 'completed'});
          }
          final failed = insert ? outcome == 'insert-failed' : outcome == 'queue-failed';
          final body = insert ? '' : outcome == 'queue-empty' ? '[]' : '[{"id":1}]';
          return http.Response(failed ? '{"message":"denied","code":"42501"}' : body,
            failed ? 403 : 201, request: request, headers: {'content-type': 'application/json'});
        }));
        final repo = DepartmentRepository(client: client)..adminDepartmentOverride = dept;
        final provider = ResultEntryProvider(repo);
        provider.setParameterValue('Hemoglobin', '14');
        provider.setFindings('Test findings');
        provider.setImpression('Test impression');
        final saved = lab
          ? await provider.submitLabResults(patientId: 'patient', gender: 'male')
          : await provider.submitFreeTextResult(patientId: 'patient', testName: 'X-Ray');
        expect(saved, outcome != 'insert-failed');
        expect(requests.length, outcome == 'insert-failed' ? 1 : 2);
        expect(provider.queueCompletionWarning,
          outcome == 'queue-failed' || outcome == 'queue-empty'
              ? QueueCompletionFailure.message : isNull);
        if (outcome == 'insert-failed') expect(provider.errorMessage, isNotNull);
        await client.dispose();
        client.fakeAuth.dispose();
      });
    }
  }

  testWidgets('partial-save banner survives navigation and time until dismissed', (tester) async {
    final messenger = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: messenger,
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        child: const Text('Enter'), onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (entryContext) => Scaffold(body: TextButton(
            child: const Text('Save'), onPressed: () {
              messenger.currentState!.showMaterialBanner(queueCompletionBanner(
                QueueCompletionFailure.message,
                () => messenger.currentState!.hideCurrentMaterialBanner()));
              Navigator.of(entryContext).pop();
            },
          ))),
        ),
      )))));
    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 10));
    expect(find.text(QueueCompletionFailure.message), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
  });

  for (final queueBody in ['[{"id":1}]', '[]']) {
    test('completeQueue retries only the queue update (response $queueBody)', () async {
      final requests = <http.Request>[];
      final client = TestClient(MockClient((request) async {
        requests.add(request);
        return http.Response(queueBody, 200, request: request,
          headers: {'content-type': 'application/json'});
      }));
      final repo = DepartmentRepository(client: client)..adminDepartmentOverride = 'laboratory';
      final retry = repo.completeQueue('patient');
      if (queueBody == '[]') {
        await expectLater(retry, throwsA(isA<QueueCompletionFailure>()));
      } else {
        await retry;
      }
      expect(requests.map((r) => '${r.method} ${r.url.path}'),
        ['PATCH /rest/v1/patient_queue']);
      expect(requests.single.url.queryParameters, {
        'patient_id': 'eq.patient', 'department': 'eq.laboratory',
        'status': 'in.("waiting","in_progress")', 'select': 'id',
      });
      expect(jsonDecode(requests.single.body), {'status': 'completed'});
      await client.dispose();
      client.fakeAuth.dispose();
    });
  }

  testWidgets('banner offers a queue-only retry when given one', (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: queueCompletionBanner(
      QueueCompletionFailure.message, () {}, onRetry: () => retries++))));
    await tester.tap(find.text('Retry queue update'));
    expect(retries, 1);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: queueCompletionBanner(
      QueueCompletionFailure.message, () {}))));
    expect(find.text('Retry queue update'), findsNothing);
  });
}
