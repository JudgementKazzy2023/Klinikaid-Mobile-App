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
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_staff_screen.dart';
import 'package:klinikaid_mobile/features/department/data/department_repository.dart';
import 'package:klinikaid_mobile/features/specialist/data/specialist_repository.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/providers/specialist_provider.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/screens/specialist_directory_screen.dart';

/// A minimal PostgREST stand-in.
///
/// It answers the range, count, order and filter parameters the app sends and
/// caps a single response at [maxRows], the way PostgREST's max-rows does. A
/// read that does not page therefore loses everything past the cap, which is
/// what the regression tests guard against.
class FakePostgrest {
  FakePostgrest(this.tables, {this.maxRows = 1000});

  final Map<String, List<Map<String, dynamic>>> tables;

  /// The server's row cap for a single response.
  final int maxRows;

  /// Every request the app made, in order.
  final List<Uri> requests = [];

  int requestCount(String table) =>
      requests.where((uri) => uri.pathSegments.last == table).length;

  http.Response handle(http.Request request) {
    requests.add(request.url);
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
    if (order != null && order.isNotEmpty) _applyOrder(rows, order);

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

  void _applyOrder(List<Map<String, dynamic>> rows, String order) {
    for (final part in order.split(',')) {
      final bits = part.split('.');
      final column = bits.first;
      final descending = bits.length > 1 && bits[1] == 'desc';
      rows.sort((a, b) {
        final left = a[column]?.toString() ?? '';
        final right = b[column]?.toString() ?? '';
        return descending ? right.compareTo(left) : left.compareTo(right);
      });
    }
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

Map<String, dynamic> _systemLogRow(int index) {
  final created = DateTime.utc(2026, 1, 1).subtract(Duration(minutes: index));
  return {
    'id': '$index',
    'user_id': 'profile-$index',
    'event_type': 'login',
    'description': index == 1400 ? 'Needle event description' : 'Routine event $index',
    'ip_address': '0.0.0.0',
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

  test('admin system events find a user match past the first page', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final logs = await repo.getSystemEvents(userSearch: 'Needle Staff');

    expect(logs, hasLength(1));
    expect(logs.single.userName, 'Needle Staff');
  });

  test('admin system events page through every matching event', () async {
    client = useTables({
      'system_logs': [for (var i = 0; i < 1500; i++) _systemLogRow(i)],
      'profiles': [for (var i = 0; i < 1500; i++) _profileRow(i)],
    });
    final repo = AdminRepository(client: client);

    final logs = await repo.getSystemEvents();

    expect(logs, hasLength(1500));
    expect(server.requestCount('system_logs'), greaterThan(1));
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

  test('admin chatbot audit reaches every row and reports the exact total', () async {
    client = useTables({
      'chatbot_logs': [
        for (var i = 0; i < 1200; i++)
          {
            'id': i + 1,
            'user_id': null,
            'session_id': 'session-$i',
            'user_message': 'Question $i',
            'bot_response': 'Answer $i',
            'tokens_used': 10,
            'feedback': null,
            'created_at': DateTime.utc(2026, 1, 1).subtract(Duration(minutes: i)).toIso8601String(),
          }
      ],
    });
    final state = AdminProvider(
      repository: AdminRepository(client: client),
      ragRepository: _UnusedRag(),
      deptRepository: DepartmentRepository(client: client),
    );

    await state.loadChatbotAudit();

    expect(state.chatbotLogs, hasLength(1200));
    expect(state.chatbotTotal, 1200);
    expect(server.requestCount('chatbot_logs'), greaterThan(1));
    state.dispose();
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
}

/// The RAG repository is out of scope for these reads.
class _UnusedRag implements RagDocumentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RAG access');
}
