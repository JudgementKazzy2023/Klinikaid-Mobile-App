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

/// Reads every row a filter matches, one page at a time.
///
/// [query] is a PostgREST builder with the filters already applied. Each page
/// is requested with an explicit range together with the server's exact count
/// for the same filter, so the caller can report the true total instead of the
/// number of rows that happened to fit in one response.
Future<PagedReadResult> readAllPages(
  PostgrestTransformBuilder<PostgrestList> query, {
  int pageSize = kPagedReadPageSize,
}) async {
  final rows = <Map<String, dynamic>>[];
  var total = 0;
  var offset = 0;

  for (var page = 0; page < kPagedReadMaxPages; page++) {
    final PostgrestResponse<PostgrestList> response;
    try {
      response =
          await query.range(offset, offset + pageSize - 1).count(CountOption.exact);
    } on PostgrestException catch (e) {
      // PostgREST answers 416/PGRST103 when the requested offset is past the
      // last row. That is the end of the data, not a server fault.
      if (e.code == 'PGRST103') break;
      rethrow;
    }

    final pageRows = response.data;
    if (pageRows.isEmpty) break;

    rows.addAll(pageRows);
    total = response.count;
    if (rows.length >= total) break;

    // Advance by the rows the server actually returned: a server whose
    // max-rows is smaller than [pageSize] answers with a short page.
    offset += pageRows.length;
  }

  return PagedReadResult(rows: rows, total: total);
}
