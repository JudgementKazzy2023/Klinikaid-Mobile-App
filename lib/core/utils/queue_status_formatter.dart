import 'package:flutter/material.dart';
import '../models/patient_queue.dart';
import '../theme/app_theme.dart';

class QueueStatusFormat {
  final String patientCardTitle; // "IN QUEUE" / "NOW CALLING"
  final String patientBodyText; // "Waiting in Queue" / "Now Being Called"
  final String staffBadgeLabel; // "WAITING" / "IN PROGRESS"
  final IconData icon; // Icons.access_time / Icons.volume_up
  final Color color; // muted / forest-green primary

  const QueueStatusFormat({
    required this.patientCardTitle,
    required this.patientBodyText,
    required this.staffBadgeLabel,
    required this.icon,
    required this.color,
  });
}

QueueStatusFormat formatQueueStatus(QueueStatus status) {
  switch (status) {
    case QueueStatus.waiting:
      return const QueueStatusFormat(
        patientCardTitle: 'IN QUEUE',
        patientBodyText: 'Waiting in Queue',
        staffBadgeLabel: 'WAITING',
        icon: Icons.access_time_rounded,
        color: AppTheme.mutedForeground,
      );
    case QueueStatus.inProgress:
      return const QueueStatusFormat(
        patientCardTitle: 'NOW CALLING',
        patientBodyText: 'Now Being Called',
        staffBadgeLabel: 'IN PROGRESS',
        icon: Icons.volume_up_rounded,
        color: AppTheme.primary,
      );
    case QueueStatus.completed:
      return const QueueStatusFormat(
        patientCardTitle: 'COMPLETED',
        patientBodyText: 'Completed',
        staffBadgeLabel: 'COMPLETED',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
      );
    case QueueStatus.cancelled:
      return const QueueStatusFormat(
        patientCardTitle: 'CANCELLED',
        patientBodyText: 'Cancelled',
        staffBadgeLabel: 'CANCELLED',
        icon: Icons.cancel_rounded,
        color: Colors.grey,
      );
  }
}
