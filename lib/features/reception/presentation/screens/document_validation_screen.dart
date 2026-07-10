import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../data/reception_repository.dart';
import '../../domain/submission_detail.dart';
import '../../domain/submission_status.dart';

class DocumentValidationScreen extends StatefulWidget {
  final String submissionId;

  const DocumentValidationScreen({
    super.key,
    required this.submissionId,
  });

  @override
  State<DocumentValidationScreen> createState() => _DocumentValidationScreenState();
}

class _DocumentValidationScreenState extends State<DocumentValidationScreen> {
  late final ReceptionRepository _repository;
  bool _isLoading = true;
  SubmissionDetail? _detail;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    try {
      _repository = Provider.of<ReceptionRepository>(context, listen: false);
    } catch (_) {
      _repository = ReceptionRepository();
    }
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final detail = await _repository.getSubmissionDetail(widget.submissionId);
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _viewOriginal(String id) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final signedUrlString = await _repository.getOriginalDocumentUrl(id);
      final signedUrl = Uri.parse(signedUrlString);
      if (await canLaunchUrl(signedUrl)) {
        final success = await launchUrl(signedUrl, mode: LaunchMode.externalApplication);
        if (!success) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Could not open document'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Could not open document'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open document'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildStatusBadge(SubmissionStatus status, ThemeData theme) {
    String label = 'Pending Review';
    Color color = Colors.orange;
    if (status == SubmissionStatus.approved) {
      label = 'Approved';
      color = Colors.green;
    } else if (status == SubmissionStatus.rejected) {
      label = 'Rejected';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCardHeader(String title, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Document Validation'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/reception/queue'),
        ),
        actions: [
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: _buildStatusBadge(detail.submission.status, theme),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : detail == null
                ? Center(
                    child: Text(
                      _errorMessage ?? 'Failed to load details.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Patient Details Card
                              Card(
                                elevation: 0.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildCardHeader('Patient Details', Icons.person_outline, theme),
                                      const Divider(height: 24),
                                      _buildDetailRow('Name', detail.submission.patientName, theme),
                                      _buildDetailRow('Date of Birth', detail.patientDob, theme),
                                      _buildDetailRow('Gender', detail.patientGender, theme),
                                      _buildDetailRow('Contact Number', detail.patientContact, theme),
                                      _buildDetailRow('Email', detail.patientEmail, theme),
                                      _buildDetailRow('Address', detail.patientAddress, theme),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 2. OCR Text Output Card
                              Card(
                                elevation: 0.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildCardHeader('MONOSPACE RAW', Icons.text_snippet_outlined, theme),
                                      const Divider(height: 24),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          (detail.ocrText == null || detail.ocrText!.trim().isEmpty)
                                              ? 'No OCR text extraction available for this document.'
                                              : detail.ocrText!,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 3. AI Validation Report Card (Static Placeholder)
                              Card(
                                elevation: 0.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildCardHeader('AI Validation Report', Icons.psychology_outlined, theme),
                                      const Divider(height: 24),
                                      _buildDetailRow('Overall AI Confidence', 'No OCR Score', theme),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Confidence score not available for this upload.',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 4. Document Metadata Card
                              Card(
                                elevation: 0.5,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildCardHeader('Document Metadata', Icons.info_outline, theme),
                                      const Divider(height: 24),
                                      _buildDetailRow('File Name', detail.submission.fileName, theme),
                                      _buildDetailRow('File Type', detail.submission.fileType.toUpperCase(), theme),
                                      _buildDetailRow(
                                        'Uploaded At',
                                        detail.submission.uploadedAt.toLocal().toString().substring(0, 19),
                                        theme,
                                      ),
                                      _buildDetailRow(
                                        'Uploaded By',
                                        detail.submission.uploadedBy.isNotEmpty ? detail.submission.uploadedBy : 'Unknown Uploader',
                                        theme,
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _viewOriginal(detail.submission.id),
                                          icon: const Icon(Icons.open_in_new),
                                          label: const Text('View Original Document'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: theme.colorScheme.primary,
                                            foregroundColor: theme.colorScheme.onPrimary,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 5. Bottom Action Bar (Disabled buttons)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1))),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: 'Available soon',
                                    child: OutlinedButton(
                                      onPressed: null,
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 48),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Reject Document'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Tooltip(
                                    message: 'Available soon',
                                    child: ElevatedButton(
                                      onPressed: null,
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 48),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Approve & Route Patient'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Available soon',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
