import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/document.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/uuid_generator.dart';
import '../../../../core/repositories/documents_repository.dart';
import '../../clinic_test_catalog.dart';
import '../../../ocr/data/document_quality_service.dart';
import '../../../ocr/domain/quality_assessment.dart';
import '../../../ocr/domain/quality_thresholds.dart';
import '../../../patient/submissions/document_dedup.dart';

class DocumentSubmissionProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _docsRepo = DocumentsRepository();
  final _qualityService = DocumentQualityService();
  
  bool _isLoading = false;
  String? _errorMessage;
  
  // OCR processing states
  bool _isProcessing = false;
  bool _isProcessingOcr = false;
  String? _extractedOcrText;
  Map<String, dynamic>? _preScreenMetadata;
  String? _selectedImagePath;
  List<ClinicTest> _detectedTests = [];
  
  // Offline sync states
  List<OfflineDocument> _queuedSubmissions = [];
  List<OfflineDocument> _orphanedSubmissions = [];
  final Map<String, int> _retryCounts = {};
  
  DocumentSubmissionProvider(this._localDb) {
    _loadQueuedSubmissions();
  }
  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isProcessing => _isProcessing;
  bool get isProcessingOcr => _isProcessingOcr;
  String? get extractedOcrText => _extractedOcrText;
  Map<String, dynamic>? get preScreenMetadata => _preScreenMetadata;
  String? get selectedImagePath => _selectedImagePath;
  List<ClinicTest> get detectedTests => List.unmodifiable(_detectedTests);
  
  /// Returns true if there is a processed document ready for review.
  bool get hasCachedSubmission => _selectedImagePath != null && _preScreenMetadata != null;
  
  List<OfflineDocument> get queuedSubmissions => _queuedSubmissions;
  List<OfflineDocument> get orphanedSubmissions => _orphanedSubmissions;
  
  /// Loads all queued submissions from Drift DB, splitting into valid and orphaned based on current user.
  Future<void> _loadQueuedSubmissions() async {
    try {
      final allQueued = await _localDb.getQueuedDocuments();
      final currentUserId = SupabaseService.client.auth.currentUser?.id;
      
      _queuedSubmissions = [];
      _orphanedSubmissions = [];
      
      for (final doc in allQueued) {
        if (doc.uploaderId != currentUserId) {
          _orphanedSubmissions.add(doc);
        } else {
          _queuedSubmissions.add(doc);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading offline queue: $e');
    }
  }

  /// Deletes a queued offline document.
  Future<void> removeQueuedItem(String id) async {
    try {
      await _localDb.removeQueuedDocument(id);
      await _loadQueuedSubmissions();
    } catch (e) {
      debugPrint('Error removing queued document: $e');
    }
  }

  /// Processes text recognition on-device with ML Kit.
  Future<String> processOnDeviceOcr(String imagePath, Patient patient) async {
    _isProcessing = true;
    _isProcessingOcr = true;
    _errorMessage = null;
    _extractedOcrText = null;
    _preScreenMetadata = null;
    _detectedTests = [];
    _selectedImagePath = imagePath;
    notifyListeners();
    
    TextRecognizer? textRecognizer;
    try {
      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(InputImage.fromFilePath(imagePath));
      final String ocrText = recognizedText.text;
      
      _extractedOcrText = ocrText;
      _detectedTests = detectRequestedTests(ocrText);
      
      // Perform AI Quality Assessment (Path A) via Edge Function
      final QualityAssessment assessment = await _qualityService.assess(
        ocrText: ocrText,
        patientName: '${patient.firstName} ${patient.lastName}',
      );
      
      final bool identityMatch = checkPatientName(ocrText, patient.firstName, patient.lastName);
      final bool submittedWithWarnings = assessment.score < QualityThresholds.minOcrPassScore || !identityMatch;
      
      _preScreenMetadata = {
        'ocr_text': ocrText,
        'quality_assessment': assessment.toJson(),
        'identity_match': identityMatch,
        'submitted_with_warnings': submittedWithWarnings,
      };
      
      _isProcessingOcr = false;
      notifyListeners();
      return ocrText;
    } catch (e) {
      _isProcessingOcr = false;
      _errorMessage = 'OCR extraction failed: ${e.toString()}';
      notifyListeners();
      rethrow;
    } finally {
      _isProcessing = false;
      notifyListeners();
      if (textRecognizer != null) {
        await textRecognizer.close();
      }
    }
  }

  /// Clears the active OCR extraction text, metadata, processing flags, and errors.
  void clearOcrState() {
    _isProcessing = false;
    _isProcessingOcr = false;
    _extractedOcrText = null;
    _preScreenMetadata = null;
    _errorMessage = null;
    _selectedImagePath = null;
    _detectedTests = [];
    notifyListeners();
  }

  /// Checks if the patient's first and last name match tokens in the OCR text (sub-task 4.8).
  /// Case-insensitive and whitespace-tolerant.
  bool checkPatientName(String ocrText, String firstName, String lastName) {
    final text = ocrText.toLowerCase();
    final cleanFirstName = firstName.toLowerCase().trim();
    final cleanLastName = lastName.toLowerCase().trim();
    return text.contains(cleanFirstName) && text.contains(cleanLastName);
  }

  /// Pre-screens extracted OCR text for key clinic checklist requirements.
  /// Note: The original hardcoded date pattern, doctor token, and keyword checks
  /// (sub-tasks 4.6, 4.7, 4.9) are commented out/removed for Path A. They are replaced
  /// by the Edge-Function-based quality assessment.
  Map<String, dynamic> preScreenOcrText(String ocrText, String firstName, String lastName) {
    /*
    final text = ocrText.toLowerCase();
    
    // 1. Date Check (matches formats like MM/DD/YYYY, DD-MM-YYYY, YYYY/MM/DD)
    final dateRegex = RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}');
    final hasDate = dateRegex.hasMatch(ocrText);
    
    // 2. Doctor Check (matches "Dr.", "Dr", "M.D.", "MD")
    final doctorRegex = RegExp(r'\b(dr\.|dr|m\.d\.|md)\b');
    final hasDoctor = doctorRegex.hasMatch(text);
    
    // 4. Diagnostic Request Keywords Check
    final keywords = [
      'laboratory', 'request', 'referral', 'clinic', 'diagnostic', 
      'physician', 'cbc', 'xray', 'x-ray', 'ultrasound', 'ecg', 'blood', 'urine'
    ];
    final matchedKeywords = keywords.where((kw) => text.contains(kw)).toList();
    final hasKeywords = matchedKeywords.isNotEmpty;
    */
    
    final bool identityMatch = checkPatientName(ocrText, firstName, lastName);
    final fallback = DocumentQualityService.fallbackAssessment;
    
    return {
      'ocr_text': ocrText,
      'quality_assessment': fallback.toJson(),
      'identity_match': identityMatch,
      'submitted_with_warnings': true,
    };
  }

  @visibleForTesting
  void setTestDetectionStateForTest({
    required String ocrText,
    required Map<String, dynamic> preScreenMetadata,
    List<ClinicTest>? detectedTests,
  }) {
    _extractedOcrText = ocrText;
    _preScreenMetadata = Map<String, dynamic>.from(preScreenMetadata);
    _detectedTests = detectedTests ?? detectRequestedTests(ocrText);
  }

  /// Submits a document. Uploads directly online, or queues in local SQLite if offline.
  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    required String documentType,
    List<String>? selectedTestIds,
    bool isTest = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Check duplicate
    if (!isTest) {
      final duplicateDate = await checkPendingDuplicate(patient.id, documentType);
      if (duplicateDate != null) {
        final label = getCategoryLabel(documentType);
        _isLoading = false;
        _errorMessage = "You already have a pending [$label] submitted on $duplicateDate. You can submit a new one once it's reviewed.";
        notifyListeners();
        return false;
      }
    }
    
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null && !isTest) {
      _isLoading = false;
      _errorMessage = 'Session expired. Please log in again.';
      notifyListeners();
      return false;
    }
    
    final currentUserId = isTest ? 'user-uuid-123' : currentUser!.id;
    final uuid = UuidGenerator.generateV4();
    // Use clear test prefix directory in storage paths to support testing cleanup
    final storagePath = isTest 
        ? '$currentUserId/__test__/${uuid}_$originalFileName'
        : '$currentUserId/${uuid}_$originalFileName';
        
    final ocrText = _extractedOcrText ?? '';
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(
      _preScreenMetadata ?? preScreenOcrText(ocrText, patient.firstName, patient.lastName),
    );
    metadata['document_type'] = documentType;
    if (_detectedTests.isNotEmpty) {
      metadata.addAll(buildTestDetectionMetadata(
        detectedTests: _detectedTests,
        selectedTestIds: selectedTestIds ?? _detectedTests.map((test) => test.id).toList(),
      ));
    }
    
    try {
      if (isTest) {
        throw const SocketException('Simulated offline exception for testing');
      }

      // 1. Upload file to Supabase Storage private bucket
      final File file = File(localFilePath);
      if (!await file.exists()) {
        throw Exception('Captured image file does not exist locally.');
      }
      
      await SupabaseService.client.storage
          .from('patient-documents')
          .upload(storagePath, file);
          
      // 2. Insert metadata document row to Supabase Postgres
      final docPayload = Document(
        id: uuid,
        patientId: patient.id,
        uploaderId: currentUserId,
        fileName: originalFileName,
        filePath: storagePath,
        fileType: fileExtension,
        status: DocumentStatus.pending,
        ocrText: ocrText,
        extractedMetadata: metadata,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _docsRepo.insertDocument(docPayload);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on SocketException catch (_) {
      // Offline fallback: Queue submission details locally in SQLite cache
      final offlineDoc = OfflineDocument(
        id: uuid,
        patientId: patient.id,
        uploaderId: currentUserId,
        fileName: originalFileName,
        localFilePath: localFilePath,
        fileType: fileExtension,
        ocrText: ocrText,
        extractedMetadata: jsonEncode(metadata),
        createdAt: DateTime.now(),
      );
      
      await _localDb.queueOfflineDocument(offlineDoc);
      await _loadQueuedSubmissions();
      
      _isLoading = false;
      _errorMessage = 'You are currently offline. Document queued for sync.';
      notifyListeners();
      return true;
    } catch (e) {
      final Failure failure = FailureMapper.fromException(e);
      // Map other network failures to offline queueing as well
      if (failure is NetworkFailure) {
        final offlineDoc = OfflineDocument(
          id: uuid,
          patientId: patient.id,
          uploaderId: currentUserId,
          fileName: originalFileName,
          localFilePath: localFilePath,
          fileType: fileExtension,
          ocrText: ocrText,
          extractedMetadata: jsonEncode(metadata),
          createdAt: DateTime.now(),
        );
        
        await _localDb.queueOfflineDocument(offlineDoc);
        await _loadQueuedSubmissions();
        _isLoading = false;
        _errorMessage = 'Network connection failed. Document queued for sync.';
        notifyListeners();
        return true;
      }
      
      _isLoading = false;
      _errorMessage = failure.message;
      notifyListeners();
      return false;
    }
  }

  /// Triggers background queue uploads syncing when online.
  Future<void> syncOfflineQueue() async {
    await _loadQueuedSubmissions();
    if (_queuedSubmissions.isEmpty) return;
    
    final currentUser = SupabaseService.client.auth.currentUser;
    if (currentUser == null) return;
    
    final toSync = List<OfflineDocument>.from(_queuedSubmissions);
    
    for (final doc in toSync) {
      // Identity Check: verify auth.uid() matches uploader_id
      if (doc.uploaderId != currentUser.id) {
        // Safe check, should be caught by _loadQueuedSubmissions already
        continue;
      }
      
      final retryCount = _retryCounts[doc.id] ?? 0;
      if (retryCount >= 3) {
        // Capped retries reached, skip this item (surfaced via UI warning list)
        continue;
      }
      
      try {
        final File file = File(doc.localFilePath);
        if (!await file.exists()) {
          // File deleted locally, remove from sync queue to avoid infinite loops
          await _localDb.removeQueuedDocument(doc.id);
          continue;
        }
        
        // 1. Upload file
        final storagePath = '${currentUser.id}/${doc.id}_${doc.fileName}';
        await SupabaseService.client.storage
            .from('patient-documents')
            .upload(storagePath, file);
            
        // 2. Insert record
        final metadata = doc.extractedMetadata != null 
            ? jsonDecode(doc.extractedMetadata!) as Map<String, dynamic>
            : null;
            
        final docPayload = Document(
          id: doc.id,
          patientId: doc.patientId,
          uploaderId: doc.uploaderId,
          fileName: doc.fileName,
          filePath: storagePath,
          fileType: doc.fileType,
          status: DocumentStatus.pending,
          ocrText: doc.ocrText,
          extractedMetadata: metadata,
          createdAt: doc.createdAt,
          updatedAt: DateTime.now(),
        );
        
        await _docsRepo.insertDocument(docPayload);
        
        // Success: remove from local SQLite queue
        await _localDb.removeQueuedDocument(doc.id);
        _retryCounts.remove(doc.id);
        
      } catch (e) {
        // Increment retry attempts count
        _retryCounts[doc.id] = retryCount + 1;
        debugPrint('Failed sync attempt for document ${doc.id}: $e');
      }
    }
    
    await _loadQueuedSubmissions();
  }
}
