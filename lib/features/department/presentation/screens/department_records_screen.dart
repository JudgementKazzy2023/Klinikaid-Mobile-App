import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/reference_status_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../records/domain/record_grouper.dart';
import '../../../records/presentation/widgets/grouped_record_detail_modal.dart';
import '../providers/department_provider.dart';

class DepartmentRecordsScreen extends StatefulWidget {
  const DepartmentRecordsScreen({super.key});

  @override
  State<DepartmentRecordsScreen> createState() => _DepartmentRecordsScreenState();
}

class _DepartmentRecordsScreenState extends State<DepartmentRecordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

    final deptDisplayName = department.isNotEmpty
        ? department[0].toUpperCase() + department.substring(1)
        : '';

    // Filter grouped records by patient name or test type client-side
    final filteredRecords = provider.groupedRecords.where((grouped) {
      final patientName = grouped.records.first.patient?.fullName.toLowerCase() ?? '';
      final testType = grouped.displayTitle.toLowerCase();
      return patientName.contains(_searchQuery) || testType.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('$deptDisplayName Records'),
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
            // Header showing count of reports
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Audit clinical histories & reports.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: deptColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${provider.groupedRecords.length} Reports',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: deptColor,
                      ),
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

            // Records List
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => provider.loadDashboard(),
                      child: filteredRecords.isEmpty
                          ? _buildEmptyState(theme)
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              itemCount: filteredRecords.length,
                              itemBuilder: (context, index) {
                                final groupedRecord = filteredRecords[index];
                                return _buildRecordCard(context, groupedRecord, deptColor);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, GroupedRecord grouped, Color deptColor) {
    final theme = Theme.of(context);
    final firstRecord = grouped.records.first;
    final patientName = firstRecord.patient?.fullName ?? 'Unknown Patient';

    // Format the date
    final dateStr = firstRecord.createdAt.toLocal().toString().substring(0, 16);

    // Defensive fallback for recorder name: if null or empty, display "Unknown"
    final recorderName = (firstRecord.recorder?.fullName == null ||
            firstRecord.recorder!.fullName.trim().isEmpty)
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
              // Patient Name & Normal/Flagged Badge
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

              // Date + Entered by [recorder]
              Text(
                'Recorded: $dateStr | Entered by $recorderName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),

              // Test Type Badge
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

              // Parameters Summary
              if (grouped.isSingleParameter) ...[
                // Free-text or single row parameter
                _buildParameterRow(
                  context,
                  firstRecord.testResults['test_name']?.toString() ?? firstRecord.testType,
                  '${firstRecord.testResults['test_value']?.toString() ?? ''} ${firstRecord.testResults['unit']?.toString() ?? ''}',
                  isFlagged,
                ),
              ] else ...[
                // Multi-parameter (e.g. Lab panels)
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

              // Technician Notes
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
                  _searchController.text.isEmpty
                      ? 'No historical department records found.'
                      : 'No records found matching your search.',
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
