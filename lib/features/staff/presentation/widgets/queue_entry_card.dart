import 'package:flutter/material.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/utils/triage_notes_formatter.dart';
import '../../../../core/utils/queue_status_formatter.dart';

class QueueEntryCard extends StatelessWidget {
  final PatientQueue entry;
  final List<Widget>? actions;
  final VoidCallback? onTap;
  final bool showActionButtons;

  const QueueEntryCard({
    super.key,
    required this.entry,
    this.actions,
    this.onTap,
    this.showActionButtons = true,
  });

  Color _getPriorityColor(BuildContext context, PriorityLevel priority) {
    switch (priority) {
      case PriorityLevel.emergency:
        return Colors.red.shade700;
      case PriorityLevel.urgent:
        return Colors.orange.shade700;
      case PriorityLevel.routine:
        return Theme.of(context).colorScheme.primary;
    }
  }



  @override
  Widget build(BuildContext context) {
    final patient = entry.patient;
    final patientName = patient != null ? patient.fullName : 'New User';
    final theme = Theme.of(context);
    final statusFormat = formatQueueStatus(entry.status);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient Name & Queue ID
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      patientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${entry.id}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Badges: Department, Priority, Status
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: [
                  // Department
                  Chip(
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    label: Text(
                      entry.department.toJsonValue().toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),

                  // Priority
                  Chip(
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: _getPriorityColor(context, entry.priorityLevel).withValues(alpha: 0.1),
                    side: BorderSide.none,
                    label: Text(
                      entry.priorityLevel.toJsonValue().toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getPriorityColor(context, entry.priorityLevel),
                      ),
                    ),
                  ),

                  // Status
                  Chip(
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: statusFormat.color.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    label: Text(
                      statusFormat.staffBadgeLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusFormat.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Triage Notes
              Builder(
                builder: (context) {
                  final notes = extractTriageNotes(entry.triageNotes);
                  if (notes == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      'Triage Notes: $notes',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  );
                },
              ),

              // Arrival Timestamp (Estimated Wait removed)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Arrived: ${entry.createdAt.toLocal().toString().substring(11, 16)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),

              // Custom Action Buttons
              if (showActionButtons && actions != null && actions!.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
