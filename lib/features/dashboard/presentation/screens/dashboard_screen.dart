import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../features/auth/domain/patient_record_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../../../core/models/patient_queue.dart';
import '../../../../core/utils/triage_notes_formatter.dart';
import '../../../../core/utils/queue_status_formatter.dart';
import '../../../../core/utils/date_formatter.dart';

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

  /// Re-runs the patient record lookup and loads the dashboard once it
  /// succeeds. Leaves the surface in its error state when the read fails
  /// again.
  Future<void> _retryPatientLookup() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.retryPatientLookup();
    if (!mounted) return;
    if (authProvider.patient != null) {
      await _refreshData();
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
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _buildPatientRecordState(context, authProvider),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Consumer<DashboardProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).cardColor,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Top App Bar
                SliverAppBar(
                  expandedHeight: 120.0,
                  floating: false,
                  pinned: true,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Text(
                      'KlinikAid',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: 0.5,
                      ),
                    ),
                    background: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
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
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Offline Mode',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Displaying cached clinic data. Reconnect to sync.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 12,
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
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              patient.fullName,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    'BSIT Capstone — KlinikAid Patient Client',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Text(
                        'Status Summary',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (provider.isLoading && provider.pendingDocumentsCount == 0 && provider.activeQueueEntry == null && provider.latestRecord == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40.0),
                            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                          ),
                        )
                      else ...[
                        // Document Templates Card
                        _buildStatusCard(
                          context: context,
                          title: 'Document Templates',
                          icon: Icons.assignment_outlined,
                          iconColor: Theme.of(context).colorScheme.primary,
                          onTap: () => context.go('/patient/templates'),
                          child: Row(
                            children: [
                              Icon(
                                Icons.note_add_outlined,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                size: 28,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  'Fill and submit structured forms directly to reception',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Pending Submissions Card
                        _buildStatusCard(
                          context: context,
                          title: 'Pending Submissions',
                          icon: Icons.document_scanner_outlined,
                          iconColor: Theme.of(context).colorScheme.primary,
                          onTap: () => context.go('/documents/status'),
                          child: Row(
                            children: [
                              Text(
                                '${provider.pendingDocumentsCount}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Pending document approvals',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                  fontSize: 14,
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
                          iconColor: Theme.of(context).colorScheme.primary,
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
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        _buildPriorityBadge(provider.activeQueueEntry!.priorityLevel),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Builder(builder: (context) {
                                      final format = formatQueueStatus(provider.activeQueueEntry!.status);
                                      return Text(
                                        format.patientBodyText,
                                        style: TextStyle(
                                          color: format.color,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    }),
                                    Builder(builder: (context) {
                                      final notes = extractTriageNotes(provider.activeQueueEntry!.triageNotes);
                                      if (notes == null) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          'Notes: $notes',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                )
                              : Text(
                                  'Not currently in triage queue.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                ),
                        ),

                        const SizedBox(height: 16),

                        // Latest Result Card
                        _buildStatusCard(
                          context: context,
                          title: 'Latest Lab Result',
                          icon: Icons.receipt_long_outlined,
                          iconColor: Theme.of(context).colorScheme.primary,
                          onTap: () => context.go('/records'),
                          child: provider.latestRecord != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      provider.latestRecord!.testType,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Department: ${provider.latestRecord!.department.toJsonValue().toUpperCase()}',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Recorded: ${DateFormatter.formatPht(provider.latestRecord!.createdAt)}',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'No clinical records found.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontSize: 14,
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

  /// Builds the surface shown when the patient record for the active account
  /// is not available.
  ///
  /// A failed read and a missing row are different problems and get different
  /// surfaces: the failed read is retryable, the missing row is not, so it
  /// offers a way out instead of a retry that cannot succeed.
  Widget _buildPatientRecordState(BuildContext context, AuthProvider authProvider) {
    switch (authProvider.patientRecordState) {
      case PatientRecordState.failed:
        return _PatientRecordNotice(
          icon: Icons.cloud_off_rounded,
          iconColor: Theme.of(context).colorScheme.error,
          title: 'Could not load your patient record',
          message: authProvider.patientRecordError ??
              'We could not retrieve your patient record details. Please try again.',
          actions: [
            ElevatedButton.icon(
              onPressed: _retryPatientLookup,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        );
      case PatientRecordState.missing:
        return _PatientRecordNotice(
          icon: Icons.person_off_outlined,
          iconColor: Theme.of(context).colorScheme.primary,
          title: 'Patient record not found',
          message: 'We could not retrieve your patient record details. '
              'Please contact clinic staff to link your authentication account.',
          actions: [
            OutlinedButton.icon(
              onPressed: _retryPatientLookup,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
            ),
            TextButton(
              onPressed: () => authProvider.signOut(),
              child: const Text('Sign Out'),
            ),
          ],
        );
      case PatientRecordState.loaded:
      case PatientRecordState.loading:
      case PatientRecordState.unknown:
        return Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        );
    }
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
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  size: 14,
                ),
              ],
            ),
            Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), height: 24),
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
        ),
      ),
    );
  }
}

/// Explains why the patient dashboard has no data and offers the way out.
class _PatientRecordNotice extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;

  const _PatientRecordNotice({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
