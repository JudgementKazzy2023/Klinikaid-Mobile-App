import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../providers/document_submission_provider.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/cache/local_database.dart';

class SubmitDocumentScreen extends StatefulWidget {
  const SubmitDocumentScreen({super.key});

  @override
  State<SubmitDocumentScreen> createState() => _SubmitDocumentScreenState();
}

class _SubmitDocumentScreenState extends State<SubmitDocumentScreen> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  String? _selectedImagePath;
  
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

      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
        
        if (mounted) {
          // Trigger on-device OCR via provider
          await Provider.of<DocumentSubmissionProvider>(context, listen: false)
              .processOnDeviceOcr(image.path, patient);
        }
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
    setState(() {
      _selectedImagePath = null;
    });
  }

  Future<void> _submit(Patient patient) async {
    if (_selectedImagePath == null) return;
    
    final provider = Provider.of<DocumentSubmissionProvider>(context, listen: false);
    final fullPath = _selectedImagePath!;
    final originalName = fullPath.split('/').last.split('\\').last;
    final ext = originalName.contains('.') ? originalName.split('.').last : 'jpg';
    
    final success = await provider.submitDocument(
      localFilePath: fullPath,
      originalFileName: originalName,
      fileExtension: ext,
      patient: patient,
    );

    if (mounted) {
      if (success) {
        final isOffline = provider.errorMessage != null && provider.errorMessage!.contains('offline');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline 
                ? 'Offline mode: Document queued locally.' 
                : 'Document submitted successfully!'),
            backgroundColor: isOffline ? Colors.orange : const Color(0xFF34C759),
          ),
        );
        _clearSelection();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
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
                if (_selectedImagePath == null)
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
    final List<dynamic> matched = metadata?['matched_fields'] ?? [];
    final List<dynamic> missing = metadata?['missing_fields'] ?? [];
    final hasWarnings = missing.isNotEmpty;

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
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Image.file(
                File(_selectedImagePath!),
                fit: BoxFit.cover,
              ),
            ),
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
              'On-Device AI Quality Pre-Screen',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            // Checklists
            _buildChecklistItem('Date of Request Match', matched.contains('date')),
            _buildChecklistItem('Physician Designation (Dr. / M.D.)', matched.contains('doctor')),
            _buildChecklistItem('Patient Name Match (${patient.fullName})', matched.contains('patient_name')),
            _buildChecklistItem('Diagnostic Keywords Found', matched.contains('request_keyword')),
            
            if (hasWarnings) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Some required clinical details could not be detected. Ensure the document is legible, or re-capture if blurry.',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      side: BorderSide(color: Theme.of(context).colorScheme.outline),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: provider.isLoading ? null : () => _pickImage(ImageSource.camera, patient),
                    child: const Text('Retake', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: provider.isLoading ? null : () => _submit(patient),
                    child: provider.isLoading
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2),
                          )
                        : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String title, bool matches) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(
            matches ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            color: matches ? Theme.of(context).colorScheme.primary : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: matches ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
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
}
