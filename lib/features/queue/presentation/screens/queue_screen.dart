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
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text(
          'Live Triage Queue',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
      ),
      body: Consumer<QueueProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.queueEntries.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00C1D4)),
            );
          }

          if (provider.errorMessage != null && provider.queueEntries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C1D4),
                      ),
                      onPressed: _loadQueueData,
                      child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }

          final active = provider.activeEntry;

          return RefreshIndicator(
            onRefresh: () async => _loadQueueData(),
            color: const Color(0xFF00C1D4),
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
                const Text(
                  'Queue History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: provider.isOffline
            ? const Color(0xFFFF9900).withAlpha(15)
            : const Color(0xFF00C1D4).withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: provider.isOffline
              ? const Color(0xFFFF9900).withAlpha(30)
              : const Color(0xFF00C1D4).withAlpha(30),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: provider.isOffline ? const Color(0xFFFF9900) : const Color(0xFF00E676),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            provider.isOffline
                ? 'OFFLINE MODE - Caching active'
                : 'LIVE REALTIME MONITOR ACTIVE',
            style: TextStyle(
              color: provider.isOffline ? const Color(0xFFFF9900) : const Color(0xFF00C1D4),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontFamily: 'Outfit',
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
        gradient: LinearGradient(
          colors: isInProgress
              ? [const Color(0xFF0083B0), const Color(0xFF00B4DB)]
              : [const Color(0xFF0F131D), const Color(0xFF161E2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInProgress ? Colors.transparent : const Color(0xFF00C1D4).withAlpha(50),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C1D4).withAlpha(10),
            blurRadius: 15,
            spreadRadius: 2,
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
                  const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    isInProgress ? 'NOW CALLING' : 'TRIAGE WAITING',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Outfit',
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'Outfit',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${active.estimatedWaitMinutes ?? 0}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'min estimated wait',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
          if (active.triageNotes != null && active.triageNotes!.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes_rounded, color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.triageNotes!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      fontFamily: 'Outfit',
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
      color: const Color(0xFF0F131D),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withAlpha(5), width: 1),
      ),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.createdAt.toLocal().toString().substring(0, 16),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontFamily: 'Outfit',
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
          children: const [
            Icon(Icons.history_rounded, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text(
              'No previous queue logs',
              style: TextStyle(color: Colors.white38, fontSize: 14, fontFamily: 'Outfit'),
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
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(40), width: 1),
      ),
      child: Text(
        priority.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }

  Widget _buildStatusBadge(QueueStatus status) {
    Color color;
    switch (status) {
      case QueueStatus.waiting:
        color = const Color(0xFF00C1D4);
        break;
      case QueueStatus.inProgress:
        color = const Color(0xFFFF9500);
        break;
      case QueueStatus.completed:
        color = const Color(0xFF30D158);
        break;
      case QueueStatus.cancelled:
        color = Colors.white38;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(30), width: 1),
      ),
      child: Text(
        status.name.toUpperCase().replaceAll('INPROGRESS', 'IN PROGRESS'),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }
}
