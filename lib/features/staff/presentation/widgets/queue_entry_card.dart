import 'package:flutter/material.dart';
import '../../../../core/models/patient_queue.dart';

class QueueEntryCard extends StatelessWidget {
  final PatientQueue entry;
  final List<Widget>? actions;
  final VoidCallback? onTap;

  const QueueEntryCard({
    super.key,
    required this.entry,
    this.actions,
    this.onTap,
  });

  Color _getPriorityColor(BuildContext context, PriorityLevel priority) {
    switch (priority) {
      case PriorityLevel.emergency:
        return Colors.red.shade700;
      case PriorityLevel.urgent:
        return Colors.orange.shade700;
      case PriorityLevel.routine:
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _getStatusColor(QueueStatus status) {
    switch (status) {
      case QueueStatus.waiting:
        return Colors.blue.shade700;
      case QueueStatus.inProgress:
        return Colors.orange.shade800;
      case QueueStatus.completed:
        return Colors.green.shade700;
      case QueueStatus.cancelled:
        return Colors.grey.shade600;
    }
  }

  String _getStatusText(QueueStatus status) {
    switch (status) {
      case QueueStatus.waiting:
        return 'Waiting';
      case QueueStatus.inProgress:
        return 'In Progress';
      case QueueStatus.completed:
        return 'Completed';
      case QueueStatus.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = entry.patient;
    final patientName = patient != null ? patient.fullName : 'New User';
    final theme = Theme.of(context);

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
                    backgroundColor: _getStatusColor(entry.status).withValues(alpha: 0.1),
                    side: BorderSide.none,
                    label: Text(
                      _getStatusText(entry.status),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(entry.status),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Triage Notes
              if (entry.triageNotes != null && entry.triageNotes!.isNotEmpty) ...[
                Text(
                  'Triage Notes: ${entry.triageNotes}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Estimated Wait Minutes & Timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Est. Wait: ${entry.estimatedWaitMinutes ?? '--'} mins',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    'Arrived: ${entry.createdAt.toLocal().toString().substring(11, 16)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),

              // Custom Action Buttons
              if (actions != null && actions!.isNotEmpty) ...[
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
