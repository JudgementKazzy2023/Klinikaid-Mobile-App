import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../../core/models/patient_queue.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
    if (authProvider.patient != null && authProvider.user != null) {
      await dashboardProvider.fetchDashboardData(
        authProvider.patient!.id,
        authProvider.user!.id,
      );
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final patient = authProvider.patient;
    
    if (patient == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0E14),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2E5BFF)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: const Color(0xFF2E5BFF),
            backgroundColor: const Color(0xFF0F131D),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top App Bar with premium feel
                SliverAppBar(
                  expandedHeight: 120.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: const Color(0xFF0F131D),
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Text(
                      'KlinikAid',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                        fontSize: 22,
                        letterSpacing: 0.5,
                      ),
                    ),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F131D), Color(0xFF0B0E14)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),

                // Offline Notice
                if (provider.isOffline)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9900).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF9900).withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF9900), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Offline Mode',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Displaying cached clinic data. Reconnect to sync.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Dashboard Content
                SliverPadding(
                  padding: const EdgeInsets.all(16.0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Greeting Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F131D),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 14,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              patient.fullName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E5BFF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.shield_outlined, color: Color(0xFF2E5BFF), size: 14),
                                  SizedBox(width: 6),
                                  Text(
                                    'BSIT Capstone — KlinikAid Patient Client',
                                    style: TextStyle(
                                      color: Color(0xFF2E5BFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      const Text(
                        'Status Summary',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (provider.isLoading && provider.pendingDocumentsCount == 0 && provider.activeQueueEntry == null && provider.latestRecord == null)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40.0),
                            child: CircularProgressIndicator(color: Color(0xFF2E5BFF)),
                          ),
                        )
                      else ...[
                        // Pending Submissions Card
                        _buildStatusCard(
                          context: context,
                          title: 'Pending Submissions',
                          icon: Icons.document_scanner_outlined,
                          iconColor: const Color(0xFF2E5BFF),
                          onTap: () => context.go('/documents/status'),
                          child: Row(
                            children: [
                              Text(
                                '${provider.pendingDocumentsCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Pending document approvals',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Queue Status Card
                        _buildStatusCard(
                          context: context,
                          title: 'Triage Queue Status',
                          icon: Icons.people_outline,
                          iconColor: const Color(0xFF00C1D4),
                          onTap: () => context.go('/queue'),
                          child: provider.activeQueueEntry != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Department: ${provider.activeQueueEntry!.department.toJsonValue().toUpperCase()}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            fontFamily: 'Outfit',
                                          ),
                                        ),
                                        _buildPriorityBadge(provider.activeQueueEntry!.priorityLevel),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Estimated Wait: ${provider.activeQueueEntry!.estimatedWaitMinutes ?? 0} mins',
                                      style: const TextStyle(
                                        color: Color(0xFF00C1D4),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                    if (provider.activeQueueEntry!.triageNotes != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Notes: ${provider.activeQueueEntry!.triageNotes}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ]
                                  ],
                                )
                              : const Text(
                                  'Not currently in triage queue.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                        ),

                        const SizedBox(height: 16),

                        // Latest Result Card
                        _buildStatusCard(
                          context: context,
                          title: 'Latest Lab Result',
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF9E00FF),
                          onTap: () => context.go('/records'),
                          child: provider.latestRecord != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      provider.latestRecord!.testType,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Department: ${provider.latestRecord!.department.toJsonValue().toUpperCase()}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Recorded: ${provider.latestRecord!.createdAt.toLocal().toString().substring(0, 16)}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'No clinical records found.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F131D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 14,
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            child,
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
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
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
}
