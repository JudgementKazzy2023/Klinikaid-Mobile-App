import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/reception_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../widgets/queue_entry_card.dart';
import '../widgets/document_review_card.dart';
import '../../../../core/utils/triage_notes_formatter.dart';

class ReceptionHomeScreen extends StatefulWidget {
  final ReceptionProvider? providerOverride;
  const ReceptionHomeScreen({super.key, this.providerOverride});

  @override
  State<ReceptionHomeScreen> createState() => _ReceptionHomeScreenState();
}

class _ReceptionHomeScreenState extends State<ReceptionHomeScreen> {
  void _showQueueDetails(BuildContext context, PatientQueue entry) {
    showDialog(
      context: context,
      builder: (context) {
        final patient = entry.patient;
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            patient?.fullName ?? 'Queue Details',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(theme, 'Queue ID', '#${entry.id}'),
              _buildDetailRow(theme, 'Department', entry.department.toJsonValue().toUpperCase()),
              _buildDetailRow(theme, 'Priority', entry.priorityLevel.toJsonValue().toUpperCase()),
              _buildDetailRow(theme, 'Status', entry.status.name.toUpperCase()),
              Builder(builder: (context) {
                final notes = extractTriageNotes(entry.triageNotes);
                if (notes == null) return const SizedBox.shrink();
                return _buildDetailRow(theme, 'Triage Notes', notes);
              }),
              _buildDetailRow(theme, 'Arrived At', entry.createdAt.toLocal().toString().substring(11, 19)),
              const Divider(height: 24),
              if (patient != null) ...[
                Text('Patient Info', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildDetailRow(theme, 'DOB', patient.dateOfBirth.toString().substring(0, 10)),
                _buildDetailRow(theme, 'Gender', patient.gender.name.toUpperCase()),
                _buildDetailRow(theme, 'Contact', patient.contactNumber),
                _buildDetailRow(theme, 'Address', patient.address),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return ChangeNotifierProvider<ReceptionProvider>(
      create: (_) => widget.providerOverride ?? (ReceptionProvider()..loadDashboard()),
      child: Consumer<ReceptionProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              title: const Text('Reception Portal'),
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
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDocumentsNestedTabs(context, provider),
            ),
          );
        },
      ),
    );
  }

  // Queue tab body. Currently unwired from the UI per project decision
  // 2026-06-22: queue management is owned by the web portal. The widget,
  // provider, and Realtime subscription are preserved in case the queue
  // tab is re-enabled in a future release.
  // ignore: unused_element
  Widget _queueTabBody(BuildContext context, ReceptionProvider provider) {
    return RefreshIndicator(
      onRefresh: () => provider.loadDashboard(),
      child: provider.queueEntries.isEmpty
          ? _buildEmptyState(context, 'No active queue entries today.')
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: provider.queueEntries.length,
              itemBuilder: (context, index) {
                final entry = provider.queueEntries[index];
                return QueueEntryCard(
                  entry: entry,
                  onTap: () => _showQueueDetails(context, entry),
                  showActionButtons: false,
                );
              },
            ),
    );
  }

  Widget _buildDocumentsNestedTabs(BuildContext context, ReceptionProvider provider) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Pending Tab
                RefreshIndicator(
                  onRefresh: () => provider.loadDashboard(),
                  child: provider.pendingDocuments.isEmpty
                      ? _buildEmptyState(
                          context,
                          'No pending documents. New submissions will appear here.',
                          icon: Icons.insert_drive_file_outlined,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: provider.pendingDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = provider.pendingDocuments[index];
                            return DocumentReviewCard(document: doc);
                          },
                        ),
                ),

                // Approved Tab
                RefreshIndicator(
                  onRefresh: () => provider.loadDashboard(),
                  child: provider.approvedDocuments.isEmpty
                      ? _buildEmptyState(
                          context,
                          'No approved documents in the last 30 days.',
                          icon: Icons.check_circle_outline_rounded,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: provider.approvedDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = provider.approvedDocuments[index];
                            return DocumentReviewCard(document: doc);
                          },
                        ),
                ),

                // Rejected Tab
                RefreshIndicator(
                  onRefresh: () => provider.loadDashboard(),
                  child: provider.rejectedDocuments.isEmpty
                      ? _buildEmptyState(
                          context,
                          'No rejected documents in the last 30 days.',
                          icon: Icons.highlight_off_rounded,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: provider.rejectedDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = provider.rejectedDocuments[index];
                            return DocumentReviewCard(document: doc);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, {IconData icon = Icons.space_dashboard_outlined}) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            alignment: Alignment.center,
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
      },
    );
  }
}
