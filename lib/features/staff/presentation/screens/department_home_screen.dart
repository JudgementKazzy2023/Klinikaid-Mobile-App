import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/department_record.dart';
import '../widgets/queue_entry_card.dart';

class DepartmentHomeScreen extends StatefulWidget {
  const DepartmentHomeScreen({super.key});

  @override
  State<DepartmentHomeScreen> createState() => _DepartmentHomeScreenState();
}

class _DepartmentHomeScreenState extends State<DepartmentHomeScreen> with SingleTickerProviderStateMixin {
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

  void _showRecordDetails(BuildContext context, DepartmentRecord record) {
    showDialog(
      context: context,
      builder: (context) {
        final patient = record.patient;
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            record.testType,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(theme, 'Test Name', record.testResults['test_name']?.toString() ?? ''),
                _buildDetailRow(theme, 'Test Value', '${record.testResults['test_value']?.toString() ?? ''} ${record.testResults['unit']?.toString() ?? ''}'),
                _buildDetailRow(
                  theme,
                  'Reference Status',
                  record.referenceRangeStatus.name.toUpperCase(),
                ),
                _buildDetailRow(theme, 'Recorded At', record.createdAt.toLocal().toString().substring(0, 16)),
                _buildDetailRow(theme, 'Notes', record.notes ?? 'None'),
                const Divider(height: 24),
                if (patient != null) ...[
                  Text('Patient Info', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildDetailRow(theme, 'Name', patient.fullName),
                  _buildDetailRow(theme, 'DOB', patient.dateOfBirth.toString().substring(0, 10)),
                  _buildDetailRow(theme, 'Gender', patient.gender.name.toUpperCase()),
                ],
              ],
            ),
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
            width: 110,
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
    final deptName = profile?.department?.toJsonValue() ?? 'laboratory';

    return ChangeNotifierProvider<DepartmentProvider>(
      create: (_) => DepartmentProvider(deptName)..loadDashboard(),
      child: Consumer<DepartmentProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              title: Text('${deptName.toUpperCase()} Portal'),
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
                    icon: Icon(Icons.playlist_play_rounded),
                    text: 'Department Queue',
                  ),
                  Tab(
                    icon: Icon(Icons.assignment_turned_in_outlined),
                    text: 'Recent Records',
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
                        // Department Queue Tab
                        RefreshIndicator(
                          onRefresh: () => provider.loadDashboard(),
                          child: provider.queueEntries.isEmpty
                              ? _buildEmptyState(context, 'No active queue entries for this department.')
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
                                                            'Failed to transition queue status.'),
                                                      ),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                label: const Text('Start Service'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                                  foregroundColor: Colors.white,
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              ),
                                            ]
                                          : entry.status == QueueStatus.inProgress
                                              ? [
                                                  ElevatedButton.icon(
                                                    onPressed: () async {
                                                      final success = await provider.updateQueueStatus(
                                                        entry.id,
                                                        QueueStatus.completed,
                                                      );
                                                      if (context.mounted && !success) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text(provider.errorMessage ??
                                                                'Failed to complete queue item.'),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    icon: const Icon(Icons.done_all_rounded, size: 16),
                                                    label: const Text('Complete'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.green.shade700,
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

                        // Completed Records Tab
                        RefreshIndicator(
                          onRefresh: () => provider.loadDashboard(),
                          child: provider.recentRecords.isEmpty
                              ? _buildEmptyState(context, 'No recent completed records found.')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: provider.recentRecords.length,
                                  itemBuilder: (context, index) {
                                    final record = provider.recentRecords[index];
                                    final patientName = record.patient != null ? record.patient!.fullName : 'Patient';
                                    final recordColor = record.referenceRangeStatus == ReferenceRangeStatus.normal
                                        ? Colors.green.shade700
                                        : Colors.red.shade700;

                                    return Card(
                                      elevation: 1.5,
                                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10.0),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                        onTap: () => _showRecordDetails(context, record),
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                          child: Icon(Icons.assignment_outlined,
                                              color: Theme.of(context).colorScheme.primary),
                                        ),
                                        title: Text(
                                          record.testType,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text('Patient: $patientName'),
                                            Text(
                                              'Recorded: ${record.createdAt.toLocal().toString().substring(0, 16)}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${record.testResults['test_value']?.toString() ?? ''} ${record.testResults['unit']?.toString() ?? ''}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: recordColor.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                record.referenceRangeStatus.name.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                  color: recordColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
                  Icons.assignment_late_outlined,
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
