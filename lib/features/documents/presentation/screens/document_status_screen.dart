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
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text(
          'Document Submissions',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
      ),
      body: Consumer<DocumentStatusProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.documents.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E5BFF)),
            );
          }

          if (provider.errorMessage != null && provider.documents.isEmpty) {
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
                        backgroundColor: const Color(0xFF2E5BFF),
                      ),
                      onPressed: _loadDocuments,
                      child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadDocuments(),
            color: const Color(0xFF2E5BFF),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: provider.isOffline
            ? const Color(0xFFFF9900).withAlpha(15)
            : const Color(0xFF2E5BFF).withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: provider.isOffline
              ? const Color(0xFFFF9900).withAlpha(30)
              : const Color(0xFF2E5BFF).withAlpha(30),
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
              color: provider.isOffline ? const Color(0xFFFF9900) : const Color(0xFF2E5BFF),
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

  Widget _buildDocumentCard(Document doc) {
    final isRejected = doc.status == DocumentStatus.rejected;
    final isApproved = doc.status == DocumentStatus.approved;

    return Card(
      color: const Color(0xFF0F131D),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isRejected
              ? const Color(0xFFFF453A).withAlpha(30)
              : (isApproved ? const Color(0xFF30D158).withAlpha(30) : Colors.white.withAlpha(5)),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
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
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Format: ${doc.fileType.toUpperCase()}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontFamily: 'Outfit',
              ),
            ),

            // If rejected, show the rejection reason in a clean alert box (Reconciliation rule)
            if (isRejected && doc.rejectionReason != null && doc.rejectionReason!.isNotEmpty) ...[
              const Divider(color: Colors.white10, height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A).withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF453A).withAlpha(30), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.report_problem_rounded, color: Color(0xFFFF453A), size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Rejection Reason:',
                          style: TextStyle(
                            color: Color(0xFFFF453A),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      doc.rejectionReason!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                        fontFamily: 'Outfit',
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
    Color color;
    switch (status) {
      case DocumentStatus.pending:
        color = const Color(0xFFFF9F0A);
        break;
      case DocumentStatus.approved:
        color = const Color(0xFF30D158);
        break;
      case DocumentStatus.rejected:
        color = const Color(0xFFFF453A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(30), width: 1),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Outfit',
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
                color: Colors.white.withAlpha(5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 64,
                color: Colors.white24,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Submissions Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Uploaded referrals and diagnostics status logs will render here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 13,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
