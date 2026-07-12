import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/admin_provider.dart';
import '../../../../core/utils/reference_status_formatter.dart';
import '../../../../core/utils/triage_notes_formatter.dart';
import '../../../../core/utils/queue_status_formatter.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../records/domain/record_grouper.dart';
import '../../../records/presentation/widgets/grouped_record_detail_modal.dart';
import '../../../../core/utils/date_formatter.dart';

class AdminRecordsScreen extends StatefulWidget {
  const AdminRecordsScreen({super.key});

  @override
  State<AdminRecordsScreen> createState() => _AdminRecordsScreenState();
}

class _AdminRecordsScreenState extends State<AdminRecordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AdminProvider>(context, listen: false);
      provider.loadDepartmentRecords(provider.selectedDepartment);
      provider.loadDepartmentQueue(provider.selectedDepartment);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getDeptColor(String department) {
    switch (department.toLowerCase()) {
      case 'laboratory':
        return const Color(0xFF047857);
      case 'imaging':
        return const Color(0xFF4338CA);
      case 'ultrasound':
        return const Color(0xFF0F766E);
      case 'ecg':
        return const Color(0xFFBE123C);
      default:
        return const Color(0xFF0284C7);
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);
    final department = provider.selectedDepartment;
    final deptColor = _getDeptColor(department);

    // Filter grouped records by patient name or test type client-side
    final filteredRecords = provider.groupedRecords.where((grouped) {
      final patientName = grouped.records.first.patient?.fullName.toLowerCase() ?? '';
      final testType = grouped.displayTitle.toLowerCase();
      return patientName.contains(_searchQuery) || testType.contains(_searchQuery);
    }).toList();

    // Filter queue entries by patient name client-side
    final filteredQueue = provider.deptQueueEntries.where((entry) {
      final patientName = entry.patient?.fullName.toLowerCase() ?? '';
      return patientName.contains(_searchQuery);
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Department Switcher Header
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
                child: Row(
                  children: [
                    const Text(
                      'Department:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('admin_dept_switcher'),
                        value: department.toLowerCase(),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'laboratory', child: Text('Laboratory', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'imaging', child: Text('Imaging', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'ultrasound', child: Text('Ultrasound', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'ecg', child: Text('ECG', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            provider.loadDepartmentRecords(val);
                            provider.loadDepartmentQueue(val);
                          }
                        },
                      ),
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
                    hintText: 'Search by patient name or test...',
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

              // Tabs
              TabBar(
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: theme.colorScheme.primary,
                tabs: const [
                  Tab(text: 'Daily Queue'),
                  Tab(text: 'Records History'),
                ],
              ),

              // Tab View
              Expanded(
                child: TabBarView(
                  children: [
                    // Daily Queue Tab
                    provider.isDeptQueueLoading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: () => provider.loadDepartmentQueue(department),
                            child: filteredQueue.isEmpty
                                ? _buildEmptyQueueState(theme)
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    itemCount: filteredQueue.length,
                                    itemBuilder: (context, index) {
                                      final entry = filteredQueue[index];
                                      return _buildQueueCard(context, entry, deptColor, department);
                                    },
                                  ),
                          ),

                    // Records History Tab
                    provider.isRecordsLoading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: () => provider.loadDepartmentRecords(department),
                            child: filteredRecords.isEmpty
                                ? _buildEmptyState(theme)
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    itemCount: filteredRecords.length,
                                    itemBuilder: (context, index) {
                                      final groupedRecord = filteredRecords[index];
                                      return _buildRecordCard(context, groupedRecord, deptColor);
                                    },
                                  ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(BuildContext context, PatientQueue entry, Color deptColor, String selectedDept) {
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

            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
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

            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                key: ValueKey('enter_results_btn_${entry.patientId}'),
                onPressed: () {
                  context.push('/admin/department/result-entry/${entry.patientId}?dept=$selectedDept');
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

  Widget _buildEmptyQueueState(ThemeData theme) {
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

  Widget _buildRecordCard(BuildContext context, GroupedRecord grouped, Color deptColor) {
    final theme = Theme.of(context);
    final firstRecord = grouped.records.first;
    final patientName = firstRecord.patient?.fullName ?? 'Unknown Patient';
    final dateStr = DateFormatter.formatPht(firstRecord.createdAt);

    final recorderName = (firstRecord.recorder?.fullName == null || firstRecord.recorder!.fullName.trim().isEmpty)
        ? 'Unknown'
        : firstRecord.recorder!.fullName.trim();

    final isFlagged = isStatusFlagged(grouped.aggregateStatus);
    final badgeColor = isFlagged ? Colors.red.shade700 : Colors.green.shade700;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: () => GroupedRecordDetailModal.show(context, grouped),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isFlagged ? 'FLAGGED' : 'NORMAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Recorded: $dateStr | Entered by $recorderName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  grouped.displayTitle.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (grouped.isSingleParameter) ...[
                _buildParameterRow(
                  context,
                  firstRecord.testResults['test_name']?.toString() ?? firstRecord.testType,
                  '${firstRecord.testResults['test_value']?.toString() ?? ''} ${firstRecord.testResults['unit']?.toString() ?? ''}',
                  isFlagged,
                ),
              ] else ...[
                ...grouped.records.map((r) {
                  final pName = r.testResults['test_name']?.toString() ?? r.testType;
                  final pVal = '${r.testResults['test_value']?.toString() ?? ''} ${r.testResults['unit']?.toString() ?? ''}';
                  final rFlagged = isStatusFlagged(r.referenceRangeStatus);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: _buildParameterRow(context, pName, pVal, rFlagged),
                  );
                }),
              ],
              if (firstRecord.notes != null && firstRecord.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Tech Notes: ${firstRecord.notes}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParameterRow(BuildContext context, String name, String value, bool isFlagged) {
    final theme = Theme.of(context);
    final valueColor = isFlagged ? Colors.red.shade700 : theme.colorScheme.onSurface;
    final valueWeight = isFlagged ? FontWeight.bold : FontWeight.normal;

    return Row(
      children: [
        Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: valueWeight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_late_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No records found for this department.'),
        ],
      ),
    );
  }
}
