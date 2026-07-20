import 'dart:io';
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

class _SubmitDocumentScreenState extends State<SubmitDocumentScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  String? _selectedDocumentType;
  List<String> _selectedTestIds = [];
  String? _initializedDetectionSignature;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DocumentSubmissionProvider>(context, listen: false).syncOfflineQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Provider.of<DocumentSubmissionProvider>(context, listen: false).syncOfflineQueue();
    }
  }

  Future<void> _pickImage(ImageSource source, Patient patient) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85, // Balance size and quality for OCR text readability
      );
      
      if (image != null && mounted) {
        // Trigger on-device OCR via provider
        await Provider.of<DocumentSubmissionProvider>(context, listen: false)
            .processOnDeviceOcr(image.path, patient);
        if (!mounted) return;
        final detectedTests = Provider.of<DocumentSubmissionProvider>(context, listen: false).detectedTests;
        setState(() {
          _selectedTestIds = detectedTests.map((test) => test.id).toList();
          _initializedDetectionSignature = _detectionSignature(detectedTests);
        });
      }
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

  void _clearSelection() {
    if (mounted) {
      setState(() {
        _selectedDocumentType = null;
        _selectedTestIds = [];
        _initializedDetectionSignature = null;
      });
      Provider.of<DocumentSubmissionProvider>(context, listen: false).clearOcrState();
    }
  }

  Future<void> _submit(Patient patient) async {
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

    final provider = Provider.of<DocumentSubmissionProvider>(context, listen: false);
    final fullPath = provider.selectedImagePath;
    if (fullPath == null) return;
    
    final metadata = provider.preScreenMetadata;
    final qualityAssessmentMap = metadata?['quality_assessment'] as Map<String, dynamic>?;
    final QualityAssessment? assessment = qualityAssessmentMap != null 
        ? QualityAssessment.fromJson(qualityAssessmentMap) 
        : null;

    if (assessment != null && assessment.score <= QualityThresholds.kPoorQualityThreshold) {
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
    final ext = originalName.contains('.') ? originalName.split('.').last : 'jpg';
    
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
        final isOffline = provider.errorMessage != null && provider.errorMessage!.contains('offline');
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(isOffline 
                ? 'Offline mode: Document queued locally.' 
                : 'Document submitted successfully!'),
            backgroundColor: isOffline ? Colors.orange : const Color(0xFF34C759),
          ),
        );
        _clearSelection();
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Submission failed.'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final patient = authProvider.patient;
    
    if (patient == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Submit Document',
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
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
                  _buildUploadCard(patient)
                else
                  _buildPreviewAndValidationCard(patient, provider),
                
                const SizedBox(height: 24),
                
                // Queued Offline Documents Section
                if (provider.queuedSubmissions.isNotEmpty || provider.orphanedSubmissions.isNotEmpty) ...[
                  Text(
                    'Offline Sync Queue',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...provider.queuedSubmissions.map((doc) => _buildQueueItem(doc, provider, false)),
                  ...provider.orphanedSubmissions.map((doc) => _buildQueueItem(doc, provider, true)),
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
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            'Analyzing document quality — this may take up to 10 seconds. Please wait.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
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
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pickImage(ImageSource.camera, patient),
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: const Text('Camera', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _pickImage(ImageSource.gallery, patient),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text('Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewAndValidationCard(Patient patient, DocumentSubmissionProvider provider) {
    final metadata = provider.preScreenMetadata;
    final detectedTests = provider.detectedTests;
    final detectionSignature = _detectionSignature(detectedTests);
    if (detectedTests.isNotEmpty && _initializedDetectionSignature != detectionSignature) {
      _selectedTestIds = detectedTests.map((test) => test.id).toList();
      _initializedDetectionSignature = detectionSignature;
    }
    
    final qualityAssessmentMap = metadata?['quality_assessment'] as Map<String, dynamic>?;
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
        border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Document Review',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
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
                    CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'AI Processing document OCR on-device...',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Document Quality Assessment',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
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
                              color: assessment.verdictColor.withValues(alpha: 0.4),
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
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (assessment.score < QualityThresholds.minOcrPassScore) ...[
                            const SizedBox(height: 8),
                            Text(
                              'This document may be hard to read (blurry / illegible text detected). You can submit as-is or retake for a clearer photo.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
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
            if (assessment != null && assessment.score < QualityThresholds.minOcrPassScore && assessment.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Identified Quality Issues',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
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
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('document_type_picker'),
              initialValue: _selectedDocumentType,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                hintText: 'Select a category',
              ),
              items: [
                ...clinicTemplates.map((t) => DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name),
                    )),
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

  Widget _buildDetectedTestsSelection(List<ClinicTest> detectedTests, bool disabled) {
    return Container(
      key: const Key('detected_tests_section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D7C66).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D7C66).withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.checklist_rounded, color: Color(0xFF0D7C66), size: 20),
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Preparation notes are general guidance only. Confirm final instructions with the clinic.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0D7C66).withValues(alpha: 0.2)),
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
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      onPressed: () => _submit(patient),
      child: const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildQueueItem(OfflineDocument doc, DocumentSubmissionProvider provider, bool isOrphaned) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOrphaned 
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.2) 
              : Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOrphaned ? Icons.account_circle_outlined : Icons.offline_bolt_outlined,
            color: isOrphaned ? Theme.of(context).colorScheme.error : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  isOrphaned 
                      ? 'Account Mismatch (Submit blocked)' 
                      : 'Pending reconnect...',
                  style: TextStyle(
                    color: isOrphaned ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38), size: 20),
            onPressed: () => provider.removeQueuedItem(doc.id),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String path) {
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, size: 40, color: Theme.of(context).colorScheme.error),
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
