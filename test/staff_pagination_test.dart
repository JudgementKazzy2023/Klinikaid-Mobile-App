import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/repositories/rag_documents_repository.dart';
import 'package:klinikaid_mobile/features/admin/data/admin_repository.dart';
import 'package:klinikaid_mobile/features/admin/presentation/providers/admin_provider.dart';
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_logs_screen.dart';
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_staff_screen.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/specialist/data/specialist_repository.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/providers/specialist_provider.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/screens/specialist_directory_screen.dart';

/// The index of the row that only a search finds.
///
/// It sits behind the first page of every list, so a read that filters on the
/// client side never sees it.
const int kNeedleIndex = 240;

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
  FakePostgrest(this.tables, {this.maxRows = 1000});

  final Map<String, List<Map<String, dynamic>>> tables;

  /// The server's row cap for a single response.
  final int maxRows;

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

    final table = request.url.pathSegments.last;
    final params = request.url.queryParametersAll;
    var rows = List<Map<String, dynamic>>.from(tables[table] ?? const []);

    for (final entry in params.entries) {
      if (const {'select', 'offset', 'limit', 'order'}.contains(entry.key)) continue;
      for (final raw in entry.value) {
        rows = rows.where((row) => _matches(entry.key, raw, row)).toList();
      }
    }

    final order = params['order']?.first;
    if (order != null && order.isNotEmpty) {
      _applyOrder(rows, order, _nextSequence(table, params));
    }

    final offset = int.tryParse(params['offset']?.first ?? '0') ?? 0;
    final limit = int.tryParse(params['limit']?.first ?? '${rows.length}') ?? rows.length;
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
        .where((entry) => !const {'select', 'offset', 'limit', 'order'}.contains(entry.key))
        .map((entry) => '${entry.key}=${entry.value.join(',')}')
        .join('&')}';
    final next = _sequences[signature] ?? 0;
    _sequences[signature] = next + 1;
    return next;
  }

  /// Sorts the rows the way the server would and rotates the rows that share
  /// every sort value.
  ///
  /// The sort is applied to all sort columns at once, the way PostgREST does.
  /// The rows that share the whole sort key have no fixed place in the order,
  /// so the fake rotates them by the number of requests it already served for
  /// the same filter: two pages of one read then see a different order.
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

  /// Fills the embedded rows the app asks for (`user:profiles(...)`).
  void _resolveEmbeds(List<Map<String, dynamic>> rows, String select) {
    const foreignKeys = {
      'user': 'user_id',
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
      case 'ilike':
        return _ilike(cell ?? '', value);
      case 'in':
        final inner = value.replaceAll('(', '').replaceAll(')', '');
        return inner.split(',').map((item) => item.replaceAll('"', '')).contains(cell);
      default:
        return true;
    }
  }

  /// Matches an ILIKE pattern: `%` is the wildcard, `\` escapes the next char.
  bool _ilike(String cell, String pattern) {
    final haystack = cell.toLowerCase();
    final needle = pattern.toLowerCase();
    final parts = <String>[];
    final buffer = StringBuffer();
    var index = 0;
    while (index < needle.length) {
      final char = needle[index];
      if (char == r'\' && index + 1 < needle.length) {
        buffer.write(needle[index + 1]);
        index += 2;
        continue;
      }
      if (char == '%') {
        parts.add(buffer.toString());
        buffer.clear();
        index++;
        continue;
      }
      buffer.write(char);
      index++;
    }
    parts.add(buffer.toString());

    var rest = haystack;
    for (final part in parts) {
      if (part.isEmpty) continue;
      final found = rest.indexOf(part);
      if (found < 0) return false;
      rest = rest.substring(found + part.length);
    }
    return true;
  }
}

Map<String, dynamic> _patientRow(int index) {
  // Newest first, so the fixture order is the order the app asks for.
  final created = DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index));
  return {
    'id': 'patient-$index',
    'specialist_id': 'specialist-1',
    'first_name': index == 2400 ? 'Needle' : 'Patient',
    'last_name': 'Row$index',
    'date_of_birth': '1990-01-01',
    'gender': 'other',
    'contact_number': null,
    'email': null,
    'address': null,
    'created_at': created.toIso8601String(),
    'updated_at': created.toIso8601String(),
  };
}

Map<String, dynamic> _profileRow(int index, {String role = 'receptionist'}) {
  final created = DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index));
  return {
    'id': 'profile-$index',
    'full_name': index == 1400 ? 'Needle Staff' : 'Staff $index',
    'role': role,
    'role_id': null,
    'department': null,
    'employee_type': null,
    'is_active': true,
    'created_at': created.toIso8601String(),
    'updated_at': created.toIso8601String(),
  };
}

Map<String, dynamic> _systemLogRow(int index, {String? userId}) {
  final created = DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index));
  return {
    'id': '$index',
    'user_id': userId ?? 'profile-$index',
    'event_type': 'login',
    'description': index == kNeedleIndex ? 'Needle event description' : 'Routine event $index',
    'ip_address': '0.0.0.0',
    'created_at': created.toIso8601String(),
  };
}

Map<String, dynamic> _chatbotLogRow(int index) {
  final created = DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index));
  return {
    'id': index + 1,
    'user_id': null,
    'session_id': 'session-$index',
    'user_message': index == kNeedleIndex ? 'Needle question' : 'Question $index',
    'bot_response': 'Answer $index',
    'tokens_used': 10,
    'feedback': null,
    'created_at': created.toIso8601String(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePostgrest server;
  late SupabaseClient client;

  /// A client for the given fixture tables.
  ///
  /// A widget test has to build the client inside `tester.runAsync`: a large
  /// response is decoded in a real isolate, and a fake clock never delivers
  /// the isolate's answer.
  SupabaseClient useTables(Map<String, List<Map<String, dynamic>>> tables) {
    server = FakePostgrest(tables);
    return SupabaseClient('https://example.invalid', 'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => server.handle(request)));
  }

  /// The admin provider on top of the mocked server.
  AdminProvider useAdmin() => AdminProvider(
    repository: AdminRepository(client: client),
    ragRepository: _UnusedRag(),
    deptRepository: DepartmentRepository(client: client),
  );

  tearDown(() async {
    await client.dispose();
  });

  test('specialist directory reaches every row past the server row cap', () async {
    client = useTables({
      'specialist_patients': [for (var i = 0; i < 2500; i++) _patientRow(i)],
    });
    final repo = SpecialistRepository(client: client);

    final patients = await repo.getMyPatients();

    expect(patients, hasLength(2500));
    expect(patients.first.fullName, 'Patient Row0');
    expect(patients.last.fullName, 'Patient Row2499');
    // The read paged instead of asking for one capped response.
    expect(server.requestCount('specialist_patients'), greaterThan(1));
  });

  test('specialist dashboard reports the exact patient count', () async {
    client = useTables({
      'specialist_patients': [for (var i = 0; i < 2500; i++) _patientRow(i)],
      'specialist_records': const [],
    });
    final state = SpecialistProvider(repository: SpecialistRepository(client: client));

    await state.loadDashboard();

    expect(state.totalPatients, 2500);
  });

  test('specialist search finds a patient that lives past the first page', () async {
    client = useTables({
      'specialist_patients': [for (var i = 0; i < 2500; i++) _patientRow(i)],
    });
    final state = SpecialistProvider(repository: SpecialistRepository(client: client));

    await state.loadDirectory();
    state.search('Needle');

    expect(state.searchResults, hasLength(1));
    expect(state.searchResults.single.id, 'patient-2400');
  });

  testWidgets('specialist directory shows the exact roster count', (tester) async {
    late SpecialistProvider state;
    await tester.runAsync(() async {
      client = useTables({
        'specialist_patients': [for (var i = 0; i < 2500; i++) _patientRow(i)],
      });
      state = SpecialistProvider(repository: SpecialistRepository(client: client));
      await state.loadDirectory();
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: SpecialistDirectoryScreen()),
    ));
    await tester.pump();

    expect(state.directoryTotal, 2500);
    expect(find.text('2500 patients'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('admin staff list reaches every row past the server row cap', () async {
    client = useTables({
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final staff = await repo.getStaffPersonnel();

    expect(staff, hasLength(1500));
    expect(server.requestCount('profiles'), greaterThan(1));
  });

  testWidgets('admin staff screen shows the exact personnel count', (tester) async {
    late AdminProvider state;
    await tester.runAsync(() async {
      client = useTables({
        'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
        'roles': const [],
      });
      state = AdminProvider(
        repository: AdminRepository(client: client),
        ragRepository: _UnusedRag(),
        deptRepository: DepartmentRepository(client: client),
      );
      await state.loadStaff();
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AdminStaffScreen()),
    ));
    await tester.pump();

    expect(state.staffTotal, 1500);
    expect(find.text('1500 personnel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  test('admin system events find a description match past the first page', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final logs = await repo.getSystemEvents(textSearch: 'Needle');

    expect(logs, hasLength(1));
    expect(logs.single.description, 'Needle event description');
    // The search is applied by the server, so the scan is not limited to the
    // rows of one page.
    expect(server.requestCount('system_logs'), 1);
  });

  test('admin system events are filtered by one chosen user', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final logs = await repo.getSystemEvents(userId: 'profile-1400');

    // The events of the chosen user, and only those.
    expect(logs, hasLength(1));
    expect(logs.single.userName, 'Needle Staff');
    // The server compares the column with one id, the way the web filters it.
    // A list of ids would grow with the staff list until the server rejects
    // the url.
    expect(server.requests.last.queryParameters['user_id'], 'eq.profile-1400');
    expect(server.requests.last.query, isNot(contains('in.(')));
  });

  test('the user filter keeps the event list paged and totally ordered', () async {
    client = useTables({
      // One staff member wrote every event, so the filtered list is as long
      // as the unfiltered one.
      'system_logs': [
        for (var i = 0; i < 1500; i++) _systemLogRow(i, userId: 'profile-7')
      ],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final state = useAdmin();

    await state.loadSystemEvents(userId: 'profile-7');
    await state.loadMoreSystemEvents();

    final request = server.requests
        .firstWhere((uri) => uri.pathSegments.last == 'system_logs');
    // The server compares the column with one id, the way the web filters it.
    expect(request.queryParameters['user_id'], 'eq.profile-7');
    expect(request.query, isNot(contains('in.(')));
    // The list is read page by page, in a total order.
    expect(
      request.queryParameters['order'],
      'created_at.desc.nullslast,id.desc.nullslast',
    );
    expect(request.queryParameters['offset'], '0');
    expect(request.queryParameters['limit'], '$kAdminLogsPageSize');
    expect(state.systemEvents, hasLength(2 * kAdminLogsPageSize));
    expect(state.systemEventsTotal, 1500);
    // The total comes from the first page; a second count is not paid for.
    expect(server.countRequestCount('system_logs'), 1);
    state.dispose();
  });

  test('the user picker reads a bounded list of profiles', () async {
    client = useTables({
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final users = await repo.searchLogUsers('Staff');

    // The picker offers a bounded list, so a name never turns into a read of
    // the whole profile table.
    expect(users, hasLength(kAdminLogUserPickerLimit));
    expect(server.requestCount('profiles'), 1);
    expect(
      server.requests.last.queryParameters['limit'],
      '$kAdminLogUserPickerLimit',
    );
  });

  test('admin queue submissions reach every row past the server row cap', () async {
    client = useTables({
      'documents': [
        for (var i = 0; i < 1200; i++)
          {
            'id': 'doc-$i',
            'patient_id': 'patient-$i',
            'file_name': 'file-$i.pdf',
            'file_type': 'PDF',
            'status': 'pending',
            'created_at': DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)).toIso8601String(),
          }
      ],
      'patients': const [],
      'profiles': const [],
    });
    final repo = AdminRepository(client: client);

    final submissions = await repo.getAllQueueSubmissions();

    expect(submissions, hasLength(1200));
    expect(server.requestCount('documents'), greaterThan(1));
  });

  test('admin department records reach every row past the server row cap', () async {
    client = useTables({
      'department_records': [
        for (var i = 0; i < 1200; i++)
          {
            'id': 'record-$i',
            'patient_id': 'patient-$i',
            'recorder_id': 'profile-$i',
            'department': 'laboratory',
            'test_type': 'CBC',
            'test_name': 'Hemoglobin',
            'test_value': '13.5',
            'unit': 'g/dL',
            'reference_range_min': 12.0,
            'reference_range_max': 16.0,
            'is_flagged': false,
            'notes': null,
            'created_at': DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)).toIso8601String(),
            'updated_at': DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)).toIso8601String(),
          }
      ],
      'patients': const [],
      'profiles': const [],
    });
    final repo = AdminRepository(client: client);

    final records = await repo.getDepartmentRecords('laboratory');

    expect(records, hasLength(1200));
    expect(server.requestCount('department_records'), greaterThan(1));
  });

  test('admin dashboard workload counts every queue entry of the day', () async {
    final today = DateTime.now().toUtc();
    client = useTables({
      'patient_queue': [
        for (var i = 0; i < 1500; i++)
          {
            'id': 'queue-$i',
            'department': i.isEven ? 'laboratory' : 'imaging',
            'created_at': today.toIso8601String(),
          }
      ],
      'documents': const [],
      'profiles': const [],
      'chatbot_logs': const [],
      'system_logs': const [],
    });
    final repo = AdminRepository(client: client);

    final data = await repo.getDashboardData();
    final workload = data['departmentWorkload'] as Map<String, int>;

    expect(workload['laboratory'], 750);
    expect(workload['imaging'], 750);
    expect(server.requestCount('patient_queue'), greaterThan(1));
  });

  // --- Round 2: total order, paged log lists, one count per read ---

  test('every row is read exactly once when many rows share a timestamp', () async {
    const total = 1500;
    client = useTables({
      'specialist_patients': [
        for (var i = 0; i < total; i++)
          {
            'id': 'patient-$i',
            'specialist_id': 'specialist-1',
            'first_name': 'Patient',
            'last_name': 'Row$i',
            'date_of_birth': '1990-01-01',
            'gender': 'other',
            // Every row shares the timestamp, so only the primary key can
            // give them a fixed place in the order.
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
          }
      ],
    });
    final repo = SpecialistRepository(client: client);

    final patients = await repo.getMyPatients();

    // The page boundary falls inside the group of rows that share a timestamp.
    expect(server.requestCount('specialist_patients'), greaterThan(1));

    // Every row is reached exactly once: none is skipped and none is read
    // twice. The rows are counted, not deduplicated, so a repeated row would
    // show up here.
    final seen = <String, int>{};
    for (final patient in patients) {
      seen[patient.id] = (seen[patient.id] ?? 0) + 1;
    }
    expect(patients, hasLength(total));
    expect(seen, hasLength(total));
    expect(seen.values.every((count) => count == 1), isTrue);
  });

  test('the exact count is asked for once per read', () async {
    client = useTables({
      'specialist_patients': [for (var i = 0; i < 2500; i++) _patientRow(i)],
    });
    final repo = SpecialistRepository(client: client);

    await repo.getMyPatients();

    // Three pages were read...
    expect(server.requestCount('specialist_patients'), 3);
    // ...but the server counted the rows only once.
    expect(server.countRequestCount('specialist_patients'), 1);
  });

  test('the system event list shows the first page with the exact total', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final state = useAdmin();

    await state.loadSystemEvents();

    expect(state.systemEvents, hasLength(kAdminLogsPageSize));
    expect(state.systemEventsTotal, 1500);
    expect(state.hasMoreSystemEvents, isTrue);
    // The list is read page by page, not in one eager sweep.
    expect(server.requestCount('system_logs'), 1);
    state.dispose();
  });

  test('load more appends the next page of the system event list', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final state = useAdmin();

    await state.loadSystemEvents();
    await state.loadMoreSystemEvents();

    expect(state.systemEvents, hasLength(2 * kAdminLogsPageSize));
    expect(state.systemEventsTotal, 1500);
    // The total comes from the first page; a second count is not paid for.
    expect(server.countRequestCount('system_logs'), 1);
    state.dispose();
  });

  test('every system event is reachable page by page', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final state = useAdmin();

    await state.loadSystemEvents();
    while (state.hasMoreSystemEvents) {
      await state.loadMoreSystemEvents();
    }

    expect(state.systemEvents, hasLength(1500));
    // Every event is on screen once: the pages continue where the last one
    // stopped instead of repeating or skipping rows.
    final ids = state.systemEvents.map((log) => log.id).toList();
    expect(ids.toSet(), hasLength(1500));
    state.dispose();
  });

  test('a search match behind the first page is found and reachable', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);
    final state = useAdmin();

    // The needle is not on the first page.
    final first = await repo.getSystemEventsPage();
    expect(first.logs, hasLength(kAdminLogsPageSize));
    expect(
      first.logs.any((log) => log.description.contains('Needle')),
      isFalse,
    );

    // The server filters, so the needle is found although it is behind the
    // first page of the list.
    final found = await repo.getSystemEventsPage(textSearch: 'Needle');
    expect(found.logs, hasLength(1));
    expect(found.logs.single.description, 'Needle event description');

    // Paging reaches it as well.
    await state.loadSystemEvents();
    while (!state.systemEvents.any((log) => log.description.contains('Needle'))) {
      expect(state.hasMoreSystemEvents, isTrue);
      await state.loadMoreSystemEvents();
    }
    expect(
      state.systemEvents.where((log) => log.description.contains('Needle')),
      hasLength(1),
    );
    state.dispose();
  });

  test('the chatbot audit shows the first page with the exact total', () async {
    client = useTables({
      'chatbot_logs': [for (var i = 0; i < 1200; i++) _chatbotLogRow(i)],
    });
    final state = useAdmin();

    await state.loadChatbotAudit();

    expect(state.chatbotLogs, hasLength(kAdminLogsPageSize));
    expect(state.chatbotTotal, 1200);
    expect(state.hasMoreChatbotLogs, isTrue);
    state.dispose();
  });

  test('load more appends the next page of the chatbot audit', () async {
    client = useTables({
      'chatbot_logs': [for (var i = 0; i < 1200; i++) _chatbotLogRow(i)],
    });
    final state = useAdmin();

    await state.loadChatbotAudit();
    await state.loadMoreChatbotAudit();

    expect(state.chatbotLogs, hasLength(2 * kAdminLogsPageSize));
    expect(state.chatbotTotal, 1200);
    state.dispose();
  });

  test('a chatbot log behind the first page is found by the search', () async {
    client = useTables({
      'chatbot_logs': [for (var i = 0; i < 1200; i++) _chatbotLogRow(i)],
    });
    final repo = AdminRepository(client: client);

    final page = await repo.getChatbotAuditPage();
    expect(page.logs, hasLength(kAdminLogsPageSize));
    expect(
      page.logs.any((log) => log.userMessage.contains('Needle')),
      isFalse,
    );

    // The needle lives on the third page of the list.
    final third = await repo.getChatbotAuditPage(offset: 2 * kAdminLogsPageSize);
    expect(third.logs.any((log) => log.userMessage.contains('Needle')), isTrue);
  });

  testWidgets('the log screen filters the events by the chosen user',
      (tester) async {
    late AdminProvider state;
    await tester.runAsync(() async {
      client = useTables({
        'system_logs': [
          for (var i = 0; i < 20; i++) _systemLogRow(i, userId: 'profile-1'),
        ],
        'profiles': [_profileRow(1)],
      });
      state = useAdmin();
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AdminLogsScreen()),
    ));
    await tester.pumpAndSettle();

    // The filter board is a collapsed tile, so open it before the picker.
    await tester.tap(find.text('Event Filters'));
    await tester.pumpAndSettle();

    // The picker offers the users whose name matches the term.
    await tester.enterText(find.byType(TextField).first, 'Staff 1');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Staff 1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, 'Staff 1'));
    await tester.pumpAndSettle();

    // The chosen user is the one the server is asked for.
    final request = server.requests
        .lastWhere((uri) => uri.pathSegments.last == 'system_logs');
    expect(request.queryParameters['user_id'], 'eq.profile-1');
    expect(request.query, isNot(contains('in.(')));
    expect(find.text('Showing the events of Staff 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('the admin log screen shows the loaded count of the exact total',
      (tester) async {
    late AdminProvider state;
    await tester.runAsync(() async {
      // The rows are small on purpose: a widget test decodes a response of
      // more than 10 kB in an isolate, whose answer the fake clock of the
      // test never delivers.
      client = useTables({
        'system_logs': [
          for (var i = 0; i < 150; i++)
            {'id': '$i', 'created_at': '2026-01-01T00:00:00.000Z'},
        ],
      });
      state = useAdmin();
    });

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: AdminLogsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Showing 100 of 150'), findsOneWidget);
    expect(find.byKey(const Key('btn_load_more_logs')), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_load_more_logs')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 150 of 150'), findsOneWidget);
    // Every event is on screen, so there is nothing left to load.
    expect(find.byKey(const Key('btn_load_more_logs')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}

/// The RAG repository is out of scope for these reads.
class _UnusedRag implements RagDocumentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RAG access');
}
