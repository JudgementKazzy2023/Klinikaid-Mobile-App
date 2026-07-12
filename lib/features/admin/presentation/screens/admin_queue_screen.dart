import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/admin_provider.dart';
import '../../../../core/utils/date_formatter.dart';

class AdminQueueScreen extends StatefulWidget {
  const AdminQueueScreen({super.key});

  @override
  State<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends State<AdminQueueScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AdminProvider>(context, listen: false);
      provider.loadQueue();
      provider.loadDashboard();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getStatusLabel(String dbStatus) {
    switch (dbStatus.toLowerCase()) {
      case 'pending':
        return 'Submitted';
      case 'ai_verified':
        return 'AI-Verified';
      case 'staff_review':
        return 'Staff Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return dbStatus[0].toUpperCase() + dbStatus.substring(1);
    }
  }

  Color _getStatusColor(String dbStatus) {
    switch (dbStatus.toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'ai_verified':
        return Colors.teal;
      case 'staff_review':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);

    if (provider.isQueueLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.queueError != null) {
      return _buildErrorState(context, provider.queueError!, () => provider.loadQueue());
    }

    final submissions = provider.queueSubmissions;

    // Calculate Counts per Status Group
    int countSubmitted = 0;
    int countAiVerified = 0;
    int countStaffReview = 0;
    int countApproved = 0;
    int countRejected = 0;

    for (final sub in submissions) {
      final status = sub['status'] as String? ?? 'pending';
      switch (status.toLowerCase()) {
        case 'pending':
          countSubmitted++;
          break;
        case 'ai_verified':
          countAiVerified++;
          break;
        case 'staff_review':
          countStaffReview++;
          break;
        case 'approved':
          countApproved++;
          break;
        case 'rejected':
          countRejected++;
          break;
      }
    }

    final filteredSubmissions = submissions.where((sub) {
      final patientName = (sub['patientName'] as String? ?? '').toLowerCase();
      final fileName = (sub['fileName'] as String? ?? '').toLowerCase();
      final status = sub['status'] as String? ?? 'pending';

      final matchesSearch = patientName.contains(_searchQuery) || fileName.contains(_searchQuery);
      
      bool matchesStatus = _statusFilter == 'All';
      if (_statusFilter == 'Submitted') matchesStatus = status.toLowerCase() == 'pending';
      if (_statusFilter == 'AI-Verified') matchesStatus = status.toLowerCase() == 'ai_verified';
      if (_statusFilter == 'Staff Review') matchesStatus = status.toLowerCase() == 'staff_review';
      if (_statusFilter == 'Approved') matchesStatus = status.toLowerCase() == 'approved';
      if (_statusFilter == 'Rejected') matchesStatus = status.toLowerCase() == 'rejected';

      return matchesSearch && matchesStatus;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Status Counts Summary Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  _buildCountChip(context, 'All', submissions.length, _statusFilter == 'All', () {
                    setState(() => _statusFilter = 'All');
                  }),
                  _buildCountChip(context, 'Submitted', countSubmitted, _statusFilter == 'Submitted', () {
                    setState(() => _statusFilter = 'Submitted');
                  }),
                  _buildCountChip(context, 'AI-Verified', countAiVerified, _statusFilter == 'AI-Verified', () {
                    setState(() => _statusFilter = 'AI-Verified');
                  }),
                  _buildCountChip(context, 'Staff Review', countStaffReview, _statusFilter == 'Staff Review', () {
                    setState(() => _statusFilter = 'Staff Review');
                  }),
                  _buildCountChip(context, 'Approved', countApproved, _statusFilter == 'Approved', () {
                    setState(() => _statusFilter = 'Approved');
                  }),
                  _buildCountChip(context, 'Rejected', countRejected, _statusFilter == 'Rejected', () {
                    setState(() => _statusFilter = 'Rejected');
                  }),
                ],
              ),
            ),

            // Search Box
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by patient name or file...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                ),
              ),
            ),

            // Queue List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.loadQueue(),
                child: filteredSubmissions.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.builder(
                        padding: const EdgeInsets.all(16.0),
                        itemCount: filteredSubmissions.length,
                        itemBuilder: (context, index) {
                          final sub = filteredSubmissions[index];
                          return _buildQueueCard(context, sub);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountChip(
    BuildContext context,
    String label,
    int count,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildQueueCard(BuildContext context, Map<String, dynamic> sub) {
    final theme = Theme.of(context);
    final status = sub['status'] as String? ?? 'pending';
    final statusLabel = _getStatusLabel(status);
    final statusColor = _getStatusColor(status);
    final uploadedAt = sub['createdAt'] as DateTime? ?? DateTime.now();
    final timeStr = DateFormatter.formatPhtCompact(uploadedAt);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: () {
          final docId = sub['id'] as String;
          context.go('/admin/document/$docId');
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    sub['patientName'] as String? ?? 'Unknown Patient',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sub['fileName'] as String? ?? '',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploaded: $timeStr by ${sub['uploadedBy']}',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
                Text(
                  sub['fileType'] as String? ?? '',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No queue submissions found.'),
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
              'Failed to load queue submissions: $error',
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
