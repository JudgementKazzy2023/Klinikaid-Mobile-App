import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/reception_queue_provider.dart';
import '../widgets/submission_card.dart';
import '../../domain/submission_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ReceptionQueueScreen extends StatefulWidget {
  const ReceptionQueueScreen({super.key});

  @override
  State<ReceptionQueueScreen> createState() => _ReceptionQueueScreenState();
}

class _ReceptionQueueScreenState extends State<ReceptionQueueScreen> {
  final _searchController = TextEditingController();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  /// Every keystroke hands the raw text to the provider.
  ///
  /// The provider owns the search state (debounce, tickets, results): the box
  /// filters the WHOLE documents table on the server, never the capped page
  /// the board already loaded, so a client-side filter here could only answer
  /// "no match" for rows that were never read.
  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchText = _searchController.text;
    });
    Provider.of<ReceptionQueueProvider>(context, listen: false)
        .onSearchChanged(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildEmptyState(BuildContext context, String message, IconData icon) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The state of a board read that failed.
  ///
  /// A failed read is not an empty board: the empty state would tell reception
  /// that no document was ever uploaded while the read is broken.
  Widget _buildErrorState(
    BuildContext context,
    ReceptionQueueProvider provider,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'The submissions could not be loaded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.boardError ?? 'Unknown error.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('btn_retry_submissions'),
              onPressed: provider.loadSubmissions,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// The state of a search that failed.
  ///
  /// A failed search is not an empty search: "No documents match" would claim
  /// something about records the search never saw. The failure is shown with
  /// its reason (web shows the error message too) and a Retry that re-runs the
  /// same query.
  Widget _buildSearchErrorState(
    BuildContext context,
    ReceptionQueueProvider provider,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'The document search could not be loaded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.searchError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('btn_retry_search'),
              onPressed: provider.retrySearch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// The one-line summary of the active search (web's statusText beside the
  /// search box).
  ///
  /// While searching the server's whole table, "loaded" would be the wrong
  /// noun: the count on screen is the number of matches, not the size of a
  /// page. A failed search says so instead of pretending to a count.
  Widget _buildSearchStatus(ReceptionQueueProvider provider) {
    final String text;
    switch (provider.searchPhase) {
      case SearchPhase.idle:
        return const SizedBox.shrink();
      case SearchPhase.loading:
        text = 'Searching all records…';
      case SearchPhase.failed:
        text = 'Search unavailable';
      case SearchPhase.ok:
        final matches = provider.searchResults.length;
        text = '$matches match${matches == 1 ? '' : 'es'} across all records';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// The truncation disclosure of a capped search.
  ///
  /// The search is capped at [ReceptionQueueProvider.searchLimit] documents,
  /// so the rows on screen are not the full match set. That gap is stated
  /// instead of left for reception to infer: a list that looks complete while
  /// omitting matches is how a referral is never actioned. The state is only
  /// rendered when the search reported it — an uncapped search never claims a
  /// cap, and a capped one never claims completeness.
  Widget _buildTruncationNotice(
    BuildContext context,
    ReceptionQueueProvider provider,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        key: const Key('search_truncated_notice'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: Colors.amber.shade900,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'There are more matches for “${provider.searchQuery}” '
                'than can be shown — showing the first '
                '${provider.searchLimit}. Refine your search to see the rest.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabList(
    BuildContext context,
    SubmissionStatus status,
    String emptyMessage,
    IconData emptyIcon,
    ReceptionQueueProvider provider,
  ) {
    final loaded = provider.submissionsOf(status);
    final total = provider.totalOf(status);

    if (loaded.isEmpty && !provider.hasMoreOf(status)) {
      return RefreshIndicator(
        onRefresh: () => provider.loadSubmissions(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.5,
            alignment: Alignment.center,
            child: _buildEmptyState(context, emptyMessage, emptyIcon),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadSubmissions(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Showing ${loaded.length} of $total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: loaded.length,
              itemBuilder: (context, index) {
                final submission = loaded[index];
                return SubmissionCard(
                  submission: submission,
                  onTap: () {
                    context.go('/reception/document/${submission.id}');
                  },
                );
              },
            ),
          ),
          _buildLoadMore(context, status, provider),
        ],
      ),
    );
  }

  /// One tab's slice of the search results.
  ///
  /// The search spans the whole table including approved/rejected history, so
  /// a match in a completed column is shown rather than hidden behind the
  /// tab's usual scope. There is no "load more": the result set is the server's
  /// capped answer, and its cap is disclosed by the truncation notice.
  Widget _buildSearchList(
    BuildContext context,
    SubmissionStatus status,
    ReceptionQueueProvider provider,
  ) {
    final matches = provider.searchResults
        .where((submission) => submission.status == status)
        .toList();

    if (matches.isEmpty) {
      // Distinct from "No pending documents.": this column of the *match set*
      // is empty, not the queue itself.
      return _buildEmptyState(context, 'No matches', Icons.search_off_rounded);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final submission = matches[index];
        return SubmissionCard(
          submission: submission,
          onTap: () {
            context.go('/reception/document/${submission.id}');
          },
        );
      },
    );
  }

  /// The "load more" control of a board column.
  ///
  /// The columns are read page by page, so the column says how much of the
  /// server's count is on screen and offers the next page.
  Widget _buildLoadMore(
    BuildContext context,
    SubmissionStatus status,
    ReceptionQueueProvider provider,
  ) {
    final hasMore = provider.hasMoreOf(status);
    final error = provider.moreErrorOf(status);
    final loading = provider.isLoadingMoreOf(status);
    if (!hasMore && error == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
              ),
            ),
          FilledButton.icon(
            key: Key('btn_load_more_${status.name}'),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(loading ? 'Loading...' : 'Load more'),
            onPressed: loading ? null : () => provider.loadMore(status),
          ),
        ],
      ),
    );
  }

  /// The count of a board column, or null when the count is unknown.
  ///
  /// A count of zero would claim the column is empty. While the board is
  /// loading and after a failed read nobody could measure it, so the count is
  /// left out instead.
  int? _knownCount(ReceptionQueueProvider provider, int count) {
    if (provider.isLoading || provider.boardError != null) return null;
    return count;
  }

  /// The count a tab header shows.
  ///
  /// While searching, the column totals are the wrong number: the tab holds
  /// matches, not pages. While the search is loading or failed no match count
  /// exists at all, so the count is left out rather than shown as zero.
  int? _tabCount(ReceptionQueueProvider provider, SubmissionStatus status) {
    if (provider.isSearching) {
      if (provider.searchPhase != SearchPhase.ok) return null;
      return provider.searchResults
          .where((submission) => submission.status == status)
          .length;
    }
    return _knownCount(provider, provider.totalOf(status));
  }

  /// The header of a board column.
  ///
  /// The count is the server's exact count for the column. It is left out
  /// while the board is loading and after a failed read: a count of zero
  /// would claim the column is empty when nobody could measure it.
  Widget _buildTabHeader(String title, int? count, ThemeData theme) {
    return Tab(
      child: Text(
        count == null ? title : '$title ($count)',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// What sits under the tab bar: the search states while a search is active,
  /// otherwise the paged board.
  ///
  /// The two never mix: during a search the board's pages are not the answer
  /// to the query (they are a capped page of a different question), and a
  /// search that is loading, failed or empty must not render as an empty
  /// board.
  Widget _buildBoardBody(
    BuildContext context,
    ReceptionQueueProvider provider,
  ) {
    if (provider.isSearching) {
      switch (provider.searchPhase) {
        case SearchPhase.idle:
          // Unreachable: isSearching is false for idle.
          return const SizedBox.shrink();
        case SearchPhase.loading:
          return const Center(child: CircularProgressIndicator());
        case SearchPhase.failed:
          return _buildSearchErrorState(context, provider);
        case SearchPhase.ok:
          if (provider.searchResults.isEmpty && !provider.searchHasMore) {
            return _buildEmptyState(
              context,
              'No documents match “${provider.searchQuery}” '
              'across all records.',
              Icons.search_off_rounded,
            );
          }
          return TabBarView(
            children: [
              _buildSearchList(
                context,
                SubmissionStatus.submitted,
                provider,
              ),
              _buildSearchList(
                context,
                SubmissionStatus.approved,
                provider,
              ),
              _buildSearchList(
                context,
                SubmissionStatus.rejected,
                provider,
              ),
            ],
          );
      }
    }

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // A failed read is not an empty board: reception reading three empty
    // columns would conclude there are no referrals while every upload sits
    // unseen.
    if (provider.boardError != null) {
      return _buildErrorState(context, provider);
    }
    return TabBarView(
      children: [
        _buildTabList(
          context,
          SubmissionStatus.submitted,
          'No pending documents.',
          Icons.assignment_turned_in_outlined,
          provider,
        ),
        _buildTabList(
          context,
          SubmissionStatus.approved,
          'No approved documents.',
          Icons.check_circle_outline_rounded,
          provider,
        ),
        _buildTabList(
          context,
          SubmissionStatus.rejected,
          'No rejected documents.',
          Icons.highlight_off_rounded,
          provider,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<ReceptionQueueProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final searching = provider.isSearching;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Reception Queue'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authProvider.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar. An empty (or whitespace-only) box is idle and the
            // paged board shows again; a non-empty box searches the whole
            // table on the server after the provider's debounce.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search patient name, file name or type...',
                  prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                  suffixIcon: _searchText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                ),
              ),
            ),

            // Search status and notices, shown above the tab bar the way web
            // shows them above the board.
            if (searching) _buildSearchStatus(provider),
            if (searching &&
                provider.searchPhase == SearchPhase.ok &&
                provider.searchHasMore)
              _buildTruncationNotice(context, provider),

            // Tab Gating
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      indicatorColor: theme.colorScheme.primary,
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: [
                        _buildTabHeader(
                          'Pending',
                          _tabCount(provider, SubmissionStatus.submitted),
                          theme,
                        ),
                        _buildTabHeader(
                          'Approved',
                          _tabCount(provider, SubmissionStatus.approved),
                          theme,
                        ),
                        _buildTabHeader(
                          'Rejected',
                          _tabCount(provider, SubmissionStatus.rejected),
                          theme,
                        ),
                      ],
                    ),
                    Expanded(child: _buildBoardBody(context, provider)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
