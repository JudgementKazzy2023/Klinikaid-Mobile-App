import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/reception_queue_provider.dart';
import '../widgets/submission_card.dart';
import '../../domain/submission.dart';
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

  Widget _buildTabList(
    BuildContext context,
    List<Submission> submissions,
    String emptyMessage,
    IconData emptyIcon,
    ReceptionQueueProvider provider,
  ) {
    final filtered = _filterList(submissions);

    if (filtered.isEmpty) {
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
    );
  }

  Widget _buildTabHeader(String title, int count, ThemeData theme) {
    return Tab(
      child: Text(
        '$title ($count)',
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
                        _buildTabHeader('Pending', provider.submittedSubmissions.length, theme),
                        _buildTabHeader('Approved', provider.approvedSubmissions.length, theme),
                        _buildTabHeader('Rejected', provider.rejectedSubmissions.length, theme),
                      ],
                    ),
                    Expanded(
                      child: provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : TabBarView(
                              children: [
                                // Pending Tab
                                _buildTabList(
                                  context,
                                  provider.submittedSubmissions,
                                  'No pending documents.',
                                  Icons.assignment_turned_in_outlined,
                                  provider,
                                ),
                                // Approved Tab
                                _buildTabList(
                                  context,
                                  provider.approvedSubmissions,
                                  'No approved documents.',
                                  Icons.check_circle_outline_rounded,
                                  provider,
                                ),
                                // Rejected Tab
                                _buildTabList(
                                  context,
                                  provider.rejectedSubmissions,
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
