import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/triage_notes_formatter.dart';
import '../../../../core/utils/queue_status_formatter.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/department_provider.dart';

class DepartmentQueueScreen extends StatefulWidget {
  const DepartmentQueueScreen({super.key});

  @override
  State<DepartmentQueueScreen> createState() => _DepartmentQueueScreenState();
}

class _DepartmentQueueScreenState extends State<DepartmentQueueScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Color _getDeptColor(String department) {
    switch (department.toLowerCase()) {
      case 'laboratory':
        return const Color(0xFF047857); // Deep Emerald green
      case 'imaging':
        return const Color(0xFF4338CA); // Deep Indigo
      case 'ultrasound':
        return const Color(0xFF0F766E); // Deep Teal
      case 'ecg':
        return const Color(0xFFBE123C); // Deep Rose
      default:
        return const Color(0xFF0284C7); // Sky Blue
    }
  }

  Color _getPriorityColor(PriorityLevel priority) {
    switch (priority) {
      case PriorityLevel.emergency:
        return Colors.red.shade700;
      case PriorityLevel.urgent:
        return Colors.orange.shade700;
      case PriorityLevel.routine:
        return const Color(0xFF0284C7);
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final provider = Provider.of<DepartmentProvider>(context);
    
    final department = provider.department;
    final theme = Theme.of(context);
    final deptColor = _getDeptColor(department);

    // Format department display name
    final deptDisplayName = department.isNotEmpty
        ? department[0].toUpperCase() + department.substring(1)
        : '';

    // Filter queue entries by patient name client-side
    final filteredQueue = provider.queueEntries.where((entry) {
      final patientName = entry.patient?.fullName.toLowerCase() ?? '';
      return patientName.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('$deptDisplayName Queue'),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Department Header panel
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: deptColor.withValues(alpha: 0.05),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$deptDisplayName Department Portal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: deptColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage patient queues, enter clinical findings, and audit department records.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Queue counts mini-panel
                  Row(
                    children: [
                      _buildCountBadge(
                        context,
                        'Waiting',
                        provider.queueEntries.where((e) => e.status == QueueStatus.waiting).length,
                        Colors.orange.shade700,
                      ),
                      const SizedBox(width: 12),
                      _buildCountBadge(
                        context,
                        'In Progress',
                        provider.queueEntries.where((e) => e.status == QueueStatus.inProgress).length,
                        deptColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search queue by patient name...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                ),
              ),
            ),

            // Queue List
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => provider.loadDashboard(),
                      child: filteredQueue.isEmpty
                          ? _buildEmptyState(theme)
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              itemCount: filteredQueue.length,
                              itemBuilder: (context, index) {
                                final entry = filteredQueue[index];
                                return _buildQueueCard(context, entry, deptColor);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountBadge(BuildContext context, String label, int count, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(BuildContext context, PatientQueue entry, Color deptColor) {
    final theme = Theme.of(context);
    final patient = entry.patient;
    final patientName = patient?.fullName ?? 'Unknown Patient';
    final statusFormat = formatQueueStatus(entry.status);
    final priorityColor = _getPriorityColor(entry.priorityLevel);

    final queueNum = extractQueueNumber(entry.triageNotes);
    final vitalsSummary = extractVitalsSummary(entry.triageNotes);
    final triageNote = extractTriageNotes(entry.triageNotes);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient Name & Queue Number
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    patientName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: deptColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: deptColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    queueNum,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: deptColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Badges: Priority, Status
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                // Priority Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.priorityLevel.toJsonValue().toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: priorityColor,
                    ),
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusFormat.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusFormat.staffBadgeLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusFormat.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Vitals
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vitalsSummary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Triage Note
            if (triageNote != null && triageNote.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes_rounded, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Triage Note: $triageNote',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Row 1: Queue Number + Routed Time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: deptColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: deptColor.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    'Queue: $queueNum',
                    key: const Key('queue_number_label'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: deptColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Routed: ${entry.createdAt.toLocal().toString().substring(11, 16)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 2: Action Button
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                key: ValueKey('enter_results_btn_${entry.patientId}'),
                onPressed: () {
                  context.push('/department/result-entry/${entry.patientId}');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: deptColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Enter Results'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
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
                  Icons.assignment_turned_in_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isEmpty
                      ? "No patients queued. Today's queue is empty."
                      : 'No patients found matching your search.',
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
