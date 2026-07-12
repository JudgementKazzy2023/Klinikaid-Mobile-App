import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/department_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/utils/reference_status_formatter.dart';
import '../../../records/domain/record_grouper.dart';
import '../widgets/queue_entry_card.dart';
import '../../../../core/utils/triage_notes_formatter.dart';
import '../../../../core/utils/queue_status_formatter.dart';
import '../../../../core/utils/date_formatter.dart';

class DepartmentHomeScreen extends StatefulWidget {
  final DepartmentProvider? providerOverride;
  const DepartmentHomeScreen({super.key, this.providerOverride});

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
        final format = formatQueueStatus(entry.status);
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
              _buildDetailRow(theme, 'Status', format.staffBadgeLabel),
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

  Widget _buildStatusBadge(BuildContext context, ReferenceRangeStatus status) {
    Color bgColor;
    Color fgColor;
    switch (status) {
      case ReferenceRangeStatus.normal:
        bgColor = Theme.of(context).colorScheme.primary;
        fgColor = Theme.of(context).colorScheme.onPrimary;
        break;
      case ReferenceRangeStatus.flagged:
        bgColor = Theme.of(context).colorScheme.error;
        fgColor = Colors.white;
        break;
      case ReferenceRangeStatus.inconclusive:
        bgColor = Theme.of(context).colorScheme.secondary;
        fgColor = Theme.of(context).colorScheme.onSurface;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        referenceStatusDisplayLabel(status).toUpperCase(),
        style: TextStyle(
          color: fgColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showRecordDetails(BuildContext context, GroupedRecord groupedRecord) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      isScrollControlled: true,
      builder: (context) {
        final firstRecord = groupedRecord.records.first;
        final patient = firstRecord.patient;
        final theme = Theme.of(context);

        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            final hasPdf = groupedRecord.records.any((r) => r.testResults.containsKey('pdf_path'));
            final pdfPath = hasPdf
                ? groupedRecord.records
                    .firstWhere((r) => r.testResults.containsKey('pdf_path'))
                    .testResults['pdf_path']?.toString()
                : null;

            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          groupedRecord.displayTitle,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildStatusBadge(context, groupedRecord.aggregateStatus),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Department: ${groupedRecord.department.name.toUpperCase()}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  Divider(color: theme.colorScheme.outline, height: 32),

                  if (groupedRecord.isSingleParameter) ...[
                    Text(
                      firstRecord.testResults['test_name']?.toString() ?? firstRecord.testType,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${firstRecord.testResults['test_value']?.toString() ?? ''} ${firstRecord.testResults['unit']?.toString() ?? ''}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (firstRecord.notes != null && firstRecord.notes!.isNotEmpty) ...[
                      Text(
                        'Notes',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          firstRecord.notes!,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ] else ...[
                    // Stacked parameters
                    ...groupedRecord.records.expand((r) {
                      final parameterName = r.testResults['test_name']?.toString() ?? r.testType;
                      final parameterValue = r.testResults['test_value']?.toString() ?? '';
                      final formattedHeader = parameterName.isNotEmpty
                          ? parameterName[0].toUpperCase() + parameterName.substring(1)
                          : '';

                      return [
                        Text(
                          formattedHeader,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            parameterValue,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ];
                    }),

                    if (groupedRecord.aggregatedNotes.isNotEmpty) ...[
                      Text(
                        'Technician Notes',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          groupedRecord.aggregatedNotes,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],

                  if (patient != null) ...[
                    Divider(color: theme.colorScheme.outline, height: 32),
                    Text(
                      'Patient Info',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(theme, 'Name', patient.fullName),
                    _buildDetailRow(theme, 'DOB', patient.dateOfBirth.toString().substring(0, 10)),
                    _buildDetailRow(theme, 'Gender', patient.gender.name.toUpperCase()),
                    const SizedBox(height: 24),
                  ],

                  if (hasPdf && pdfPath != null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Open Result Attachment'),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Loading report attachment: $pdfPath'),
                              backgroundColor: theme.colorScheme.primary,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
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
      create: (_) => widget.providerOverride ?? (DepartmentProvider(deptName)..loadDashboard()),
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
                                      showActionButtons: false,
                                    );
                                  },
                                ),
                        ),

                        // Completed Records Tab
                        RefreshIndicator(
                          onRefresh: () => provider.loadDashboard(),
                          child: provider.groupedRecords.isEmpty
                              ? _buildEmptyState(context, 'No recent completed records found.')
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: provider.groupedRecords.length,
                                  itemBuilder: (context, index) {
                                    final groupedRecord = provider.groupedRecords[index];
                                    final firstRecord = groupedRecord.records.first;
                                    final patientName = firstRecord.patient != null ? firstRecord.patient!.fullName : 'Patient';

                                    final status = groupedRecord.aggregateStatus;
                                    Color recordColor;
                                    switch (status) {
                                      case ReferenceRangeStatus.normal:
                                        recordColor = Colors.green.shade700;
                                        break;
                                      case ReferenceRangeStatus.flagged:
                                        recordColor = Colors.red.shade700;
                                        break;
                                      case ReferenceRangeStatus.inconclusive:
                                        recordColor = Colors.orange.shade700;
                                        break;
                                    }

                                    return Card(
                                      elevation: 1.5,
                                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10.0),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                        onTap: () => _showRecordDetails(context, groupedRecord),
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                          child: Icon(Icons.assignment_outlined,
                                              color: Theme.of(context).colorScheme.primary),
                                        ),
                                        title: Text(
                                          groupedRecord.displayTitle,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text('Patient: $patientName'),
                                            Text(
                                              'Recorded: ${DateFormatter.formatPht(firstRecord.createdAt)}',
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
                                              groupedRecord.isSingleParameter
                                                  ? '${firstRecord.testResults['test_value']?.toString() ?? ''} ${firstRecord.testResults['unit']?.toString() ?? ''}'
                                                  : 'Multi-parameter',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: groupedRecord.isSingleParameter ? 14 : 11,
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
                                                status.name.toUpperCase().replaceAll('_', ' '),
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
