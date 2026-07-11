import 'package:flutter/material.dart';
import '../../../../core/models/department_record.dart';
import '../../../../core/utils/reference_status_formatter.dart';
import '../../domain/record_grouper.dart';

class GroupedRecordDetailModal extends StatelessWidget {
  final GroupedRecord groupedRecord;
  final ScrollController scrollController;

  const GroupedRecordDetailModal({
    super.key,
    required this.groupedRecord,
    required this.scrollController,
  });

  /// Displays the modal bottom sheet for the given [groupedRecord].
  static void show(BuildContext context, GroupedRecord groupedRecord) {
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
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return GroupedRecordDetailModal(
              groupedRecord: groupedRecord,
              scrollController: scrollController,
            );
          },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (groupedRecord.isSingleParameter) {
      final record = groupedRecord.records.first;
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
                    record.testType,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusBadge(context, record.referenceRangeStatus),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Department: ${record.department.name.toUpperCase()}',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            Divider(color: theme.colorScheme.outline, height: 32),
            
            Text(
              'Test Results',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (record.testResults.isEmpty)
              Text(
                'No quantitative values recorded.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline, width: 1),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(1.0),
                  },
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: theme.colorScheme.outline, width: 1),
                  ),
                  children: record.testResults.entries.map((entry) {
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            entry.key.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            entry.value.toString(),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            
            const SizedBox(height: 24),
            if (record.notes != null && record.notes!.isNotEmpty) ...[
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
                  record.notes!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (record.testResults.containsKey('pdf_path')) ...[
              const SizedBox(height: 8),
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
                        content: Text('Loading report attachment: ${record.testResults['pdf_path']}'),
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
    } else {
      // Multi-parameter grouped view
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

            // Stacked parameters (ensure 'findings' comes before 'impression' if present)
            ...(() {
              final list = List<DepartmentRecord>.from(groupedRecord.records);
              list.sort((a, b) {
                final aName = (a.testResults['test_name']?.toString() ?? '').toLowerCase();
                final bName = (b.testResults['test_name']?.toString() ?? '').toLowerCase();
                if (aName == 'findings' && bName == 'impression') return -1;
                if (aName == 'impression' && bName == 'findings') return 1;
                return 0;
              });
              return list;
            })().expand((r) {
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

            // Aggregated Notes
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

            if (hasPdf && pdfPath != null) ...[
              const SizedBox(height: 8),
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
    }
  }
}
