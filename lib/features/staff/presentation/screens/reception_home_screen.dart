import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/reception_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/document.dart';
import '../widgets/queue_entry_card.dart';
import '../widgets/document_review_card.dart';

class ReceptionHomeScreen extends StatefulWidget {
  const ReceptionHomeScreen({super.key});

  @override
  State<ReceptionHomeScreen> createState() => _ReceptionHomeScreenState();
}

class _ReceptionHomeScreenState extends State<ReceptionHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showRejectionDialog(BuildContext context, String documentId, ReceptionProvider provider) {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reject Document',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please select a rejection reason or type a custom one.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: 16),
                // Predefined Chips
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ActionChip(
                      label: const Text('Blurry Image'),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      onPressed: () => textController.text = 'Blurry Image',
                    ),
                    ActionChip(
                      label: const Text('Incorrect Document Type'),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      onPressed: () => textController.text = 'Incorrect Document Type',
                    ),
                    ActionChip(
                      label: const Text('Missing Signature'),
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      onPressed: () => textController.text = 'Missing Signature',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Rejection Reason Text Field
                TextFormField(
                  controller: textController,
                  maxLength: 200,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Rejection Reason',
                    border: OutlineInputBorder(),
                    hintText: 'Enter reason for rejection...',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Rejection reason is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState?.validate() ?? false) {
                          final reason = textController.text.trim();
                          Navigator.pop(context);
                          final success = await provider.updateDocumentStatus(
                            documentId,
                            DocumentStatus.rejected,
                            rejectionReason: reason,
                          );
                          if (context.mounted && !success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(provider.errorMessage ?? 'Failed to reject document.')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Confirm Rejection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
              _buildDetailRow(theme, 'Triage Notes', entry.triageNotes ?? 'None'),
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
    final profile = authProvider.profile;

    return ChangeNotifierProvider<ReceptionProvider>(
      create: (_) => ReceptionProvider()..loadDashboard(),
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
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.format_list_bulleted_rounded),
                    text: 'Today\'s Queue',
                  ),
                  Tab(
                    icon: Icon(Icons.rate_review_outlined),
                    text: 'Document Reviews',
                  ),
                ],
              ),
            ),
            body: SafeArea(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // Today's Queue Tab
                        RefreshIndicator(
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
                                      actions: entry.status == QueueStatus.waiting
                                          ? [
                                              ElevatedButton.icon(
                                                onPressed: () async {
                                                  final success = await provider.updateQueueStatus(
                                                    entry.id,
                                                    QueueStatus.inProgress,
                                                  );
                                                  if (context.mounted && !success) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text(provider.errorMessage ??
                                                            'Failed to mark patient as arrived.'),
                                                      ),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                                                label: const Text('Mark Arrived'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                                  foregroundColor: Colors.white,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              ),
                                            ]
                                          : null,
                                    );
                                  },
                                ),
                        ),

                        // Document Reviews Tab
                        RefreshIndicator(
                          onRefresh: () => provider.loadDashboard(),
                          child: provider.pendingDocuments.isEmpty
                              ? _buildEmptyState(context, 'No pending documents for review.')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: provider.pendingDocuments.length,
                                  itemBuilder: (context, index) {
                                    final doc = provider.pendingDocuments[index];
                                    return DocumentReviewCard(
                                      document: doc,
                                      onApprove: () async {
                                        final success = await provider.updateDocumentStatus(
                                          doc.id,
                                          DocumentStatus.approved,
                                        );
                                        if (context.mounted && !success) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(provider.errorMessage ?? 'Failed to approve document.'),
                                            ),
                                          );
                                        }
                                      },
                                      onReject: () => _showRejectionDialog(context, doc.id, provider),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
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
                  Icons.space_dashboard_outlined,
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
