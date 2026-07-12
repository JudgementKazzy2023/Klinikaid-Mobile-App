import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/admin_provider.dart';
import '../../../../core/models/system_log.dart';
import '../../../../core/models/chatbot_log.dart';
import '../../../../core/utils/date_formatter.dart';

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // System Event filters state
  String _eventTypeFilter = 'All';
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _textSearchController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Bind listeners to refresh logs automatically on filter change
    _userSearchController.addListener(_onFilterChanged);
    _textSearchController.addListener(_onFilterChanged);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _loadTab(context, _tabController.index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTab(context, 0);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearchController.dispose();
    _textSearchController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final provider = Provider.of<AdminProvider>(context, listen: false);
    provider.loadSystemEvents(
      eventType: _eventTypeFilter,
      userSearch: _userSearchController.text,
      textSearch: _textSearchController.text,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  void _loadTab(BuildContext context, int index) {
    final provider = Provider.of<AdminProvider>(context, listen: false);
    if (index == 0) {
      provider.loadSystemEvents(
        eventType: _eventTypeFilter,
        userSearch: _userSearchController.text,
        textSearch: _textSearchController.text,
        startDate: _startDate,
        endDate: _endDate,
      );
    } else if (index == 1) {
      provider.loadChatbotAudit();
    } else if (index == 2) {
      provider.loadApiCost();
    }
  }

  void _triggerCsvExport(List<SystemLog> logs) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Timestamp,User,Role,Event Type,Description,IP Address');
    for (final log in logs) {
      buffer.writeln('${log.id},"${log.createdAt.toIso8601String()}","${log.userName}","${log.userRole}","${log.eventType}","${log.description}","${log.ipAddress}"');
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('CSV exported successfully (mocked).'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        action: SnackBarAction(
          label: 'SHARE',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: 'System Events'),
              Tab(text: 'Chatbot Audit'),
              Tab(text: 'API Cost Tracker'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSystemEventsTab(context),
          _buildChatbotAuditTab(context),
          _buildApiCostTrackerTab(context),
        ],
      ),
    );
  }

  // --- SYSTEM EVENTS TAB ---
  Widget _buildSystemEventsTab(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);

    return Column(
      children: [
        // Filter Board
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ExpansionTile(
            title: const Text('Event Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            leading: const Icon(Icons.filter_list_rounded),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            children: [
              DropdownButtonFormField<String>(
                value: _eventTypeFilter,
                decoration: const InputDecoration(labelText: 'Event Type', border: OutlineInputBorder()),
                items: ['All', 'Security', 'Authentication', 'Configuration', 'Data Access', 'AI Model'].map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _eventTypeFilter = val);
                    _onFilterChanged();
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _userSearchController,
                decoration: const InputDecoration(labelText: 'Search User / Role', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_search_outlined)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textSearchController,
                decoration: const InputDecoration(labelText: 'Search Description', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description_outlined)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_startDate == null ? 'Start Date' : '${_startDate!.month}/${_startDate!.day}/${_startDate!.year}'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() => _startDate = date);
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_endDate == null ? 'End Date' : '${_endDate!.month}/${_endDate!.day}/${_endDate!.year}'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() => _endDate = date);
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _eventTypeFilter = 'All';
                        _userSearchController.clear();
                        _textSearchController.clear();
                        _startDate = null;
                        _endDate = null;
                      });
                      _onFilterChanged();
                    },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Action Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${provider.systemEvents.length} logs found',
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                key: const Key('btn_export_csv'),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
                onPressed: provider.systemEvents.isEmpty ? null : () => _triggerCsvExport(provider.systemEvents),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Logs List
        Expanded(
          child: provider.isLogsLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.systemEvents.isEmpty
                  ? const Center(child: Text('No events matching filters.'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: provider.systemEvents.length,
                      itemBuilder: (context, index) {
                        final log = provider.systemEvents[index];
                        return _buildSystemLogCard(context, log);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSystemLogCard(BuildContext context, SystemLog log) {
    final theme = Theme.of(context);
    final timeStr = DateFormatter.formatPht(log.createdAt);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (log.userRole.toUpperCase() == 'SYSTEM' || log.userName.toLowerCase() == 'system')
                      ? 'System'
                      : '${log.userName} (${log.userRole.toUpperCase()})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.eventType.toUpperCase(),
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(log.description, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeStr, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                Text('IP: ${log.ipAddress}', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- CHATBOT AUDIT TAB ---
  Widget _buildChatbotAuditTab(BuildContext context) {
    final provider = Provider.of<AdminProvider>(context);

    if (provider.isChatbotLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Chatbot Stats Dashboard
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: _buildLogMiniCard(
                  context,
                  'Queries Today',
                  provider.todayQueries.toString(),
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLogMiniCard(
                  context,
                  'Tokens Used',
                  provider.todayTokens.toString(),
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLogMiniCard(
                  context,
                  'Est. Cost',
                  '\$${provider.todayCost.toStringAsFixed(4)}',
                  Colors.green,
                ),
              ),
            ],
          ),
        ),

        // Chatbot Audit List
        Expanded(
          child: provider.chatbotLogs.isEmpty
              ? const Center(child: Text('No chatbot logs found.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: provider.chatbotLogs.length,
                  itemBuilder: (context, index) {
                    final log = provider.chatbotLogs[index];
                    return _buildChatbotLogCard(context, log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogMiniCard(BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatbotLogCard(BuildContext context, ChatbotLog log) {
    final theme = Theme.of(context);
    final timeStr = DateFormatter.formatPhtCompact(log.createdAt);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Session: ${log.sessionId.length > 8 ? "${log.sessionId.substring(0, 8)}..." : log.sessionId}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(timeStr, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Q: ${log.userMessage}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('A: ${log.botResponse}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tokens: ${log.tokensUsed}', style: const TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                if (log.feedback != null)
                  Icon(
                    log.feedback == FeedbackType.helpful ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
                    size: 14,
                    color: log.feedback == FeedbackType.helpful ? Colors.green : Colors.red,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- API COST TRACKER TAB ---
  Widget _buildApiCostTrackerTab(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);

    if (provider.isCostLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 30-Day Token Consumption Title
          Text('Token Consumption (30 Days)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Line Chart
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 24, 12),
              child: SizedBox(
                height: 180,
                child: provider.costChartData.isEmpty
                    ? const Center(child: Text('No chart data available.'))
                    : _buildCostLineChart(context, provider.costChartData),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Weekly Breakdown Table Title
          Text('Weekly Cost Breakdown', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Breakdown List
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: provider.weeklyBreakdown.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final week = provider.weeklyBreakdown[index];
                return ListTile(
                  title: Text(week['label'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(week['range'] as String, style: const TextStyle(fontSize: 11)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('\$${(week['cost'] as double).toStringAsFixed(4)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 2),
                      Text('${week['tokens']} tokens', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostLineChart(BuildContext context, List<Map<String, dynamic>> chartData) {
    final theme = Theme.of(context);
    
    // Create spots from token consumption
    final List<FlSpot> spots = [];
    double maxTokens = 1000.0;
    for (int i = 0; i < chartData.length; i++) {
      final tokens = (chartData[i]['tokens'] as int).toDouble();
      if (tokens > maxTokens) {
        maxTokens = tokens;
      }
      spots.add(FlSpot(i.toDouble(), tokens));
    }

    final double verticalInterval = maxTokens / 4;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (chartData.length - 1).toDouble(),
        minY: 0,
        maxY: maxTokens * 1.1,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            left: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: verticalInterval,
              getTitlesWidget: (value, meta) {
                return Text(
                  value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString(),
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 7.0, // Label every week
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < chartData.length) {
                  final dateStr = chartData[index]['date'] as String;
                  // Output: MM/DD
                  final parts = dateStr.split('-');
                  if (parts.length == 3) {
                    return SideTitleWidget(
                      meta: meta,
                      child: Text('${parts[1]}/${parts[2]}', style: const TextStyle(fontSize: 8)),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2,
            color: Colors.blue.shade700,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.shade700.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
