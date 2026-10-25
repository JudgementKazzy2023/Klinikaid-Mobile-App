import 'dart:async';
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
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/reception_search.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/reception_queue_screen.dart';

/// A PostgREST stand-in for the three search branches.
///
/// It records every request so a test can assert the exact filter, order and
/// limit the repository sent, and answers each branch from its own canned
/// rows, bounded by the requested limit the way PostgREST bounds a response.
/// The `or=`/`imatch` conditions themselves are pinned by the helper parity
/// tests and asserted verbatim on the request URLs.
class _SearchServer {
  final List<http.Request> requests = [];

  final Map<String, List<Map<String, dynamic>>> rows =
      <String, List<Map<String, dynamic>>>{
    'file': <Map<String, dynamic>>[],
    'patient': <Map<String, dynamic>>[],
    'uploader': <Map<String, dynamic>>[],
  };

  /// The branch that answers with a failure, if any.
  String? failBranch;

  static String branchOf(http.Request request) {
    final params = request.url.queryParameters;
    if (params.containsKey('patient.or')) return 'patient';
    if (params.containsKey('uploader.or')) return 'uploader';
    return 'file';
  }

  http.Response handle(http.Request request) {
    requests.add(request);
    final branch = branchOf(request);
    if (branch == failBranch) {
      return http.Response(
        jsonEncode({'message': 'database did not answer', 'code': 'XX000'}),
        500,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }
    final limit = int.parse(request.url.queryParameters['limit'] ?? '1000');
    final page = rows[branch]!.take(limit).toList();
    return http.Response(
      jsonEncode(page),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// A repository whose searches complete only when the test says so.
class _QueuedSearchRepository extends ReceptionRepository {
  _QueuedSearchRepository({required SupabaseClient client})
      : super(client: client);

  final List<Completer<SearchResult>> pending = <Completer<SearchResult>>[];

  @override
  Future<SearchResult> searchSubmissions(String rawQuery) {
    final completer = Completer<SearchResult>();
    pending.add(completer);
    return completer.future;
  }
}

/// A reception repository whose reads are stubbed out.
///
/// The screen is tested with the values it shows: the paged board comes from
/// [paged], the whole-table search answer from [matches]/[hasMore], and
/// [failuresLeft] fails the next searches.
class _BoardRepository extends ReceptionRepository {
  _BoardRepository({required SupabaseClient client, required this.paged})
      : super(client: client);

  final List<Submission> paged;
  List<Submission> matches = const [];
  bool hasMore = false;
  int failuresLeft = 0;
  int searchCalls = 0;
  String? lastQuery;

  @override
  Future<SubmissionsPage> getSubmissionsPage({
    SubmissionStatus? status,
    int offset = 0,
    int limit = kReceptionSubmissionsPageSize,
  }) async {
    final matching = status == null
        ? paged
        : paged.where((s) => s.status == status).toList();
    return SubmissionsPage(
      submissions: matching.skip(offset).take(limit).toList(),
      total: matching.length,
    );
  }

  @override
  Future<SearchResult> searchSubmissions(String rawQuery) async {
    searchCalls++;
    lastQuery = rawQuery;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const DatabaseFailure('database did not answer');
    }
    return SearchResult(
      submissions: matches,
      hasMore: hasMore,
      limit: searchResultLimit,
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

/// One joined `documents` row whose patient name is [firstName] [lastName].
Map<String, dynamic> _docRow(
  String id,
  String createdAt, {
  String fileName = 'file.pdf',
  String firstName = 'Qa129',
  String lastName = 'Patient',
}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 'patient-$id',
      'uploader_id': 'profile-1',
      'file_name': fileName,
      'file_type': 'application/pdf',
      'status': 'pending',
      'created_at': createdAt,
      'patient': <String, dynamic>{
        'id': 'patient-$id',
        'first_name': firstName,
        'last_name': lastName,
      },
      'uploader': <String, dynamic>{
        'id': 'profile-1',
        'full_name': 'Reception On Duty',
        'role': 'receptionist',
      },
    };

Submission _submission(
  String id,
  String name, {
  SubmissionStatus status = SubmissionStatus.submitted,
}) =>
    Submission(
      id: id,
      patientId: 'patient-$id',
      patientName: name,
      fileName: '$id.pdf',
      fileType: 'pdf',
      uploadedAt: DateTime.utc(2026, 1, 1),
      uploadedBy: 'Reception On Duty',
      status: status,
    );

Widget _app(ReceptionQueueProvider provider) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _StubAuthProvider(client: Supabase.instance.client)),
        ChangeNotifierProvider<ReceptionQueueProvider>.value(value: provider),
      ],
      child: const MaterialApp(home: ReceptionQueueScreen()),
    );

/// Types [term], lets the debounce fire, and lets the search resolve.
Future<void> _search(WidgetTester tester, String term) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.pump();
  await tester.pump(ReceptionQueueProvider.searchDebounce);
  await tester.pump();
  await tester.pump();
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

    // Nothing leaves the test and no live project is touched.
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

  // ─── Helper parity with web ───────────────────────────────────────────────
  //
  // Every expectation below is a port of one from web's
  // `src/lib/reception-search.test.ts`: same inputs, same outputs. The web
  // file is the specification of the two layers of escaping.

  group('the search helpers mirror web exactly', () {
    test('the bounds are web\'s bounds', () {
      expect(maxSearchTermLength, 100);
      expect(searchResultLimit, 50);
      expect(maxNameSplits, 6);
    });

    group('escapeRegexLiteral', () {
      test('leaves plain text untouched', () {
        expect(escapeRegexLiteral('abc'), 'abc');
      });

      test('escapes the regex metacharacters, including the asterisk', () {
        expect(escapeRegexLiteral('*'), r'\*');
        expect(escapeRegexLiteral('a*b'), r'a\*b');
        expect(
          escapeRegexLiteral(r'.+?^${}()|[]' '\\'),
          r'\.\+\?\^\$\{\}\(\)\|\[\]\\',
        );
      });

      test(
          'leaves % and _ alone; they are literal in a regex, not wildcards',
          () {
        expect(escapeRegexLiteral('%'), '%');
        expect(escapeRegexLiteral('_'), '_');
      });

      test('escapes a backslash first, before it can escape something else',
          () {
        expect(escapeRegexLiteral('\\'), r'\\');
      });

      test('never escapes letters, which would turn them into regex classes',
          () {
        // `\d`, `\w` and friends are character classes; only punctuation may
        // be escaped or the term would stop matching itself.
        expect(escapeRegexLiteral('dw s'), 'dw s');
      });
    });

    group('quotePostgrestValue', () {
      test('wraps a value in double quotes', () {
        expect(quotePostgrestValue('abc'), '"abc"');
      });

      test('escapes a double quote and a backslash inside the quotes', () {
        expect(quotePostgrestValue('a"b'), r'"a\"b"');
        expect(quotePostgrestValue('a\\b'), r'"a\\b"');
      });
    });

    group('buildSearchPattern', () {
      test('produces a quoted, unanchored substring-match pattern', () {
        expect(buildSearchPattern('abc'), '"abc"');
      });

      test(
          'neutralises PostgREST\'s * wildcard alias by escaping the asterisk',
          () {
        // PostgREST rewrites `*` to `%` in like/ilike values with no escape
        // available. The search uses imatch instead, where `\*` reaches
        // Postgres as a literal asterisk after the quoting layer.
        expect(buildSearchPattern('*'), r'"\\*"');
        expect(buildSearchPattern('lab*report'), r'"lab\\*report"');
      });

      test('keeps % and _ literal without escaping them', () {
        // Not regex metacharacters, so the regex engine already matches them
        // literally — no `%`-wrapping and no escapes.
        expect(buildSearchPattern('%'), '"%"');
        expect(buildSearchPattern('_'), '"_"');
      });

      test('keeps PostgREST structural characters literal by quoting them',
          () {
        // `,` would otherwise be parsed as an `or=` condition separator; `(`,
        // `)` and `.` are regex metacharacters on top of that. Inside the
        // double quotes they are value characters.
        expect(buildSearchPattern(','), '","');
        expect(buildSearchPattern('('), r'"\\("');
        expect(buildSearchPattern(')'), r'"\\)"');
        expect(buildSearchPattern('a,b(c)'), r'"a,b\\(c\\)"');
      });

      test(
          'composes both escape layers for a term with metacharacters and commas',
          () {
        // `a,b(c)*` → regex-escaped to `a,b\(c\)\*`, then quoted with each
        // backslash doubled for PostgREST: `"a,b\\(c\\)\\*"`.
        expect(buildSearchPattern('a,b(c)*'), r'"a,b\\(c\\)\\*"');
      });

      test('handles an embedded double quote without terminating the value',
          () {
        // `"` inside the term is escaped as `\"` so it stays part of the
        // value.
        expect(buildSearchPattern('a"b'), r'"a\"b"');
      });
    });

    group('patientNameConditions', () {
      test('matches each name column for a single word', () {
        expect(patientNameConditions('Cruz'), [
          'first_name.imatch.${buildSearchPattern('Cruz')}',
          'last_name.imatch.${buildSearchPattern('Cruz')}',
        ]);
      });

      test('adds one first/last split per word boundary for a full name', () {
        final conditions = patientNameConditions('Juan Dela Cruz');
        expect(
          conditions,
          contains(
            'and(first_name.imatch.${buildSearchPattern('Juan')},'
            'last_name.imatch.${buildSearchPattern('Dela Cruz')})',
          ),
        );
        expect(
          conditions,
          contains(
            'and(first_name.imatch.${buildSearchPattern('Juan Dela')},'
            'last_name.imatch.${buildSearchPattern('Cruz')})',
          ),
        );
        expect(conditions, hasLength(4));
      });

      test('keeps PostgREST grammar characters inside quoted values', () {
        for (final condition in patientNameConditions('a,b (c)')) {
          expect(
            RegExp(r'imatch\.[^"]').hasMatch(condition),
            isFalse,
            reason: condition,
          );
        }
      });

      test('never uses like/ilike, where PostgREST would rewrite * to %', () {
        for (final condition in patientNameConditions('a*b')) {
          expect(
            RegExp(r'\.i?like\.').hasMatch(condition),
            isFalse,
            reason: condition,
          );
          expect(condition, contains(buildSearchPattern('a*b')));
        }
      });
    });
  });

  // ─── The repository search ────────────────────────────────────────────────

  SupabaseClient? client;

  /// A client whose transport answers from [server].
  SupabaseClient useServer(_SearchServer server) {
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => server.handle(request)),
    );
    return client!;
  }

  tearDown(() async {
    final live = client;
    client = null;
    if (live != null) await live.dispose();
  });

  group('the reception document search', () {
    test(
        'queries documents three times with web\'s filters, order and limit '
        'on the trimmed term', () async {
      const term = 'lab*report';
      final server = _SearchServer();
      final repo = ReceptionRepository(client: useServer(server));

      await repo.searchSubmissions('  $term  ');

      expect(server.requests, hasLength(3));
      final allParams = server.requests
          .map((request) => request.url.queryParameters.values.join('&'))
          .join('&');
      for (final request in server.requests) {
        expect(request.url.pathSegments.last, 'documents');
        // Newest-first, declared so the branch bound keeps the newest rows.
        expect(request.url.queryParameters['order'],
            'created_at.desc.nullslast');
        // Each branch fetches one extra row to detect its own bound.
        expect(
            request.url.queryParameters['limit'], '${searchResultLimit + 1}');
        // imatch only, never like/ilike where PostgREST rewrites * to %.
        expect(allParams, isNot(contains('.like.')));
        expect(allParams, isNot(contains('.ilike.')));
        // No branch resolves names through a capped id list (#129).
        expect(allParams, isNot(contains('patient_id.in.')));
        expect(allParams, isNot(contains('uploader_id.in.')));
      }

      final fileBranch = server.requests
          .firstWhere((request) => _SearchServer.branchOf(request) == 'file');
      expect(
        fileBranch.url.queryParameters['or'],
        '(file_name.imatch.${buildSearchPattern(term)},'
        'file_type.imatch.${buildSearchPattern(term)})',
      );
      // The file branch keeps a plain join: an inner join would drop
      // documents whose patient_id is null out of file-name matches.
      expect(fileBranch.url.queryParameters['select'],
          isNot(contains('!inner')));

      final patientBranch = server.requests
          .firstWhere((request) => _SearchServer.branchOf(request) == 'patient');
      expect(
        patientBranch.url.queryParameters['patient.or'],
        '(${patientNameConditions(term).join(',')})',
      );
      // The name branches filter through embedded-resource joins.
      expect(patientBranch.url.queryParameters['select'],
          contains('patient:patients!inner'));

      final uploaderBranch = server.requests
          .firstWhere((request) => _SearchServer.branchOf(request) == 'uploader');
      expect(
        uploaderBranch.url.queryParameters['uploader.or'],
        '(full_name.imatch.${buildSearchPattern(term)})',
      );
      expect(uploaderBranch.url.queryParameters['select'],
          contains('uploader:profiles!inner'));
    });

    test('finds a document past any name cap and reports it truncated',
        () async {
      // 51 distinct matching names, one document each; the last one is the
      // newest, so it must survive the final 50-document cap (#129).
      final server = _SearchServer();
      server.rows['patient'] = [
        for (var i = 1; i <= searchResultLimit; i++)
          _docRow(
            'doc-patient-$i',
            '2026-10-01T00:00:${(59 - i).toString().padLeft(2, '0')}+00:00',
            lastName: 'Patient $i',
          ),
        _docRow('doc-newest', '2026-10-02T00:00:00+00:00',
            lastName: 'Newest Patient'),
      ];
      final repo = ReceptionRepository(client: useServer(server));

      final result = await repo.searchSubmissions('qa129');

      expect(result.submissions, hasLength(searchResultLimit));
      expect(result.hasMore, isTrue);
      expect(result.limit, searchResultLimit);
      // The newest match survives the cap.
      expect(result.submissions.first.id, 'doc-newest');
      // Newest-first is preserved across the merged branches.
      final timestamps = [
        for (final submission in result.submissions)
          submission.uploadedAt.toIso8601String()
      ];
      final ascending = List<String>.from(timestamps)..sort();
      expect(timestamps, ascending.reversed.toList());
    });

    test(
        'de-duplicates a document across branches and reports a complete '
        'search', () async {
      final server = _SearchServer();
      final shared = _docRow('doc-shared', '2026-10-01T00:00:00+00:00',
          fileName: 'qa129-file.pdf');
      server.rows['patient'] = [shared];
      // The same document also matches the file-field branch.
      server.rows['file'] = [
        shared,
        _docRow('doc-file-only', '2026-09-01T00:00:00+00:00',
            fileName: 'qa129-report.pdf'),
      ];
      final repo = ReceptionRepository(client: useServer(server));

      final result = await repo.searchSubmissions('qa129');

      expect(
        [for (final submission in result.submissions) submission.id],
        ['doc-shared', 'doc-file-only'],
      );
      expect(result.hasMore, isFalse);
    });

    test('reports an empty result as complete only when no branch matched',
        () async {
      final server = _SearchServer();
      final repo = ReceptionRepository(client: useServer(server));

      final result = await repo.searchSubmissions('qa129-nothing');

      expect(result.submissions, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test(
        'marks the result truncated when the merged union exceeds the cap '
        'although no branch was cut off', () async {
      final server = _SearchServer();
      // Two branches well under the +1 branch bound whose union is over the
      // final cap: the union was capped, so the search was not complete.
      server.rows['file'] = [
        for (var i = 1; i <= 30; i++)
          _docRow(
            'doc-file-$i',
            '2026-10-01T01:00:${i.toString().padLeft(2, '0')}+00:00',
          ),
      ];
      server.rows['uploader'] = [
        for (var i = 1; i <= 25; i++)
          _docRow(
            'doc-uploader-$i',
            '2026-10-01T02:00:${i.toString().padLeft(2, '0')}+00:00',
            fileName: 'staff-$i.pdf',
          ),
      ];
      final repo = ReceptionRepository(client: useServer(server));

      final result = await repo.searchSubmissions('qa129');

      expect(result.submissions, hasLength(searchResultLimit));
      expect(result.hasMore, isTrue);
      expect(result.limit, searchResultLimit);
      // Newest first: the uploader branch's rows are the newest.
      expect(result.submissions.first.id, 'doc-uploader-25');
    });

    test(
        'fails the whole search when one branch fails, instead of answering '
        'with the rest', () async {
      final server = _SearchServer();
      server.rows['file'] = [
        _docRow('doc-1', '2026-10-01T00:00:00+00:00'),
      ];
      server.failBranch = 'uploader';
      final repo = ReceptionRepository(client: useServer(server));

      // A partial answer would look complete to the caller; a failure must
      // never degrade into "fewer matches" or "no matches".
      await expectLater(
        repo.searchSubmissions('qa129'),
        throwsA(isA<Failure>()),
      );
      expect(server.requests, hasLength(3));
    });

    test(
        'rejects an empty or over-long term without reaching the server, '
        'with web\'s message', () async {
      final server = _SearchServer();
      final repo = ReceptionRepository(client: useServer(server));

      const message = 'Search term must be between 1 and 100 characters.';
      for (final bad in ['', '   ', 'x' * (maxSearchTermLength + 1)]) {
        await expectLater(
          repo.searchSubmissions(bad),
          throwsA(isA<ValidationFailure>()
              .having((e) => e.message, 'message', message)),
        );
      }
      expect(server.requests, isEmpty);

      // The longest accepted term still searches.
      await repo.searchSubmissions('x' * maxSearchTermLength);
      expect(server.requests, hasLength(3));
    });
  });

  // ─── The search state ─────────────────────────────────────────────────────

  test('a late answer for an older query never overwrites the newest one',
      () async {
    final repo = _QueuedSearchRepository(client: Supabase.instance.client);
    final provider = ReceptionQueueProvider(repository: repo);

    provider.onSearchChanged('old');
    await Future<void>.delayed(
        ReceptionQueueProvider.searchDebounce +
            const Duration(milliseconds: 20));
    expect(repo.pending, hasLength(1));

    provider.onSearchChanged('new');
    await Future<void>.delayed(
        ReceptionQueueProvider.searchDebounce +
            const Duration(milliseconds: 20));
    expect(repo.pending, hasLength(2));

    // The newest query answers first.
    repo.pending[1].complete(SearchResult(
      submissions: [_submission('new-doc', 'New Patient')],
      hasMore: false,
      limit: searchResultLimit,
    ));
    await pumpEventQueue();
    expect(provider.searchPhase, SearchPhase.ok);
    expect(provider.searchResults.single.id, 'new-doc');

    // The older query answers afterwards: its answer describes a query the
    // user is no longer looking at and must be dropped.
    repo.pending[0].complete(SearchResult(
      submissions: [_submission('old-doc', 'Old Patient')],
      hasMore: false,
      limit: searchResultLimit,
    ));
    await pumpEventQueue();
    expect(provider.searchPhase, SearchPhase.ok);
    expect(provider.searchResults.single.id, 'new-doc');
    provider.dispose();
  });

  // ─── The board screen ─────────────────────────────────────────────────────

  group('the reception board search', () {
    testWidgets(
        'searches the whole table on the server, and clearing restores the '
        'paged board', (tester) async {
      final repo = _BoardRepository(
        client: Supabase.instance.client,
        paged: [
          _submission('doc-1', 'Paged One'),
          _submission('doc-2', 'Paged Two'),
          _submission('doc-3', 'Paged Three'),
        ],
      );
      repo.matches = [_submission('doc-9', 'Matched Patient')];
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(_app(provider));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      // The paged board before any search.
      expect(find.text('Showing 3 of 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'matched');
      await tester.pump();

      // While the debounce runs the board is replaced by the search state —
      // never by a client-side filter of the loaded page.
      expect(find.text('Searching all records…'), findsOneWidget);
      expect(find.text('Showing 3 of 3'), findsNothing);

      await tester.pump(ReceptionQueueProvider.searchDebounce);
      await tester.pump();
      await tester.pump();

      // The server, not the loaded page, answered.
      expect(repo.searchCalls, 1);
      expect(repo.lastQuery, 'matched');
      expect(find.text('1 match across all records'), findsOneWidget);
      expect(find.text('Matched Patient'), findsOneWidget);
      expect(find.text('Pending (1)'), findsOneWidget);
      // The paged rows are not part of the answer.
      expect(find.text('Paged One'), findsNothing);

      // Clearing the box returns to the untouched paged board.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Showing 3 of 3'), findsOneWidget);
      expect(find.text('Paged One'), findsOneWidget);
      expect(find.text('Matched Patient'), findsNothing);
      expect(find.text('1 match across all records'), findsNothing);
      expect(find.byKey(const Key('search_truncated_notice')), findsNothing);
    });

    testWidgets(
        'a failed search shows the failure and a retry, never "no matches"',
        (tester) async {
      final repo = _BoardRepository(
        client: Supabase.instance.client,
        paged: [_submission('doc-1', 'Paged One')],
      );
      repo.matches = [_submission('doc-9', 'Matched Patient')];
      repo.failuresLeft = 1;
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(_app(provider));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      await _search(tester, 'matched');

      // A failed search is not an empty search.
      expect(find.text('Search unavailable'), findsOneWidget);
      expect(find.text('The document search could not be loaded.'),
          findsOneWidget);
      expect(find.text('database did not answer'), findsOneWidget);
      expect(
        find.text('No documents match “matched” across all records.'),
        findsNothing,
      );
      expect(find.byKey(const Key('btn_retry_search')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_retry_search')));
      await tester.pump();
      await tester.pump();

      // The retry ran the same query again and the failure cleared.
      expect(repo.searchCalls, 2);
      expect(repo.lastQuery, 'matched');
      expect(find.text('1 match across all records'), findsOneWidget);
      expect(find.text('Matched Patient'), findsOneWidget);
      expect(
          find.text('The document search could not be loaded.'), findsNothing);
    });

    testWidgets('a capped search discloses that only the first 50 are shown',
        (tester) async {
      final repo = _BoardRepository(
        client: Supabase.instance.client,
        paged: [_submission('doc-1', 'Paged One')],
      );
      repo.matches = [
        for (var i = 0; i < searchResultLimit; i++)
          _submission('doc-$i', 'Match $i'),
      ];
      repo.hasMore = true;
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(_app(provider));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      await _search(tester, 'match');

      expect(find.text('50 matches across all records'), findsOneWidget);
      expect(find.byKey(const Key('search_truncated_notice')), findsOneWidget);
      expect(find.textContaining('showing the first 50'), findsOneWidget);
      expect(
        find.textContaining(
            'There are more matches for “match” than can be shown'),
        findsOneWidget,
      );
    });

    testWidgets('an empty search says so, distinctly from a failed one',
        (tester) async {
      final repo = _BoardRepository(
        client: Supabase.instance.client,
        paged: [_submission('doc-1', 'Paged One')],
      );
      final provider = ReceptionQueueProvider(repository: repo);

      await tester.pumpWidget(_app(provider));
      await tester.runAsync(() => provider.loadSubmissions());
      await tester.pumpAndSettle();

      await _search(tester, 'nothing');

      expect(
        find.text('No documents match “nothing” across all records.'),
        findsOneWidget,
      );
      expect(find.text('0 matches across all records'), findsOneWidget);
      expect(find.text('The document search could not be loaded.'),
          findsNothing);
      expect(find.text('Searching all records…'), findsNothing);
    });
  });
}
