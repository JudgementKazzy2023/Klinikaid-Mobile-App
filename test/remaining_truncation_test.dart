import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/department/presentation/providers/department_provider.dart';
import 'package:klinikaid_mobile/features/department/presentation/screens/department_queue_screen.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_queue_screen.dart';

/// A minimal PostgREST stand-in.
///
/// It answers the range, count, order and filter parameters the app sends and
/// caps a single response at [maxRows], the way PostgREST's max-rows does. A
/// read that does not page therefore loses everything past the cap, which is
/// what the regression tests guard against.
///
/// Rows that share every sort value have no fixed place in the order, and the
/// server may answer two requests with a different order for them. The fake
/// models that: a tied group is rotated by the number of requests it has
/// already served for the same filter. A read that pages over such an order
/// without a unique tiebreaker therefore skips and repeats rows, while a read
/// that orders by a unique column has no tied rows at all and is unaffected.
class FakePostgrest {
  FakePostgrest(this.tables, {this.maxRows = 1000, this.failWith});

  final Map<String, List<Map<String, dynamic>>> tables;

  /// The server's row cap for a single response.
  final int maxRows;

  /// The status code the server answers with, when it should fail.
  final int? failWith;

  /// Every request the app made, in order.
  final List<Uri> requests = [];

  /// The requests that asked the server for an exact count.
  final List<Uri> countRequests = [];

  /// How many requests each filter has served.
  final Map<String, int> _sequences = {};

  int requestCount(String table) =>
      requests.where((uri) => uri.pathSegments.last == table).length;

  /// The number of requests to [table] that asked for the exact count.
  int countRequestCount(String table) =>
      countRequests.where((uri) => uri.pathSegments.last == table).length;

  http.Response handle(http.Request request) {
    requests.add(request.url);
    final prefer = request.headers['prefer'] ?? '';
    if (prefer.contains('count=exact')) countRequests.add(request.url);

    if (failWith != null) {
      return http.Response(
        jsonEncode({'message': 'denied', 'code': '42501'}),
        failWith!,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }

    final table = request.url.pathSegments.last;
    final params = request.url.queryParametersAll;
    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);

    for (final entry in params.entries) {
      if (const {'select', 'offset', 'limit', 'order'}.contains(entry.key)) {
        continue;
      }
      for (final raw in entry.value) {
        rows = rows.where((row) => _matches(entry.key, raw, row)).toList();
      }
    }

    final order = params['order']?.first;
    if (order != null && order.isNotEmpty) {
      _applyOrder(rows, order, _nextSequence(table, params));
    }

    final offset = int.tryParse(params['offset']?.first ?? '0') ?? 0;
    final limit =
        int.tryParse(params['limit']?.first ?? '${rows.length}') ?? rows.length;
    final total = rows.length;
    final start = offset.clamp(0, total);
    final end = (offset + limit).clamp(0, total);
    var page = rows.sublist(start, end);
    if (page.length > maxRows) page = page.sublist(0, maxRows);
    _resolveEmbeds(page, params['select']?.first ?? '*');

    final last = page.isEmpty ? offset : offset + page.length - 1;
    return http.Response(
      jsonEncode(page),
      200,
      request: request,
      headers: {
        'content-type': 'application/json',
        'content-range': page.isEmpty ? '*/$total' : '$offset-$last/$total',
      },
    );
  }

  /// The number of requests this filter has served before this one.
  int _nextSequence(String table, Map<String, List<String>> params) {
    final signature = '$table|${params.entries
        .where((entry) =>
            !const {'select', 'offset', 'limit', 'order'}.contains(entry.key))
        .map((entry) => '${entry.key}=${entry.value.join(',')}')
        .join('&')}';
    final next = _sequences[signature] ?? 0;
    _sequences[signature] = next + 1;
    return next;
  }

  /// Sorts the rows the way the server would and rotates the rows that share
  /// every sort value.
  void _applyOrder(
    List<Map<String, dynamic>> rows,
    String order,
    int sequence,
  ) {
    final columns = <({String column, bool descending})>[];
    for (final part in order.split(',')) {
      final bits = part.split('.');
      if (bits.isEmpty || bits.first.isEmpty) continue;
      columns.add((
        column: bits.first,
        descending: bits.length > 1 && bits[1] == 'desc',
      ));
    }
    if (columns.isEmpty) return;

    rows.sort((a, b) {
      for (final column in columns) {
        final cmp = _compareValues(a[column.column], b[column.column]);
        if (cmp != 0) return column.descending ? -cmp : cmp;
      }
      return 0;
    });

    var start = 0;
    while (start < rows.length) {
      var end = start + 1;
      while (end < rows.length && _sameKey(rows[start], rows[end], columns)) {
        end++;
      }
      if (end - start > 1 && sequence > 0) {
        final group = rows.sublist(start, end);
        final shift = sequence % group.length;
        final rotated = [...group.sublist(shift), ...group.sublist(0, shift)];
        for (var i = 0; i < rotated.length; i++) {
          rows[start + i] = rotated[i];
        }
      }
      start = end;
    }
  }

  /// Compares two cell values, numbers numerically and everything else as text.
  int _compareValues(Object? left, Object? right) {
    if (left is num && right is num) return left.compareTo(right);
    final a = left?.toString() ?? '';
    final b = right?.toString() ?? '';
    return a.compareTo(b);
  }

  /// True when both rows share every sort value.
  bool _sameKey(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    List<({String column, bool descending})> columns,
  ) {
    for (final column in columns) {
      if (_compareValues(a[column.column], b[column.column]) != 0) return false;
    }
    return true;
  }

  /// Fills the embedded rows the app asks for (`patient:patients(*)`).
  void _resolveEmbeds(List<Map<String, dynamic>> rows, String select) {
    const foreignKeys = {
      'uploader': 'uploader_id',
      'patient': 'patient_id',
      'recorder': 'recorder_id',
    };
    for (final match in RegExp(r'(\w+):(\w+)\(').allMatches(select)) {
      final alias = match.group(1)!;
      final table = match.group(2)!;
      final key = foreignKeys[alias];
      if (key == null) continue;
      final linked = tables[table] ?? const [];
      for (final row in rows) {
        final id = row[key]?.toString();
        final match = id == null
            ? null
            : linked.where((candidate) => candidate['id']?.toString() == id);
        row[alias] = match == null || match.isEmpty ? null : match.first;
      }
    }
  }

  bool _matches(String column, String raw, Map<String, dynamic> row) {
    final dot = raw.indexOf('.');
    if (dot < 0) return true;
    final operator = raw.substring(0, dot);
    final value = raw.substring(dot + 1);
    final cell = row[column]?.toString();
    switch (operator) {
      case 'eq':
        return cell == value;
      case 'neq':
        return cell != value;
      case 'gt':
        return (cell ?? '').compareTo(value) > 0;
      case 'gte':
        return (cell ?? '').compareTo(value) >= 0;
      case 'lt':
        return (cell ?? '').compareTo(value) < 0;
      case 'lte':
        return (cell ?? '').compareTo(value) <= 0;
      case 'in':
        final inner = value.replaceAll('(', '').replaceAll(')', '');
        return inner
            .split(',')
            .map((item) => item.replaceAll('"', ''))
            .contains(cell);
      default:
        return true;
    }
  }
}

/// A queue entry of the department fixture.
Map<String, dynamic> _queueRow(int index, {String? createdAt}) {
  final created = createdAt ??
      DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index)).toIso8601String();
  return {
    'id': index + 1,
    'patient_id': 'patient-$index',
    'department': 'laboratory',
    'status': index.isEven ? 'waiting' : 'in_progress',
    'priority_level': 'routine',
    'triage_notes': null,
    'created_at': created,
    'updated_at': created,
  };
}

/// The patient of a queue entry.
Map<String, dynamic> _patientRow(int index) => {
      'id': 'patient-$index',
      'profile_id': null,
      'first_name': 'Patient',
      'last_name': 'Row$index',
      'date_of_birth': '1990-01-01',
      'gender': 'other',
      'contact_number': null,
      'email': null,
      'address': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    };

/// A document of the reception fixture.
Map<String, dynamic> _documentRow(int index, {String status = 'pending'}) {
  final created = DateTime.utc(2026, 1, 1)
      .subtract(Duration(minutes: index))
      .toIso8601String();
  return {
    'id': 'doc-$index',
    'patient_id': 'patient-$index',
    'uploader_id': 'profile-1',
    'file_name': 'file-$index.pdf',
    'file_type': 'pdf',
    'status': status,
    'created_at': created,
  };
}

/// The uploader of the documents.
Map<String, dynamic> _uploaderRow() => {
      'id': 'profile-1',
      'full_name': 'Reception On Duty',
      'role': 'receptionist',
    };

/// A department provider whose reads are stubbed out.
///
/// The provider builds its own repository, so the screen is tested with the
/// values it shows instead of with a server.
class _StubDepartmentProvider extends DepartmentProvider {
  _StubDepartmentProvider(
    super.department, {
    this.entries = const [],
    this.total,
    this.error,
  });

  final List<PatientQueue> entries;
  final int? total;
  final String? error;

  @override
  bool get isLoading => false;

  @override
  List<PatientQueue> get queueEntries => entries;

  @override
  int get queueTotal => total ?? entries.length;

  @override
  String? get queueError => error;

  @override
  Future<void> loadDashboard() async {}
}

/// A reception repository whose reads are stubbed out.
class _StubReceptionRepository extends ReceptionRepository {
  _StubReceptionRepository(this.documents, {required SupabaseClient client})
      : super(client: client);

  final List<Submission> documents;

  @override
  Future<SubmissionsPage> getSubmissionsPage({
    SubmissionStatus? status,
    int offset = 0,
    int limit = kReceptionSubmissionsPageSize,
  }) async {
    final matching = status == null
        ? documents
        : documents.where((s) => s.status == status).toList();
    return SubmissionsPage(
      submissions: matching.skip(offset).take(limit).toList(),
      total: matching.length,
    );
  }
}

/// An auth provider that signs nobody in.
class _StubAuthProvider extends AuthProvider {
  _StubAuthProvider({required SupabaseClient client}) : super(client: client);

  @override
  bool get isAuthenticated => false;

  @override
  bool get isLoading => false;

  @override
  bool get hasConsented => true;

  @override
  bool get isOnboarded => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The Supabase auth client keeps its session in shared preferences.
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    });

    // The screens read an AuthProvider, which builds its repositories from the
    // global Supabase instance. The instance is pointed at a mock transport, so
    // nothing leaves the test and no live project is touched.
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'fake-anon-key',
      debug: false,
      httpClient: MockClient((request) async => http.Response(
            jsonEncode(<String, dynamic>{}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          )),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  late FakePostgrest server;
  late SupabaseClient client;

  /// Whether the running test owns the client the tearDown disposes.
  ///
  /// A widget test cannot dispose a client that an auth provider listens to:
  /// the disposal waits for the auth stream, which never closes inside the
  /// fake clock of a widget test.
  var ownsClient = true;

  /// A client for the given fixture tables.
  SupabaseClient useTables(
    Map<String, List<Map<String, dynamic>>> tables, {
    int? failWith,
  }) {
    server = FakePostgrest(tables, failWith: failWith);
    return SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => server.handle(request)),
    );
  }

  tearDown(() async {
    if (ownsClient) await client.dispose();
    ownsClient = true;
  });

  group('the department queue read', () {
    test('reaches every entry past the server row cap', () async {
      client = useTables({
        'patient_queue': [for (var i = 0; i < 1200; i++) _queueRow(i)],
        'patients': [for (var i = 0; i < 1200; i++) _patientRow(i)],
      });
      final repo = DepartmentRepository(client: client)
        ..adminDepartmentOverride = 'laboratory';

      final queue = await repo.getActiveQueue();

      // Every entry of the queue is there, not just the first page.
      expect(queue.entries, hasLength(1200));
      expect(queue.total, 1200);
      // The read paged instead of asking for one capped response.
      expect(server.requestCount('patient_queue'), greaterThan(1));
      // The server counted the rows once for the whole read.
      expect(server.countRequestCount('patient_queue'), 1);
    });

    test('keeps the department and status filters and no date cutoff', () async {
      client = useTables({
        'patient_queue': [for (var i = 0; i < 5; i++) _queueRow(i)],
        'patients': [for (var i = 0; i < 5; i++) _patientRow(i)],
      });
      final repo = DepartmentRepository(client: client)
        ..adminDepartmentOverride = 'laboratory';

      await repo.getActiveQueue();

      final request = server.requests
          .firstWhere((uri) => uri.pathSegments.last == 'patient_queue');
      expect(request.queryParameters['department'], 'eq.laboratory');
      expect(request.queryParameters['status'], 'in.("waiting","in_progress")');
      // An entry routed before midnight is still listed and still closeable.
      expect(request.queryParameters.containsKey('created_at'), isFalse);
      // The order is total: oldest first, then the primary key.
      expect(
        request.queryParameters['order'],
        'created_at.asc.nullslast,id.asc.nullslast',
      );
    });

    test('reads every entry exactly once when they share a timestamp', () async {
      const total = 1500;
      client = useTables({
        'patient_queue': [
          for (var i = 0; i < total; i++)
            // Every entry shares the timestamp, so only the primary key can
            // give them a fixed place in the order.
            _queueRow(i, createdAt: '2026-01-01T00:00:00.000Z'),
        ],
        'patients': [for (var i = 0; i < total; i++) _patientRow(i)],
      });
      final repo = DepartmentRepository(client: client)
        ..adminDepartmentOverride = 'laboratory';

      final queue = await repo.getActiveQueue();

      // The page boundary falls inside the group of entries that share a
      // timestamp.
      expect(server.requestCount('patient_queue'), greaterThan(1));

      // Every entry is read exactly once: none is skipped and none is read
      // twice.
      final seen = <int, int>{};
      for (final entry in queue.entries) {
        seen[entry.id] = (seen[entry.id] ?? 0) + 1;
      }
      expect(queue.entries, hasLength(total));
      expect(seen, hasLength(total));
      expect(seen.values.every((count) => count == 1), isTrue);
      expect(server.countRequestCount('patient_queue'), 1);
    });

    test('reports an empty queue when the server holds no entry', () async {
      client = useTables({
        'patient_queue': const [],
        'patients': const [],
      });
      final repo = DepartmentRepository(client: client)
        ..adminDepartmentOverride = 'laboratory';

      final queue = await repo.getActiveQueue();

      expect(queue.entries, isEmpty);
      expect(queue.total, 0);
    });

    test('fails instead of reporting an empty queue when the read fails',
        () async {
      client = useTables({
        'patient_queue': [for (var i = 0; i < 5; i++) _queueRow(i)],
        'patients': [for (var i = 0; i < 5; i++) _patientRow(i)],
      }, failWith: 500);
      final repo = DepartmentRepository(client: client)
        ..adminDepartmentOverride = 'laboratory';

      // A broken read is not an empty queue.
      expect(repo.getActiveQueue(), throwsA(isA<Failure>()));
    });
  });

  group('the reception submission read', () {
    test('shows the first page with the exact total', () async {
      client = useTables({
        'documents': [
          for (var i = 0; i < 1200; i++) _documentRow(i),
        ],
        'patients': [for (var i = 0; i < 1200; i++) _patientRow(i)],
        'profiles': [_uploaderRow()],
      });
      final repo = ReceptionRepository(client: client);

      final page = await repo.getSubmissionsPage(
        status: SubmissionStatus.submitted,
      );

      expect(page.submissions, hasLength(kReceptionSubmissionsPageSize));
      expect(page.total, 1200);
      // The board is read page by page, not in one eager sweep.
      expect(server.requestCount('documents'), 1);
      expect(server.countRequestCount('documents'), 1);
    });

    test('reaches every submission page by page, with one count', () async {
      client = useTables({
        'documents': [
          for (var i = 0; i < 1200; i++) _documentRow(i),
        ],
        'patients': [for (var i = 0; i < 1200; i++) _patientRow(i)],
        'profiles': [_uploaderRow()],
      });
      final repo = ReceptionRepository(client: client);

      final loaded = <Submission>[];
      var total = 0;
      var offset = 0;
      while (true) {
        final page = await repo.getSubmissionsPage(
          status: SubmissionStatus.submitted,
          offset: offset,
        );
        total = page.total == 0 ? total : page.total;
        loaded.addAll(page.submissions);
        if (loaded.length >= total) break;
        offset = loaded.length;
      }

      // Every submission is reachable: the pages continue where the last one
      // stopped instead of repeating or skipping rows.
      expect(loaded, hasLength(1200));
      final ids = loaded.map((submission) => submission.id).toSet();
      expect(ids, hasLength(1200));
      // The total comes from the first page; a second count is not paid for.
      expect(server.countRequestCount('documents'), 1);
      expect(server.requestCount('documents'), 12);
    });

    test('reads one status at a time, newest first, in a total order',
        () async {
      client = useTables({
        'documents': [for (var i = 0; i < 5; i++) _documentRow(i)],
        'patients': [for (var i = 0; i < 5; i++) _patientRow(i)],
        'profiles': [_uploaderRow()],
      });
      final repo = ReceptionRepository(client: client);

      await repo.getSubmissionsPage(status: SubmissionStatus.submitted);

      final request = server.requests
          .firstWhere((uri) => uri.pathSegments.last == 'documents');
      expect(request.queryParameters['status'], 'eq.pending');
      expect(
        request.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast',
      );
      expect(request.queryParameters['offset'], '0');
      expect(
        request.queryParameters['limit'],
        '$kReceptionSubmissionsPageSize',
      );
    });

    test('reads every submission exactly once when they share a timestamp',
        () async {
      const total = 1200;
      client = useTables({
        'documents': [
          for (var i = 0; i < total; i++)
            {
              ..._documentRow(i),
              // Every document shares the timestamp, so only the primary key
              // can give them a fixed place in the order.
              'created_at': '2026-01-01T00:00:00.000Z',
            },
        ],
        'patients': [for (var i = 0; i < total; i++) _patientRow(i)],
        'profiles': [_uploaderRow()],
      });
      final repo = ReceptionRepository(client: client);

      final loaded = <Submission>[];
      var counted = 0;
      var offset = 0;
      while (true) {
        final page = await repo.getSubmissionsPage(
          status: SubmissionStatus.submitted,
          offset: offset,
        );
        // Only the first page carries the count; a later page keeps it.
        counted = page.total == 0 ? counted : page.total;
        loaded.addAll(page.submissions);
        if (loaded.length >= counted) break;
        offset = loaded.length;
      }

      // The page boundary falls inside the group of documents that share a
      // timestamp, and no document is skipped or read twice.
      expect(server.requestCount('documents'), greaterThan(1));
      expect(loaded, hasLength(total));
      final ids = loaded.map((submission) => submission.id).toSet();
      expect(ids, hasLength(total));
      expect(server.countRequestCount('documents'), 1);
    });

    test('reports an empty column when the server holds no document', () async {
      client = useTables({
        'documents': const [],
        'patients': const [],
        'profiles': const [],
      });
      final repo = ReceptionRepository(client: client);

      final page = await repo.getSubmissionsPage(
        status: SubmissionStatus.submitted,
      );

      expect(page.submissions, isEmpty);
      expect(page.total, 0);
    });

    test('fails instead of reporting an empty board when the read fails',
        () async {
      client = useTables({
        'documents': [for (var i = 0; i < 5; i++) _documentRow(i)],
        'patients': [for (var i = 0; i < 5; i++) _patientRow(i)],
        'profiles': [_uploaderRow()],
      }, failWith: 500);
      final repo = ReceptionRepository(client: client);

      // A broken read is not an empty board.
      expect(
        repo.getSubmissionsPage(status: SubmissionStatus.submitted),
        throwsA(isA<Failure>()),
      );
    });
  });

  group('the department queue screen', () {
    testWidgets('shows how much of the queue is on screen', (tester) async {
      ownsClient = false;
      final provider = _StubDepartmentProvider(
        'laboratory',
        entries: [
          for (var i = 0; i < 3; i++)
            PatientQueue(
              id: i + 1,
              patientId: 'patient-$i',
              status: QueueStatus.waiting,
              department: Department.laboratory,
              priorityLevel: PriorityLevel.routine,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
        ],
        total: 1200,
      );

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(client: Supabase.instance.client)),
          ChangeNotifierProvider<DepartmentProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: DepartmentQueueScreen()),
      ));
      await tester.pump();

      // The screen says how many entries are on screen and how many the
      // server holds.
      expect(find.text('Showing 3 of 1200 queue entries'), findsOneWidget);
    });

    testWidgets('shows a failed read instead of an empty queue',
        (tester) async {
      ownsClient = false;
      final provider = _StubDepartmentProvider(
        'laboratory',
        error: 'Access denied: you do not have permission to view the queue.',
      );

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(client: Supabase.instance.client)),
          ChangeNotifierProvider<DepartmentProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: DepartmentQueueScreen()),
      ));
      await tester.pumpAndSettle();

      // A broken read is not an empty queue.
      expect(
        find.text('Access denied: you do not have permission to view the queue.'),
        findsOneWidget,
      );
      expect(find.text('No active patients queued.'), findsNothing);
      expect(find.byKey(const Key('btn_retry_queue')), findsOneWidget);
    });
  });

  group('the reception board screen', () {
    testWidgets('shows the loaded count of the exact total and loads more',
        (tester) async {
      ownsClient = false;
      final repo = _StubReceptionRepository([
        for (var i = 0; i < 150; i++)
          Submission(
            id: 'doc-$i',
            patientId: 'patient-$i',
            patientName: 'Patient Row$i',
            fileName: 'file-$i.pdf',
            fileType: 'pdf',
            uploadedAt: DateTime.now(),
            uploadedBy: 'Reception On Duty',
            status: SubmissionStatus.submitted,
          ),
      ], client: Supabase.instance.client);
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(client: Supabase.instance.client)),
          ChangeNotifierProvider<ReceptionQueueProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: ReceptionQueueScreen()),
      ));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      // The board says how much of the column is on screen and how much the
      // server holds.
      expect(find.text('Showing 100 of 150'), findsOneWidget);
      expect(find.byKey(const Key('btn_load_more_submitted')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_load_more_submitted')));
      await tester.pumpAndSettle();

      expect(find.text('Showing 150 of 150'), findsOneWidget);
      // Every submission is on screen, so there is nothing left to load.
      expect(find.byKey(const Key('btn_load_more_submitted')), findsNothing);
    });

    testWidgets('shows a failed read instead of an empty board',
        (tester) async {
      ownsClient = false;
      final repo = _FailingReceptionRepository(client: Supabase.instance.client);
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(client: Supabase.instance.client)),
          ChangeNotifierProvider<ReceptionQueueProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: ReceptionQueueScreen()),
      ));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      // A broken read is not an empty board.
      expect(find.text('The submissions could not be loaded.'), findsOneWidget);
      expect(find.text('No pending documents.'), findsNothing);
      expect(find.byKey(const Key('btn_retry_submissions')), findsOneWidget);
    });
  });
}

/// A reception repository whose read always fails.
class _FailingReceptionRepository extends ReceptionRepository {
  _FailingReceptionRepository({required SupabaseClient client})
      : super(client: client);

  @override
  Future<SubmissionsPage> getSubmissionsPage({
    SubmissionStatus? status,
    int offset = 0,
    int limit = kReceptionSubmissionsPageSize,
  }) async {
    throw const DatabaseFailure('The documents could not be read.');
  }
}
