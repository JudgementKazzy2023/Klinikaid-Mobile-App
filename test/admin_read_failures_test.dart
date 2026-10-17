import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/repositories/rag_documents_repository.dart';
import 'package:klinikaid_mobile/features/admin/data/admin_repository.dart';
import 'package:klinikaid_mobile/features/admin/presentation/providers/admin_provider.dart';
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_logs_screen.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';

// No Supabase.initialize or platform plugins: every HTTP request is intercepted.
class UnusedRag implements RagDocumentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unexpected RAG access');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late AdminRepository repo;
  late AdminProvider state;
  String? failPath;
  Object usage = <Object>[];
  bool populated = false;
  final paths = <String>[];
  final requests = <http.Request>[];
  final blockers = <String, Completer<http.Response>>{};
  http.Response response(http.Request r, Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, request: r, headers: {
      'content-type': 'application/json', 'content-range': '0-0/1',
    });
  setUp(() {
    failPath = null; usage = <Object>[]; populated = false; paths.clear(); blockers.clear(); requests.clear();
    client = SupabaseClient('https://example.invalid', 'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        paths.add(r.url.path);
        requests.add(r);
        final filter = r.url.queryParameters['event_type'];
        if (blockers.containsKey(filter)) return blockers[filter]!.future;
        if (failPath == '*' || r.url.path.endsWith(failPath ?? '!')) {
          return response(r, {'message': 'test denial', 'code': '42501'}, 403);
        }
        if (r.url.path.contains('/rpc/')) return response(r, usage);
        if (r.url.path.endsWith('system_logs')) return response(r, populated ? [{
          'id': 1, 'created_at': DateTime.now().toUtc().toIso8601String(),
          'event_type': 'test', 'description': 'Fixture event',
        }] : []);
        if (r.url.path.endsWith('chatbot_logs') && r.url.queryParameters['select'] == '*') {
          return response(r, populated ? [{ 'id': 1, 'created_at': DateTime.now().toUtc().toIso8601String(),
            'tokens_used': 12, 'user_message': 'Fixture', 'bot_response': 'Fixture' }] : []);
        }
        return response(r, []);
      }));
    repo = AdminRepository(client: client);
    state = AdminProvider(repository: repo, ragRepository: UnusedRag(),
      deptRepository: DepartmentRepository(client: client));
  });
  tearDown(() async { state.dispose(); await client.dispose(); });

  test('required failures propagate; supplementary events fail locally', () async {
    for (final path in ['patient_queue', 'documents', 'profiles', 'chatbot_logs']) {
      failPath = path;
      await expectLater(repo.getDashboardData(), throwsA(anything));
    }
    failPath = 'system_logs';
    final data = await repo.getDashboardData();
    expect(data['recentEvents'], isEmpty);
    expect(data['recentEventsError'], isNotNull);
    expect(data['todayPatients'], 1);
  });
  test('initial failure, valid success, refresh failure clears all provider payloads, retry', () async {
    Future<void> load() async {
      await state.loadDashboard(); await state.loadSystemEvents();
      await state.loadChatbotAudit(); await state.loadApiCost();
    }
    failPath = '*'; await load();
    expect(state.dashboardState, AdminReadState.failed);
    expect(state.dashboardData, isNull);
    expect(state.systemEvents, isEmpty);
    expect(state.chatbotLogs, isEmpty);
    expect(state.costChartData, isEmpty);
    failPath = null; populated = true; await load();
    expect(state.systemEvents, isNotEmpty);
    expect(state.chatbotLogs, isNotEmpty);
    expect(state.costChartData, isNotEmpty);
    failPath = '*'; await load();
    expect(state.dashboardData, isNull);
    expect(state.systemEvents, isEmpty);
    expect(state.chatbotLogs, isEmpty);
    expect(state.todayTokens, 0);
    expect(state.todayCost, 0);
    expect(state.costChartData, isEmpty);
    expect(state.weeklyBreakdown, isEmpty);
    failPath = null; populated = false; await load();
    expect(state.logsState, AdminReadState.loaded);
    expect(state.logsError, isNull);
    expect(state.systemEvents, isEmpty);
  });
  test('cost failures never query chatbot fallback; malformed response rejected; empty valid', () async {
    failPath = 'get_daily_token_usage';
    await expectLater(repo.getApiCostData(), throwsA(anything));
    expect(paths.every((p) => p.endsWith('get_daily_token_usage')), isTrue);
    failPath = null;
    for (final bad in [null, {}, [{'usage_date': 'bad', 'tokens_used': 4}], [{'usage_date': '2026-10-17'}]]) {
      usage = bad ?? 'null';
      await expectLater(repo.getApiCostData(), throwsA(anything));
    }
    usage = <Object>[];
    final data = await repo.getApiCostData();
    expect((data['chartData'] as List).every((r) => r['tokens'] == 0), isTrue);
  });
  test('cost RPC sends required PHT cutoff and consumes web response contract', () async {
    final pht = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime.utc(pht.year, pht.month, pht.day);
    final date = today.toIso8601String().substring(0, 10);
    usage = [{'date': date, 'total_tokens': 1000000, 'query_count': 2}];
    final data = await repo.getApiCostData();
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body), {
      'start_date': today.subtract(const Duration(days: 29, hours: 8)).toIso8601String(),
    });
    final chart = data['chartData'] as List;
    expect(chart, hasLength(30));
    expect(chart.last['date'], date);
    expect(chart.last['tokens'], 1000000);
    expect(chart.last['cost'], closeTo(0.63, 0.00001));
  });
  test('old filter response cannot replace new results', () async {
    blockers['eq.old'] = Completer<http.Response>();
    final old = state.loadSystemEvents(eventType: 'old');
    await Future<void>.delayed(Duration.zero);
    populated = true;
    await state.loadSystemEvents(eventType: 'new');
    expect(state.systemEvents, hasLength(1));
    blockers['eq.old']!.complete(response(http.Request('GET', Uri.parse('https://example.invalid')), []));
    await old;
    expect(state.systemEvents, hasLength(1));
  });
  test('supplementary retry preserves aggregates and clears failed event payload', () async {
    populated = true;
    await state.loadDashboard();
    expect(state.dashboardData!['recentEvents'], isNotEmpty);
    failPath = 'system_logs';
    await state.retryRecentEvents();
    expect(state.dashboardData!['recentEvents'], isEmpty);
    expect(state.dashboardData!['recentEventsError'], isNotNull);
    expect(state.dashboardData!['todayPatients'], 1);
    expect(state.dashboardError, isNull);
    failPath = null;
    await state.retryRecentEvents();
    expect(state.dashboardData!['recentEventsError'], isNull);
    expect(state.dashboardData!['recentEvents'], isNotEmpty);
  });
  testWidgets('failed log refresh clears rows and disables export; Retry recovers', (tester) async {
    populated = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state,
      child: const MaterialApp(home: Scaffold(body: AdminLogsScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Fixture event'), findsOneWidget);
    failPath = '*';
    await state.loadSystemEvents(); await tester.pumpAndSettle();
    expect(find.text('Fixture event'), findsNothing);
    expect(find.text('No events matching filters.'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('btn_export_csv'))).onPressed, isNull);
    expect(find.text('Retry'), findsOneWidget);
    failPath = null;
    await tester.tap(find.text('Retry')); await tester.pumpAndSettle();
    expect(find.text('Fixture event'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
