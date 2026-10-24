import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/reception_queue_provider.dart';
import '../widgets/submission_card.dart';
import '../../domain/submission.dart';
import '../../domain/submission_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ReceptionQueueScreen extends StatefulWidget {
  const ReceptionQueueScreen({super.key});

  @override
  State<ReceptionQueueScreen> createState() => _ReceptionQueueScreenState();
}

class _ReceptionQueueScreenState extends State<ReceptionQueueScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Submission> _filterList(List<Submission> list) {
    if (_searchQuery.isEmpty) return list;
    return list.where((item) {
      final name = item.patientName.toLowerCase();
      final file = item.fileName.toLowerCase();
      final type = item.fileType.toLowerCase();
      return name.contains(_searchQuery) ||
          file.contains(_searchQuery) ||
          type.contains(_searchQuery);
    }).toList();
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

  Widget _buildTabList(
    BuildContext context,
    SubmissionStatus status,
    String emptyMessage,
    IconData emptyIcon,
    ReceptionQueueProvider provider,
  ) {
    final loaded = provider.submissionsOf(status);
    final filtered = _filterList(loaded);
    final total = provider.totalOf(status);

    if (filtered.isEmpty && !provider.hasMoreOf(status)) {
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
                // The search runs over the pages that are on screen, so the
                // label says so instead of claiming the whole column.
                _searchQuery.isEmpty
                    ? 'Showing ${loaded.length} of $total'
                    : '${filtered.length} of ${loaded.length} loaded documents match',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final submission = filtered[index];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<ReceptionQueueProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

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
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search patient name, file name or type...',
                  prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                  suffixIcon: _searchController.text.isNotEmpty
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
                          _knownCount(provider, provider.pendingTotal),
                          theme,
                        ),
                        _buildTabHeader(
                          'Approved',
                          _knownCount(provider, provider.approvedTotal),
                          theme,
                        ),
                        _buildTabHeader(
                          'Rejected',
                          _knownCount(provider, provider.rejectedTotal),
                          theme,
                        ),
                      ],
                    ),
                    Expanded(
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.boardError != null
                          // A failed read is not an empty board: reception
                          // reading three empty columns would conclude there
                          // are no referrals while every upload sits unseen.
                          ? _buildErrorState(context, provider)
                          : TabBarView(
                              children: [
                                // Pending Tab
                                _buildTabList(
                                  context,
                                  SubmissionStatus.submitted,
                                  'No pending documents.',
                                  Icons.assignment_turned_in_outlined,
                                  provider,
                                ),
                                // Approved Tab
                                _buildTabList(
                                  context,
                                  SubmissionStatus.approved,
                                  'No approved documents.',
                                  Icons.check_circle_outline_rounded,
                                  provider,
                                ),
                                // Rejected Tab
                                _buildTabList(
                                  context,
                                  SubmissionStatus.rejected,
                                  'No rejected documents.',
                                  Icons.highlight_off_rounded,
                                  provider,
                                ),
                              ],
                            ),
                    ),
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
