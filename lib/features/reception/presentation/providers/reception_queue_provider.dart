import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/reception_repository.dart';
import '../../domain/reception_search.dart';
import '../../domain/submission.dart';
import '../../domain/submission_detail.dart';
import '../../domain/submission_status.dart';

/// What a whole-table search can be.
///
/// There is no member that means "searched and found nothing" and no member
/// that means "searched and failed": those are two different claims, and the
/// board renders them as two different states — exactly web's SearchState.
enum SearchPhase { idle, loading, ok, failed }

/// One column of the reception board: the rows on screen and the server's
/// exact count for that column.
class SubmissionColumn {
  const SubmissionColumn({required this.rows, required this.total});

  /// The submissions on screen, newest first.
  final List<Submission> rows;

  /// The exact number of submissions the server holds for this column.
  final int total;

  /// True when the server holds more submissions than are on screen.
  bool get hasMore => rows.length < total;
}

class ReceptionQueueProvider extends ChangeNotifier {
  final ReceptionRepository _repository;

  ReceptionQueueProvider({required ReceptionRepository repository})
      : _repository = repository;

  /// The columns of the board, one per status.
  ///
  /// The board reads one status at a time: every column is a work list of its
  /// own, and a mixed page would leave a column empty while that column holds
  /// rows.
  static const List<SubmissionStatus> boardStatuses = <SubmissionStatus>[
    SubmissionStatus.submitted,
    SubmissionStatus.approved,
    SubmissionStatus.rejected,
  ];

  final Map<SubmissionStatus, SubmissionColumn> _columns =
      <SubmissionStatus, SubmissionColumn>{
    for (final status in boardStatuses)
      status: const SubmissionColumn(rows: <Submission>[], total: 0),
  };

  /// The columns whose next page is being read.
  final Map<SubmissionStatus, bool> _loadingMore = <SubmissionStatus, bool>{
    for (final status in boardStatuses) status: false,
  };

  /// The failure of the last "load more" of a column.
  final Map<SubmissionStatus, String?> _moreErrors = <SubmissionStatus, String?>{
    for (final status in boardStatuses) status: null,
  };

  bool _isLoading = false;
  String? _errorMessage;
  String? _boardError;
  SubmissionDetail? _selectedDetail;

  /// Delay before a search query is sent, to avoid a request per keystroke
  /// (web's SEARCH_DEBOUNCE_MS).
  static const Duration searchDebounce = Duration(milliseconds: 300);

  SearchPhase _searchPhase = SearchPhase.idle;
  List<Submission> _searchResults = const [];
  bool _searchHasMore = false;
  int _searchLimit = searchResultLimit;
  String _searchError = '';

  /// The trimmed query the current search state describes.
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// Each search takes a ticket; only the newest may write its result.
  ///
  /// Without this, a slow response to an older query would overwrite the
  /// answer for the query the user is actually looking at (web's searchSeq).
  int _searchSeq = 0;

  /// Set when the provider is disposed, so an in-flight search that resolves
  /// afterwards reports nothing to a listener that no longer exists.
  bool _disposed = false;

  bool _isRouting = false;
  String? _routingError;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// The failure of the board read, if it failed.
  ///
  /// The board has its own failure: a detail read that fails says nothing
  /// about the board, and the board must not go blank because one document
  /// could not be opened.
  String? get boardError => _boardError;

  SubmissionDetail? get selectedDetail => _selectedDetail;
  bool get isRouting => _isRouting;
  String? get routingError => _routingError;

  /// What the current search is: idle, loading, ok or failed.
  SearchPhase get searchPhase => _searchPhase;

  /// True while a query is being searched for (the board is then replaced by
  /// the search states, never by a client-side filter of the loaded page).
  bool get isSearching => _searchPhase != SearchPhase.idle;

  /// The whole-table matches of the last successful search, newest first.
  List<Submission> get searchResults => _searchResults;

  /// True when the search matched more documents than [searchResults] holds.
  bool get searchHasMore => _searchHasMore;

  /// The most submissions one search may report.
  int get searchLimit => _searchLimit;

  /// The failure of the last search, as shown to reception.
  String get searchError => _searchError;

  /// The trimmed query the current search state describes.
  String get searchQuery => _searchQuery;

  /// The board's search field changed.
  ///
  /// The trimmed query decides everything: an empty query is idle (the paged
  /// board shows), a non-empty one is loading at once and reaches the server
  /// after [searchDebounce]. Only a server search can answer for a non-empty
  /// query — the board's pages are capped, so a client-side filter could read
  /// "no match" for rows that were never loaded.
  void onSearchChanged(String raw) {
    final query = raw.trim();
    _searchDebounce?.cancel();
    _searchSeq++;

    if (query.isEmpty) {
      _searchPhase = SearchPhase.idle;
      _searchQuery = '';
      _searchResults = const [];
      _searchHasMore = false;
      _searchError = '';
      notifyListeners();
      return;
    }

    _searchQuery = query;
    _searchResults = const [];
    _searchHasMore = false;
    _searchError = '';
    _searchPhase = SearchPhase.loading;
    notifyListeners();
    _searchDebounce = Timer(searchDebounce, () => _runSearch(query));
  }

  /// Re-runs the current search after a failure.
  void retrySearch() {
    final query = _searchQuery;
    if (query.isEmpty) return;
    _searchDebounce?.cancel();
    _runSearch(query);
  }

  Future<void> _runSearch(String query) async {
    final ticket = ++_searchSeq;
    _searchPhase = SearchPhase.loading;
    _searchError = '';
    notifyListeners();

    try {
      final result = await _repository.searchSubmissions(query);
      // A newer query owns the screen; a disposed provider owns nothing.
      if (ticket != _searchSeq || _disposed) return;
      _searchResults = result.submissions;
      _searchHasMore = result.hasMore;
      _searchLimit = result.limit;
      _searchPhase = SearchPhase.ok;
      notifyListeners();
    } catch (e) {
      if (ticket != _searchSeq || _disposed) return;
      // A failed search is not an empty search: the state says so plainly.
      _searchResults = const [];
      _searchHasMore = false;
      _searchError = e.toString();
      _searchPhase = SearchPhase.failed;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// The submissions of one board column, newest first.
  List<Submission> submissionsOf(SubmissionStatus status) =>
      _columns[status]!.rows;

  /// The exact number of submissions the server holds for one column.
  int totalOf(SubmissionStatus status) => _columns[status]!.total;

  /// True when the column holds more submissions than are on screen.
  bool hasMoreOf(SubmissionStatus status) => _columns[status]!.hasMore;

  /// True while the next page of the column is being read.
  bool isLoadingMoreOf(SubmissionStatus status) => _loadingMore[status]!;

  /// The failure of the last "load more" of the column, if it failed.
  String? moreErrorOf(SubmissionStatus status) => _moreErrors[status];

  List<Submission> get pendingSubmissions =>
      submissionsOf(SubmissionStatus.submitted);

  List<Submission> get submittedSubmissions =>
      submissionsOf(SubmissionStatus.submitted);

  List<Submission> get approvedSubmissions =>
      submissionsOf(SubmissionStatus.approved);

  List<Submission> get rejectedSubmissions =>
      submissionsOf(SubmissionStatus.rejected);

  /// The exact number of pending submissions the server holds.
  int get pendingTotal => totalOf(SubmissionStatus.submitted);

  /// The exact number of approved submissions the server holds.
  int get approvedTotal => totalOf(SubmissionStatus.approved);

  /// The exact number of rejected submissions the server holds.
  int get rejectedTotal => totalOf(SubmissionStatus.rejected);

  /// Loads the first page of every board column.
  ///
  /// Each column is read on its own, so every count on the board is the
  /// server's exact count for that column and not the size of one page.
  Future<void> loadSubmissions() async {
    _isLoading = true;
    _boardError = null;
    notifyListeners();

    try {
      final pages = await Future.wait(<Future<SubmissionsPage>>[
        for (final status in boardStatuses)
          _repository.getSubmissionsPage(status: status),
      ]);

      for (var index = 0; index < boardStatuses.length; index++) {
        final status = boardStatuses[index];
        final page = pages[index];
        _columns[status] = SubmissionColumn(
          rows: page.submissions,
          total: page.total,
        );
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _boardError = e.toString();
      notifyListeners();
    }
  }

  /// Appends the next page of one board column.
  ///
  /// The page continues where the last one stopped, so no submission is
  /// skipped and none is read twice. The rows that are on screen stay when the
  /// read fails, and the failure is shown next to the button.
  Future<void> loadMore(SubmissionStatus status) async {
    if (_loadingMore[status] == true) return;
    final column = _columns[status]!;
    if (!column.hasMore) return;

    _loadingMore[status] = true;
    _moreErrors[status] = null;
    notifyListeners();

    try {
      final page = await _repository.getSubmissionsPage(
        status: status,
        offset: column.rows.length,
      );
      _columns[status] = SubmissionColumn(
        rows: <Submission>[...column.rows, ...page.submissions],
        total: column.total,
      );
    } catch (e) {
      _moreErrors[status] = e.toString();
    } finally {
      _loadingMore[status] = false;
      notifyListeners();
    }
  }

  /// Loads the details of a single document submission.
  Future<SubmissionDetail?> loadSubmissionDetail(String id) async {
    _isLoading = true;
    _errorMessage = null;
    _selectedDetail = null;
    notifyListeners();

    try {
      _selectedDetail = await _repository.getSubmissionDetail(id);
      _isLoading = false;
      notifyListeners();
      return _selectedDetail;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Fetches a signed storage URL for a document.
  Future<String> getOriginalDocumentUrl(String id) async {
    return await _repository.getOriginalDocumentUrl(id);
  }

  /// Approves a document and routes the patient to a department.
  /// On success, refreshes the queue so Pending −1, Approved +1 without
  /// requiring a manual pull-to-refresh.
  /// Returns true on success, false on failure (error available via [routingError]).
  Future<bool> approveAndRoute({
    required String documentId,
    required String patientId,
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) async {
    _isRouting = true;
    _routingError = null;
    notifyListeners();

    try {
      await _repository.approveAndRoute(
        documentId: documentId,
        patientId: patientId,
        department: department,
        priority: priority,
        bloodPressure: bloodPressure,
        weightKg: weightKg,
        temperatureC: temperatureC,
        triageNotes: triageNotes,
      );
      _isRouting = false;
      notifyListeners();
      // Refresh queue so Pending −1, Approved +1 automatically.
      await loadSubmissions();
      return true;
    } catch (e) {
      _isRouting = false;
      _routingError = e.toString();
      notifyListeners();
      return false;
    }
  }

  bool _isRejecting = false;
  String? _rejectError;

  bool get isRejecting => _isRejecting;
  String? get rejectError => _rejectError;

  /// Rejects a document and records the reason.
  /// On success, refreshes the queue lists automatically.
  /// Returns true on success, false on failure (error available via [rejectError]).
  Future<bool> rejectDocument({
    required String documentId,
    required String reason,
  }) async {
    _isRejecting = true;
    _rejectError = null;
    notifyListeners();

    try {
      await _repository.rejectDocument(
        documentId: documentId,
        reason: reason,
      );
      _isRejecting = false;
      notifyListeners();
      // Refresh queue lists so Pending -1, Rejected +1 automatically.
      await loadSubmissions();
      return true;
    } catch (e) {
      _isRejecting = false;
      _rejectError = e.toString();
      notifyListeners();
      return false;
    }
  }
}
