import '../../data/upload_image.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:file_selector/file_selector.dart' as files;
import '../../../auth/presentation/screens/verification_code_screen.dart';
import '../../../auth/presentation/screens/consent_screen.dart';
import '../../../reception/presentation/widgets/change_password_modal.dart';
import 'dart:io';
import '../../../../core/patient_submission_containment.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/document_submission_provider.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/cache/local_database.dart';
import '../../../ocr/domain/quality_assessment.dart';
import '../../../ocr/domain/quality_thresholds.dart';
import '../../clinic_test_catalog.dart';
import '../../../../features/patient/templates/document_templates.dart';

class SubmitDocumentScreen extends StatefulWidget {
  const SubmitDocumentScreen({super.key});

  @override
  State<SubmitDocumentScreen> createState() => _SubmitDocumentScreenState();
}

class _SubmitDocumentScreenState extends State<SubmitDocumentScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _selectedDocumentType;
  List<String> _selectedTestIds = [];
  String? _initializedDetectionSignature;

  // Opening/resuming this screen must never replay drafts. Phase 2 requires
  // explicit owner-aware reconciliation before any queued submission.

  Future<void> _pickImage(ImageSource source, Patient patient) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85, // Balance size and quality for OCR text readability
      );

      if (image != null && mounted) await _useImage(image.path, patient);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select image: $e'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  /// Converts the picked image if needed, then runs on-device OCR and test
  /// detection. Used by Camera, Gallery and the file chooser.
  Future<void> _useImage(String imagePath, Patient patient) async {
    // WebP/HEIC from the photo picker become a JPEG the server accepts.
    final uploadable = await ensureUploadableImage(imagePath);
    if (!mounted) return;
    final provider = Provider.of<DocumentSubmissionProvider>(
      context,
      listen: false,
    );
    await provider.processOnDeviceOcr(uploadable, patient);
    if (!mounted) return;
    final detectedTests = provider.detectedTests;
    setState(() {
      _selectedTestIds = detectedTests.map((test) => test.id).toList();
      _initializedDetectionSignature = _detectionSignature(detectedTests);
    });
  }

  Future<void> _pickFile(Patient patient) async {
    if (PatientSubmissionContainment.isActive) return;
    try {
      final file = await files.openFile(
        acceptedTypeGroups: [
          const files.XTypeGroup(
            label: 'PDF, JPG or PNG',
            extensions: ['pdf', 'jpg', 'jpeg', 'png'],
            mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      if (file.path.toLowerCase().endsWith('.pdf')) {
        await context.read<DocumentSubmissionProvider>().selectPdf(file.path);
      } else {
        await _useImage(file.path, patient);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Choose a readable PDF, JPG or PNG up to 5 MB. Your saved drafts are still here.',
            ),
          ),
        );
      }
    }
  }


  String _draftSummary(OfflineDocument doc) {
    try {
      final saved =
          jsonDecode(doc.submissionContent ?? doc.extractedMetadata ?? '{}')
              as Map;
      final category = saved['category'] ?? saved['document_type'] ?? 'other';
      final matches = clinicTemplates.where((t) => t.id == category);
      final label = matches.isEmpty ? 'Other' : matches.first.name;
      final selected = saved['selected'] ?? saved['selected_tests'];
      final tests = selected == null
          ? 'All detected tests'
          : (selected as List)
                .map((value) {
                  final id = value is Map ? value['id'] : value;
                  final matches = clinicTestCatalog.where((t) => t.id == id);
                  return matches.isEmpty ? id.toString() : matches.first.label;
                })
                .join(', ');
      return '${doc.fileName}\nCategory: $label\nTests: ${tests.isEmpty ? "None selected" : tests}';
    } catch (_) {
      return '${doc.fileName}\nThis draft needs clinic review.';
    }
  }

  Future<void> _remediate(DocumentSubmissionProvider provider) async {
    switch (provider.remediationRoute) {
      case '/login':
        await context.read<AuthProvider>().signOut();
        if (mounted) context.go('/login');
      case '/verify':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const VerificationCodeScreen(),
          ),
        );
        if (mounted) provider.resumeAfterAccountFlow();
      case '/consent':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ConsentScreen()));
        if (mounted) provider.resumeAfterAccountFlow();
      case 'change-password':
        final changed = await showDialog<bool>(
          context: context,
          builder: (_) => const ChangePasswordModal(),
        );
        if (mounted && changed == true) provider.resumeAfterAccountFlow();
    }
  }

  Future<void> _resolveDraft(
    OfflineDocument doc,
    DocumentSubmissionProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review saved draft'),
        content: Text(
          '${_draftSummary(doc)}\nThis action checks any uncertain outcome first, then submits only this draft if the server confirms it was not committed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check and submit this draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final done = await provider.resolveQueuedDraft(doc.id);
    if (!mounted) return;
    if (done)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Submission confirmed.')));
    else
      await _remediate(provider);
  }

  void _clearSelection() {
    if (mounted) {
      setState(() {
        _selectedDocumentType = null;
        _selectedTestIds = [];
        _initializedDetectionSignature = null;
      });
      Provider.of<DocumentSubmissionProvider>(
        context,
        listen: false,
      ).clearOcrState();
    }
  }

  Future<void> _submit(Patient patient) async {
    if (PatientSubmissionContainment.isActive) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (_selectedDocumentType == null) {
      scaffoldMessenger.clearSnackBars();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a Document Type before submitting.'),
          backgroundColor: Color(0xFFFF3B30),
        ),
      );
      return;
    }

    final provider = Provider.of<DocumentSubmissionProvider>(
      context,
      listen: false,
    );
    final fullPath = provider.selectedImagePath;
    if (fullPath == null) return;

    final metadata = provider.preScreenMetadata;
    final qualityAssessmentMap =
        metadata?['quality_assessment'] as Map<String, dynamic>?;
    final QualityAssessment? assessment = qualityAssessmentMap != null
        ? QualityAssessment.fromJson(qualityAssessmentMap)
        : null;

    if (assessment != null &&
        assessment.score <= QualityThresholds.kPoorQualityThreshold) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Submission'),
          content: const Text(
            'This document is poor quality. Are you sure you want to submit it? There is a higher chance the clinic will reject it. You can retake for a clearer photo, or submit as-is.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit Anyway'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
    }

    final originalName = fullPath.split('/').last.split('\\').last;
    final ext = originalName.contains('.')
        ? originalName.split('.').last
        : 'jpg';

    final success = await provider.submitDocument(
      localFilePath: fullPath,
      originalFileName: originalName,
      fileExtension: ext,
      patient: patient,
      documentType: _selectedDocumentType!,
      selectedTestIds: _selectedTestIds,
    );

    if (mounted) {
      scaffoldMessenger.clearSnackBars();
      if (success) {
        final isOffline =
            provider.errorMessage != null &&
            provider.errorMessage!.contains('offline');
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              isOffline
                  ? 'Offline mode: Document queued locally.'
                  : 'Document submitted successfully!',
            ),
            backgroundColor: isOffline
                ? Colors.orange
                : const Color(0xFF34C759),
          ),
        );
        _clearSelection();
      } else {
        await _remediate(provider);
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              provider.errorMessage ?? 'Submission could not be confirmed.',
            ),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PatientSubmissionContainment.isActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Submit Document')),
        body: SafeArea(
          child: Consumer<DocumentSubmissionProvider>(
            builder: (context, provider, child) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(PatientSubmissionContainment.message),
                const SizedBox(height: 16),
                const Text(
                  'Existing saved drafts are kept on this device. '
                  'They will not be submitted automatically. '
                  'Previously submitted documents remain available in Records.',
                ),
                const SizedBox(height: 24),
                for (final doc in provider.queuedSubmissions)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(doc.fileName),
                    subtitle: const Text(
                      'Saved draft - submission unavailable',
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final authProvider = Provider.of<AuthProvider>(context);
    final patient = authProvider.patient;

    if (patient == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Submit Document',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Consumer<DocumentSubmissionProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (provider.isProcessing)
                  _buildProcessingSpinner()
                else if (!provider.hasCachedSubmission)
                  Column(
                    children: [_buildUploadCard(patient), _buildFilePicker(patient)],
                  )
                else
                  _buildPreviewAndValidationCard(patient, provider),

                const SizedBox(height: 24),

                if (provider.isLoading && provider.advisoryMessage != null)
                  Text(provider.advisoryMessage!),
                if (provider.errorMessage != null) ...[
                  Text(
                    provider.errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  for (final error in provider.fieldErrors.entries)
                    Text(
                      '${error.key}: ${error.value}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (provider.duplicateDocumentId != null)
                    TextButton(
                      onPressed: () => context.push(
                        Uri(
                          path: '/documents/status',
                          queryParameters: {
                            'document_id': provider.duplicateDocumentId!,
                          },
                        ).toString(),
                      ),
                      child: const Text('View pending document in my records'),
                    ),
                ],
                // Queued Offline Documents Section (current account only)
                if (provider.queuedSubmissions.isNotEmpty) ...[
                  Text(
                    'Saved drafts — review individually',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...provider.queuedSubmissions.map(
                    (doc) => _buildQueueItem(doc, provider),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProcessingSpinner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Analyzing document quality — this may take up to 10 seconds. Please wait.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildUploadCard(Patient patient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_upload_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Upload Diagnostic Referrals',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capture a document with your camera or select from gallery. On-device AI will process details before uploading.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _pickImage(ImageSource.camera, patient),
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: const Text(
                    'Camera',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _pickImage(ImageSource.gallery, patient),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text(
                    'Gallery',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilePicker(Patient patient) => TextButton.icon(
    onPressed: () => _pickFile(patient),
    icon: const Icon(Icons.upload_file_outlined),
    label: const Text('Choose a file: PDF, JPG or PNG (up to 5 MB)'),
  );

  Widget _buildPreviewAndValidationCard(
    Patient patient,
    DocumentSubmissionProvider provider,
  ) {
    final metadata = provider.preScreenMetadata;
    final detectedTests = provider.detectedTests;
    final detectionSignature = _detectionSignature(detectedTests);
    if (detectedTests.isNotEmpty &&
        _initializedDetectionSignature != detectionSignature) {
      _selectedTestIds = detectedTests.map((test) => test.id).toList();
      _initializedDetectionSignature = detectionSignature;
    }

    final qualityAssessmentMap =
        metadata?['quality_assessment'] as Map<String, dynamic>?;
    final QualityAssessment? assessment = qualityAssessmentMap != null
        ? QualityAssessment.fromJson(qualityAssessmentMap)
        : null;

    final bool identityMatch = metadata?['identity_match'] as bool? ?? true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Document Review',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                onPressed: provider.isLoading ? null : _clearSelection,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // File image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildImagePreview(provider.selectedImagePath!),
          ),

          const SizedBox(height: 20),

          // OCR Loader or Checklist
          if (provider.isProcessingOcr)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AI Processing document OCR on-device...',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Document Quality Assessment',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // A. The traffic light card (prominent)
            if (assessment != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: assessment.verdictColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: assessment.verdictColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: assessment.verdictColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: assessment.verdictColor.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assessment.verdictLabel,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Quality Score: ${assessment.score}/100',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (assessment.score <
                              QualityThresholds.minOcrPassScore) ...[
                            const SizedBox(height: 8),
                            Text(
                              'This document may be hard to read (blurry / illegible text detected). You can submit as-is or retake for a clearer photo.',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.8),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // B. Issue List (rendered if issues are present and score is below threshold)
            if (assessment != null &&
                assessment.score < QualityThresholds.minOcrPassScore &&
                assessment.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Identified Quality Issues',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...assessment.issues.map((issue) {
                final IconData icon = switch (issue.severity) {
                  QualityIssueSeverity.high => Icons.error_outline_rounded,
                  QualityIssueSeverity.medium => Icons.warning_amber_rounded,
                  QualityIssueSeverity.low => Icons.info_outline_rounded,
                };
                final Color color = switch (issue.severity) {
                  QualityIssueSeverity.high => Colors.red.shade700,
                  QualityIssueSeverity.medium => Colors.orange.shade800,
                  QualityIssueSeverity.low => Colors.blue.shade700,
                };

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          issue.description,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            // C. Identity-match warning (if applicable, separate card)
            if (!identityMatch) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Name Mismatch Warning',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your name was not found on this document. If this document does belong to you, you may still submit it for receptionist review.',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (detectedTests.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildDetectedTestsSelection(detectedTests, provider.isLoading),
            ],

            const SizedBox(height: 20),
            Text(
              'Select Document Type *',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              forceErrorText: provider.fieldErrors['document_type'],
              key: const Key('document_type_picker'),
              initialValue: _selectedDocumentType,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                hintText: 'Select a category',
              ),
              items: [
                ...clinicTemplates.map(
                  (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                ),
                const DropdownMenuItem(
                  value: 'other',
                  child: Text('Other / Uncategorized'),
                ),
              ],
              onChanged: provider.isLoading
                  ? null
                  : (val) {
                      setState(() {
                        _selectedDocumentType = val;
                      });
                    },
            ),

            const SizedBox(height: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSubmitButton(assessment, patient, provider),
                if (assessment == null ||
                    assessment.score < QualityThresholds.minOcrPassScore) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('retake_button'),
                    onPressed: provider.isLoading ? null : _clearSelection,
                    child: Text(
                      'Retake',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _detectionSignature(List<ClinicTest> tests) {
    return tests.map((test) => test.id).join('|');
  }

  Widget _buildDetectedTestsSelection(
    List<ClinicTest> detectedTests,
    bool disabled,
  ) {
    return Container(
      key: const Key('detected_tests_section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D7C66).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0D7C66).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.checklist_rounded,
                color: Color(0xFF0D7C66),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detected tests from your lab request',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select the tests you want sent for receptionist review.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Preparation notes are general guidance only. Confirm final instructions with the clinic.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...detectedTests.map((test) {
            final selected = _selectedTestIds.contains(test.id);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: disabled
                    ? null
                    : () {
                        setState(() {
                          if (selected) {
                            _selectedTestIds.remove(test.id);
                          } else {
                            _selectedTestIds.add(test.id);
                          }
                        });
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0D7C66).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: Key('detected_test_checkbox_${test.id}'),
                        value: selected,
                        onChanged: disabled
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    if (!_selectedTestIds.contains(test.id)) {
                                      _selectedTestIds.add(test.id);
                                    }
                                  } else {
                                    _selectedTestIds.remove(test.id);
                                  }
                                });
                              },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              test.label,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              clinicTestPrepInstructions[test.id] ?? '',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.62),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(
    QualityAssessment? assessment,
    Patient patient,
    DocumentSubmissionProvider provider,
  ) {
    final isLoading = provider.isLoading;

    if (isLoading) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: null,
        child: SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onPrimary,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: provider.canSubmit ? () => _submit(patient) : null,
      child: const Text(
        'Submit Request',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildQueueItem(
    OfflineDocument doc,
    DocumentSubmissionProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_outlined, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kept on this device until confirmed',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.fact_check_outlined,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.38),
              size: 20,
            ),
            tooltip: 'Review this draft',
            onPressed: provider.isLoading
                ? null
                : () => _resolveDraft(doc, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String path) {
    if (path.toLowerCase().endsWith('.pdf')) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf, size: 48),
            Text(path.split(RegExp(r'[/\\]')).last),
          ],
        ),
      );
    }
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        return _buildImagePlaceholder();
      }
    } catch (_) {
      return _buildImagePlaceholder();
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildImagePlaceholder(),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          Text(
            'Preview unavailable',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
