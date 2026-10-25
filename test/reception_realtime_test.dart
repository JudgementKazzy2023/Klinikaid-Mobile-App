import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/reception_search.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';

/// A reception repository over an in-memory `documents` table.
///
/// The Realtime channel is replaced by its event stream: a test fires
/// [changes] the way the channel would, and the provider re-reads through the
/// overridden reads. No socket and no HTTP request is involved.
class _LiveReceptionRepository extends ReceptionRepository {
  _LiveReceptionRepository()
      : super(
          client: SupabaseClient(
            'https://example.invalid',
            'fake-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient((_) async => http.Response('', 500)),
          ),
        );

  /// The rows of the table, newest first.
  final List<Submission> table = <Submission>[];

  /// The change events. Single-subscription, like the channel's stream, so a
  /// second listener is an error and [StreamController.hasListener] shows
  /// whether the provider is subscribed.
  final StreamController<void> changes = StreamController<void>();

  int boardReads = 0;
  final List<int> boardLimits = <int>[];
  bool boardFails = false;

  int searchCalls = 0;
  bool holdSearches = false;
  final List<Completer<SearchResult>> heldSearches = <Completer<SearchResult>>[];

  void insertNewest(Submission submission) => table.insert(0, submission);

  void setStatus(String id, SubmissionStatus status) {
    final index = table.indexWhere((s) => s.id == id);
    final old = table[index];
    table[index] = _doc(old.id, status: status, fileName: old.fileName);
  }

  void remove(String id) => table.removeWhere((s) => s.id == id);

  @override
  Stream<void> documentChanges() => changes.stream;

  @override
  Future<SubmissionsPage> getSubmissionsPage({
    SubmissionStatus? status,
    int offset = 0,
    int limit = kReceptionSubmissionsPageSize,
  }) async {
    boardReads++;
    boardLimits.add(limit);
    if (boardFails) throw const DatabaseFailure('board read failed');
    final matching = table.where((s) => s.status == status).toList();
    return SubmissionsPage(
      submissions: matching.skip(offset).take(limit).toList(),
      total: matching.length,
    );
  }

  @override
  Future<SearchResult> searchSubmissions(String rawQuery) {
    searchCalls++;
    if (!holdSearches) return Future.value(_answer(rawQuery));
    final answer = Completer<SearchResult>();
    heldSearches.add(answer);
    return answer.future;
  }

  /// The table's rows whose file name contains [query], newest first.
  SearchResult _answer(String query) {
    final matches = table
        .where((s) => s.fileName.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SearchResult(
      submissions: matches,
      hasMore: false,
      limit: searchResultLimit,
    );
  }
}

Submission _doc(
  String id, {
  SubmissionStatus status = SubmissionStatus.submitted,
  String? fileName,
}) =>
    Submission(
      id: id,
      patientId: 'patient-$id',
      patientName: 'Patient $id',
      fileName: fileName ?? '$id.pdf',
      fileType: 'pdf',
      uploadedAt: DateTime.utc(2026, 1, 1),
      uploadedBy: 'Reception On Duty',
      status: status,
    );

/// Waits past the live-refresh debounce, so a scheduled re-read has run.
Future<void> _pastLiveDebounce() => Future<void>.delayed(
      ReceptionQueueProvider.liveRefreshDebounce +
          const Duration(milliseconds: 50),
    );

/// Waits past the search debounce, so a typed query has been sent.
Future<void> _pastSearchDebounce() => Future<void>.delayed(
      ReceptionQueueProvider.searchDebounce + const Duration(milliseconds: 50),
    );

/// A board showing [repo]'s table, live.
Future<ReceptionQueueProvider> _openLiveBoard(
  _LiveReceptionRepository repo,
) async {
  final provider = ReceptionQueueProvider(repository: repo)
    ..startLiveUpdates();
  await provider.loadSubmissions();
  return provider;
}

SearchResult _resultOf(List<Submission> submissions) => SearchResult(
      submissions: submissions,
      hasMore: false,
      limit: searchResultLimit,
    );

void main() {
  group('reception board follows document changes', () {
    test('a new pending document appears in its column and count', () async {
      final repo = _LiveReceptionRepository()..insertNewest(_doc('old'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);
      expect(provider.pendingTotal, 1);

      repo.insertNewest(_doc('new'));
      repo.changes.add(null);
      await _pastLiveDebounce();

      expect(provider.pendingSubmissions.map((s) => s.id), ['new', 'old']);
      expect(provider.pendingTotal, 2);
    });

    test('an approval moves the document from Pending to Approved', () async {
      final repo = _LiveReceptionRepository()
        ..insertNewest(_doc('b'))
        ..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      repo.setStatus('a', SubmissionStatus.approved);
      repo.changes.add(null);
      await _pastLiveDebounce();

      expect(provider.pendingSubmissions.map((s) => s.id), ['b']);
      expect(provider.pendingTotal, 1);
      expect(provider.approvedSubmissions.map((s) => s.id), ['a']);
      expect(provider.approvedTotal, 1);
    });

    test('a delete removes the row and lowers its column count', () async {
      final repo = _LiveReceptionRepository()
        ..insertNewest(_doc('b'))
        ..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      // A DELETE event carries only the primary key; the re-read is what
      // drops the row, so the provider needs nothing from the payload.
      repo.remove('a');
      repo.changes.add(null);
      await _pastLiveDebounce();

      expect(provider.pendingSubmissions.map((s) => s.id), ['b']);
      expect(provider.pendingTotal, 1);
    });

    test('a burst of changes re-reads the board once, after it settles',
        () async {
      final repo = _LiveReceptionRepository()..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);
      final readsBefore = repo.boardReads;

      for (var i = 0; i < 5; i++) {
        repo.insertNewest(_doc('burst-$i'));
        repo.changes.add(null);
      }

      // Still inside the debounce window: nothing has been re-read yet.
      await Future<void>.delayed(
        ReceptionQueueProvider.liveRefreshDebounce ~/ 2,
      );
      expect(repo.boardReads, readsBefore);

      await _pastLiveDebounce();
      // One re-read is one read per column, not one per event.
      expect(repo.boardReads - readsBefore, 3);
      expect(provider.pendingTotal, 6);
    });

    test('a re-read keeps the rows the reader has loaded', () async {
      final repo = _LiveReceptionRepository();
      for (var i = 0; i < 150; i++) {
        repo.table.add(_doc('p$i'));
      }
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);
      await provider.loadMore(SubmissionStatus.submitted);
      expect(provider.submissionsOf(SubmissionStatus.submitted), hasLength(150));

      repo.insertNewest(_doc('fresh'));
      repo.changes.add(null);
      await _pastLiveDebounce();

      // The reader's 150 rows are read back; the new row is counted, and the
      // column says one more row is past what is on screen.
      expect(
        provider.submissionsOf(SubmissionStatus.submitted),
        hasLength(150),
      );
      expect(provider.pendingTotal, 151);
      expect(provider.hasMoreOf(SubmissionStatus.submitted), isTrue);
      expect(repo.boardLimits.sublist(repo.boardLimits.length - 3), [
        150,
        kReceptionSubmissionsPageSize,
        kReceptionSubmissionsPageSize,
      ]);
    });

    test('a failed re-read is shown as a board error, not as current rows',
        () async {
      final repo = _LiveReceptionRepository()..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);
      expect(provider.boardError, isNull);

      repo.boardFails = true;
      repo.changes.add(null);
      await _pastLiveDebounce();

      expect(provider.boardError, 'board read failed');
      expect(provider.isLoading, isFalse);
    });
  });

  group('an open search follows document changes', () {
    test('the search re-runs once per burst with the same query', () async {
      final repo = _LiveReceptionRepository()
        ..insertNewest(_doc('r1', fileName: 'report-1.pdf'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      provider.onSearchChanged('report');
      await _pastSearchDebounce();
      expect(repo.searchCalls, 1);
      expect(provider.searchResults.map((s) => s.id), ['r1']);

      for (var i = 0; i < 4; i++) {
        repo.insertNewest(_doc('r-burst-$i', fileName: 'report-burst-$i.pdf'));
        repo.changes.add(null);
      }
      await _pastLiveDebounce();

      expect(repo.searchCalls, 2);
      expect(provider.searchQuery, 'report');
      expect(provider.searchResults, hasLength(5));
    });

    test('no search is sent when no search is open', () async {
      final repo = _LiveReceptionRepository()..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      repo.changes.add(null);
      await _pastLiveDebounce();

      expect(repo.searchCalls, 0);
      expect(provider.isSearching, isFalse);
    });

    test('a re-run keeps the answer on screen until the new one arrives',
        () async {
      final repo = _LiveReceptionRepository()
        ..insertNewest(_doc('old', fileName: 'report-old.pdf'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      provider.onSearchChanged('report');
      await _pastSearchDebounce();
      expect(provider.searchPhase, SearchPhase.ok);

      repo.holdSearches = true;
      repo.changes.add(null);
      await _pastLiveDebounce();

      // The re-run is in flight, but the list is not replaced by a spinner.
      expect(repo.heldSearches, hasLength(1));
      expect(provider.searchPhase, SearchPhase.ok);
      expect(provider.searchResults.map((s) => s.id), ['old']);

      repo.heldSearches.single.complete(_resultOf([
        _doc('new', fileName: 'report-new.pdf'),
      ]));
      await pumpEventQueue();
      expect(provider.searchResults.map((s) => s.id), ['new']);
    });

    test('an answer from before a change never replaces the newer one',
        () async {
      final repo = _LiveReceptionRepository();
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      addTearDown(provider.dispose);

      repo.holdSearches = true;
      provider.onSearchChanged('report');
      await _pastSearchDebounce();
      expect(repo.heldSearches, hasLength(1));

      repo.changes.add(null);
      await _pastLiveDebounce();
      expect(repo.heldSearches, hasLength(2));

      // The re-run answers first; the search sent before the change answers
      // afterwards with rows the change has already superseded.
      repo.heldSearches[1].complete(_resultOf([
        _doc('newer', fileName: 'report-newer.pdf'),
      ]));
      await pumpEventQueue();
      expect(provider.searchResults.map((s) => s.id), ['newer']);

      repo.heldSearches[0].complete(_resultOf([
        _doc('older', fileName: 'report-older.pdf'),
      ]));
      await pumpEventQueue();
      expect(provider.searchResults.map((s) => s.id), ['newer']);
      expect(provider.searchPhase, SearchPhase.ok);
    });
  });

  group('the live subscription', () {
    test('starts once and is cancelled by dispose', () async {
      final repo = _LiveReceptionRepository();
      addTearDown(repo.changes.close);
      final provider = ReceptionQueueProvider(repository: repo);

      provider.startLiveUpdates();
      // A second start must not listen again: the stream allows one listener.
      provider.startLiveUpdates();
      expect(repo.changes.hasListener, isTrue);

      provider.dispose();
      expect(repo.changes.hasListener, isFalse);
    });

    test('nothing is re-read after dispose, even for a change already fired',
        () async {
      final repo = _LiveReceptionRepository()..insertNewest(_doc('a'));
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      final readsBefore = repo.boardReads;

      repo.changes.add(null);
      provider.dispose();
      await _pastLiveDebounce();

      expect(repo.boardReads, readsBefore);
    });

    test('a search answer that lands after dispose is ignored', () async {
      final repo = _LiveReceptionRepository();
      addTearDown(repo.changes.close);
      final provider = await _openLiveBoard(repo);
      repo.holdSearches = true;

      provider.onSearchChanged('report');
      await _pastSearchDebounce();
      provider.dispose();

      expect(
        () => repo.heldSearches.single.complete(_resultOf(const [])),
        returnsNormally,
      );
      await pumpEventQueue();
    });
  });
}
