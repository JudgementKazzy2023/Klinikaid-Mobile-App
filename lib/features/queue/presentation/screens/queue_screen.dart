import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../providers/queue_provider.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQueueData();
    });
  }

  void _loadQueueData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.patient != null) {
      context.read<QueueProvider>().fetchQueueAndSubscribe(authProvider.patient!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Live Triage Queue',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Consumer<QueueProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.queueEntries.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
            );
          }

          if (provider.errorMessage != null && provider.queueEntries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadQueueData,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final active = provider.activeEntry;

          return RefreshIndicator(
            onRefresh: () async => _loadQueueData(),
            color: Theme.of(context).colorScheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Realtime active status banner indicator
                _buildRealtimeIndicator(provider),
                const SizedBox(height: 16),

                // Active Queue Entry Card
                if (active != null && 
                    (active.status == QueueStatus.waiting || active.status == QueueStatus.inProgress)) ...[
                  _buildActiveQueueCard(active),
                  const SizedBox(height: 24),
                ],

                // History Section Header
                Text(
                  'Queue History',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Historical entries list
                if (provider.queueEntries.isEmpty)
                  _buildEmptyState()
                else
                  ...provider.queueEntries.map((entry) => _buildHistoryCard(entry)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRealtimeIndicator(QueueProvider provider) {
    final isOffline = provider.isOffline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOffline
            ? Colors.orange.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOffline
              ? Colors.orange.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOffline ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOffline
                ? 'OFFLINE MODE - Caching active'
                : 'LIVE REALTIME MONITOR ACTIVE',
            style: TextStyle(
              color: isOffline ? Colors.orange : Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQueueCard(PatientQueue active) {
    final isInProgress = active.status == QueueStatus.inProgress;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInProgress ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isInProgress ? Icons.volume_up_rounded : Icons.hourglass_empty_rounded,
                    color: isInProgress ? Theme.of(context).colorScheme.primary : Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isInProgress ? 'NOW CALLING' : 'TRIAGE WAITING',
                    style: TextStyle(
                      color: isInProgress ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              _buildPriorityBadge(active.priorityLevel),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            active.department.name.toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${active.estimatedWaitMinutes ?? 0}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'min estimated wait',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (active.triageNotes != null && active.triageNotes!.isNotEmpty) ...[
            Divider(color: Theme.of(context).colorScheme.outline, height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.triageNotes!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard(PatientQueue entry) {
    if (entry.status == QueueStatus.waiting || entry.status == QueueStatus.inProgress) {
      // Handled in top active card
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.department.name.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.createdAt.toLocal().toString().substring(0, 16),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            _buildStatusBadge(entry.status),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.history_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 12),
            Text(
              'No previous queue logs',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(PriorityLevel priority) {
    Color color;
    switch (priority) {
      case PriorityLevel.emergency:
        color = const Color(0xFFFF3B30);
        break;
      case PriorityLevel.urgent:
        color = const Color(0xFFFF9500);
        break;
      case PriorityLevel.routine:
        color = const Color(0xFF34C759);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Text(
        priority.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(QueueStatus status) {
    Color bgColor;
    Color fgColor;
    switch (status) {
      case QueueStatus.waiting:
        bgColor = Theme.of(context).colorScheme.secondary;
        fgColor = Theme.of(context).colorScheme.onSecondary;
        break;
      case QueueStatus.inProgress:
        bgColor = Colors.orange.withValues(alpha: 0.15);
        fgColor = Colors.orange[800] ?? Colors.orange;
        break;
      case QueueStatus.completed:
        bgColor = Theme.of(context).colorScheme.primary;
        fgColor = Theme.of(context).colorScheme.onPrimary;
        break;
      case QueueStatus.cancelled:
        bgColor = Theme.of(context).colorScheme.outline.withValues(alpha: 0.2);
        fgColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.name.toUpperCase().replaceAll('INPROGRESS', 'IN PROGRESS'),
        style: TextStyle(
          color: fgColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
