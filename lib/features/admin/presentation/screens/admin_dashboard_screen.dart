import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/admin_provider.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/utils/date_formatter.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);

    if (provider.isDashboardLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.dashboardError != null) {
      return _buildErrorState(context, provider.dashboardError!, () => provider.loadDashboard());
    }

    final data = provider.dashboardData ?? {};
    final int todayPatients = data['todayPatients'] as int? ?? 0;
    final int pendingReviews = data['pendingReviews'] as int? ?? 0;
    final int activeStaff = data['activeStaff'] as int? ?? 0;
    final int chatbotQueries = data['chatbotQueries'] as int? ?? 0;
    final Map<String, int> workload = Map<String, int>.from(data['departmentWorkload'] as Map? ?? {});
    final List<SystemLog> recentEvents = List<SystemLog>.from(data['recentEvents'] as List? ?? []);

    return RefreshIndicator(
      onRefresh: () => provider.loadDashboard(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stat Cards Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final double itemWidth = (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildStatCard(
                      context: context,
                      width: itemWidth,
                      title: "Today's Patients",
                      value: todayPatients.toString(),
                      icon: Icons.personal_injury_outlined,
                      color: Colors.blue.shade700,
                    ),
                    _buildStatCard(
                      context: context,
                      width: itemWidth,
                      title: 'Pending Reviews',
                      value: pendingReviews.toString(),
                      icon: Icons.rate_review_outlined,
                      color: Colors.amber.shade700,
                    ),
                    _buildStatCard(
                      context: context,
                      width: itemWidth,
                      title: 'Active Staff',
                      value: activeStaff.toString(),
                      icon: Icons.people_outline_rounded,
                      color: Colors.green.shade700,
                    ),
                    _buildStatCard(
                      context: context,
                      width: itemWidth,
                      title: 'Chatbot Queries',
                      value: chatbotQueries.toString(),
                      icon: Icons.chat_bubble_outline_rounded,
                      color: Colors.purple.shade700,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Workload Bar Chart Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Department Workload Today',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Patient queue volume per department',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 180,
                      child: _buildBarChart(context, workload),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Recent System Events
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent System Events',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          Icons.security_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (recentEvents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Center(child: Text('No recent system events.')),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recentEvents.length,
                        separatorBuilder: (_, __) => Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        itemBuilder: (context, index) {
                          final log = recentEvents[index];
                          return _buildEventItem(context, log);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required double width,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(BuildContext context, Map<String, int> workload) {
    final theme = Theme.of(context);
    final depts = ['laboratory', 'imaging', 'ultrasound', 'ecg'];
    final labels = ['Lab', 'Imaging', 'Ultrasound', 'ECG'];
    final colors = [
      const Color(0xFF047857), // Green
      const Color(0xFF4338CA), // Indigo
      const Color(0xFF0F766E), // Teal
      const Color(0xFFBE123C), // Rose
    ];

    double maxVal = 5.0;
    for (var key in depts) {
      final val = workload[key] ?? 0;
      if (val > maxVal) {
        maxVal = val.toDouble();
      }
    }
    maxVal = maxVal + 1; // Extra padding at top

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.primaryContainer,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${labels[groupIndex]}: ${rod.toY.round()} patients',
                TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                if (value % 1 != 0) return const SizedBox.shrink();
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      labels[index],
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(depts.length, (i) {
          final count = workload[depts[i]] ?? 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: colors[i],
                width: 24,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildEventItem(BuildContext context, SystemLog log) {
    final theme = Theme.of(context);
    final timeStr = DateFormatter.formatPht(log.createdAt);

    Color logColor = theme.colorScheme.primary;
    if (log.eventType.toLowerCase().contains('security') || log.eventType.toLowerCase().contains('auth')) {
      logColor = Colors.orange.shade700;
    } else if (log.eventType.toLowerCase().contains('config')) {
      logColor = Colors.purple.shade700;
    } else if (log.eventType.toLowerCase().contains('error')) {
      logColor = theme.colorScheme.error;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: logColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              log.eventType.toLowerCase().contains('security')
                  ? Icons.lock_outline_rounded
                  : (log.eventType.toLowerCase().contains('auth') ? Icons.login_rounded : Icons.info_outline_rounded),
              size: 14,
              color: logColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (log.userRole.trim().isEmpty || log.userName.toLowerCase() == 'system')
                          ? 'System'
                          : '${log.userName} (${log.userRole.toUpperCase()})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      log.ipAddress,
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  log.description,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
