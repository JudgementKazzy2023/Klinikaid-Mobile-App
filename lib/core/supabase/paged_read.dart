import 'package:supabase_flutter/supabase_flutter.dart';

/// Rows requested per page when walking a PostgREST result set.
///
/// PostgREST answers a single request with at most `max-rows` rows (1,000 on
/// KlinikAid) and says nothing when it drops the rest, so an unpaginated read
/// silently truncates: every row past the cap is unreachable and every count
/// derived from it is wrong.
const int kPagedReadPageSize = 1000;

/// Upper bound on the number of page requests one read may make, so a server
/// that ignores the requested range cannot spin the read forever.
const int kPagedReadMaxPages = 1000;

/// The rows a filter matched, plus the exact number of rows the server counted.
class PagedReadResult {
  const PagedReadResult({required this.rows, required this.total});

  /// Every row the filter matched.
  final List<Map<String, dynamic>> rows;

  /// The server's exact count for the same filter, independent of the page size.
  final int total;

  /// True when the server counted more rows than were read back.
  bool get truncated => rows.length < total;
}

/// One page of a paged read, plus the exact number of rows the filter matched.
class PagedPageResult {
  const PagedPageResult({required this.rows, required this.total});

  /// The rows of this page.
  final List<Map<String, dynamic>> rows;

  /// The server's exact count for the same filter, independent of the page size.
  final int total;
}

/// Reads one page of a result set and the exact number of rows its filter matched.
///
/// The page is read with a range, so the server answers with the rows of that
/// range only. The order is the caller's sort plus [uniqueOrderColumn], the
/// primary key that makes the sort a total order: two rows that share a sort
/// value keep a fixed place in the order, so a page boundary cannot skip or
/// repeat one of them.
///
/// The exact count is asked for with the first page only. The count costs the
/// server a full scan and the number does not change between the pages of one
/// read, so a later page keeps the total of the first one instead of paying for
/// a second count.
Future<PagedPageResult> readPage(
  PostgrestTransformBuilder<PostgrestList> query, {
  required String uniqueOrderColumn,
  required int offset,
  bool uniqueOrderAscending = false,
  int pageSize = kPagedReadPageSize,
}) async {
  assert(
    uniqueOrderColumn.trim().isNotEmpty,
    'readPage needs the unique tiebreaker column (the table primary key).',
  );
  assert(offset >= 0, 'readPage needs a non-negative offset.');

  // The tiebreaker turns the caller's sort into a total order.
  final ordered = query.order(uniqueOrderColumn, ascending: uniqueOrderAscending);

  final List<Map<String, dynamic>> rows;
  final int total;
  if (offset == 0) {
    final response = await ordered
        .range(offset, offset + pageSize - 1)
        .count(CountOption.exact);
    rows = response.data;
    total = response.count;
  } else {
    rows = await ordered.range(offset, offset + pageSize - 1);
    total = 0;
  }

  return PagedPageResult(rows: rows, total: total);
}

/// Reads every row a filter matches, one page at a time.
///
/// [query] is a PostgREST builder with the filters already applied and with
/// the sort columns the caller wants already attached. [uniqueOrderColumn]
/// names the column that makes that sort a total order - the table's primary
/// key - and is appended to the order here.
///
/// The tiebreaker is mandatory, not a nicety. Two rows that share a sort value
/// have no fixed place in the order, so the server may return them in a
/// different order for two requests; a page boundary that falls inside such a
/// group then skips rows and repeats others, which is the defect this read
/// exists to prevent. The unique column gives every row a fixed place, so
/// every row is read exactly once.
///
/// Only the first page asks the server for the exact count: the count costs
/// the server a full scan and the number does not change between the pages of
/// one read. The total is therefore the server's answer for the moment of the
/// first page; a concurrent insert can make it stale before the last page
/// arrives.
Future<PagedReadResult> readAllPages(
  PostgrestTransformBuilder<PostgrestList> query, {
  required String uniqueOrderColumn,
  bool uniqueOrderAscending = false,
  int pageSize = kPagedReadPageSize,
}) async {
  assert(
    uniqueOrderColumn.trim().isNotEmpty,
    'readAllPages needs the unique tiebreaker column (the table primary key).',
  );

  // The tiebreaker turns the caller's sort into a total order.
  final ordered =
      query.order(uniqueOrderColumn, ascending: uniqueOrderAscending);

  final rows = <Map<String, dynamic>>[];
  var total = 0;
  var offset = 0;

  for (var page = 0; page < kPagedReadMaxPages; page++) {
    final List<Map<String, dynamic>> pageRows;
    final int pageTotal;
    try {
      if (page == 0) {
        final response = await ordered
            .range(offset, offset + pageSize - 1)
            .count(CountOption.exact);
        pageRows = response.data;
        pageTotal = response.count;
      } else {
        // Only the first page asks for the count: it is the expensive part of
        // the read and the answer does not change between the pages.
        pageRows = await ordered.range(offset, offset + pageSize - 1);
        pageTotal = total;
      }
    } on PostgrestException catch (e) {
      // PostgREST answers 416/PGRST103 when the requested offset is past the
      // last row. That is the end of the data, not a server fault.
      if (e.code == 'PGRST103') break;
      rethrow;
    }

    if (pageRows.isEmpty) break;
    rows.addAll(pageRows);
    if (page == 0) total = pageTotal;
    if (rows.length >= total) break;

    // Advance by the rows the server actually returned: a server whose
    // max-rows is smaller than [pageSize] answers with a short page.
    offset += pageRows.length;
  }

  return PagedReadResult(rows: rows, total: total);
}
