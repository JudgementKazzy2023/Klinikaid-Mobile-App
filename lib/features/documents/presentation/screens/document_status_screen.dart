import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/models/document.dart';
import '../providers/document_status_provider.dart';

class DocumentStatusScreen extends StatefulWidget {
  const DocumentStatusScreen({super.key});

  @override
  State<DocumentStatusScreen> createState() => _DocumentStatusScreenState();
}

class _DocumentStatusScreenState extends State<DocumentStatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDocuments();
    });
  }

  void _loadDocuments() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      context.read<DocumentStatusProvider>().fetchDocumentsAndSubscribe(authProvider.user!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Document Submissions',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Consumer<DocumentStatusProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.documents.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
            );
          }

          if (provider.errorMessage != null && provider.documents.isEmpty) {
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
                      onPressed: _loadDocuments,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadDocuments(),
            color: Theme.of(context).colorScheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Live Connection Status Banner
                _buildRealtimeBanner(provider),
                const SizedBox(height: 16),

                if (provider.documents.isEmpty)
                  _buildEmptyState()
                else
                  ...provider.documents.map((doc) => _buildDocumentCard(doc)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRealtimeBanner(DocumentStatusProvider provider) {
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

  Widget _buildDocumentCard(Document doc) {
    final isRejected = doc.status == DocumentStatus.rejected;
    final isApproved = doc.status == DocumentStatus.approved;

    return Card(
      color: Theme.of(context).cardColor,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRejected
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.3)
              : (isApproved ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3) : Theme.of(context).colorScheme.outline),
          width: 1.2,
        ),
      ),
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
                    doc.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusBadge(doc.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Submitted: ${doc.createdAt.toLocal().toString().substring(0, 16)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Format: ${doc.fileType.toUpperCase()}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),

            // If rejected, show the rejection reason in a clean alert box
            if (isRejected && doc.rejectionReason != null && doc.rejectionReason!.isNotEmpty) ...[
              Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.report_problem_rounded, color: Theme.of(context).colorScheme.error, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Rejection Reason:',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      doc.rejectionReason!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DocumentStatus status) {
    Color bgColor;
    Color fgColor;
    switch (status) {
      case DocumentStatus.pending:
        bgColor = Theme.of(context).colorScheme.secondary;
        fgColor = Theme.of(context).colorScheme.onSurface;
        break;
      case DocumentStatus.approved:
        bgColor = Theme.of(context).colorScheme.primary;
        fgColor = Theme.of(context).colorScheme.onPrimary;
        break;
      case DocumentStatus.rejected:
        bgColor = Theme.of(context).colorScheme.error;
        fgColor = Colors.white;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: fgColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64.0, horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Submissions Yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uploaded referrals and diagnostics status logs will render here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
