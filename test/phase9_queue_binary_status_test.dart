import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/utils/queue_status_formatter.dart';
import 'package:klinikaid_mobile/core/theme/app_theme.dart';

void main() {
  group('Phase 9: Queue Binary Status Formatter Unit Tests', () {
    test('waiting status maps correctly', () {
      final format = formatQueueStatus(QueueStatus.waiting);
      expect(format.patientCardTitle, equals('IN QUEUE'));
      expect(format.patientBodyText, equals('Waiting in Queue'));
      expect(format.staffBadgeLabel, equals('WAITING'));
      expect(format.icon, equals(Icons.access_time_rounded));
      expect(format.color, equals(AppTheme.mutedForeground));
    });

    test('inProgress status maps correctly', () {
      final format = formatQueueStatus(QueueStatus.inProgress);
      expect(format.patientCardTitle, equals('NOW CALLING'));
      expect(format.patientBodyText, equals('Now Being Called'));
      expect(format.staffBadgeLabel, equals('IN PROGRESS'));
      expect(format.icon, equals(Icons.volume_up_rounded));
      expect(format.color, equals(AppTheme.primary));
    });

    test('completed status maps correctly', () {
      final format = formatQueueStatus(QueueStatus.completed);
      expect(format.patientCardTitle, equals('COMPLETED'));
      expect(format.patientBodyText, equals('Completed'));
      expect(format.staffBadgeLabel, equals('COMPLETED'));
      expect(format.icon, equals(Icons.check_circle_rounded));
      expect(format.color, equals(Colors.green));
    });

    test('cancelled status maps correctly', () {
      final format = formatQueueStatus(QueueStatus.cancelled);
      expect(format.patientCardTitle, equals('CANCELLED'));
      expect(format.patientBodyText, equals('Cancelled'));
      expect(format.staffBadgeLabel, equals('CANCELLED'));
      expect(format.icon, equals(Icons.cancel_rounded));
      expect(format.color, equals(Colors.grey));
    });
  });
}
