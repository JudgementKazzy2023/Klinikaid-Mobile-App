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

class DocumentSubmissionProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _docsRepo = DocumentsRepository();
  
  bool _isLoading = false;
  String? _errorMessage;
  
  // OCR processing states
  bool _isProcessingOcr = false;
  String? _extractedOcrText;
  Map<String, dynamic>? _preScreenMetadata;
  
  // Offline sync states
  List<OfflineDocument> _queuedSubmissions = [];
  List<OfflineDocument> _orphanedSubmissions = [];
  final Map<String, int> _retryCounts = {};
  
  DocumentSubmissionProvider(this._localDb) {
    _loadQueuedSubmissions();
  }
  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isProcessingOcr => _isProcessingOcr;
  String? get extractedOcrText => _extractedOcrText;
  Map<String, dynamic>? get preScreenMetadata => _preScreenMetadata;
  
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
    _isProcessingOcr = true;
    _errorMessage = null;
    _extractedOcrText = null;
    _preScreenMetadata = null;
    notifyListeners();
    
    TextRecognizer? textRecognizer;
    try {
      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(InputImage.fromFilePath(imagePath));
      final String ocrText = recognizedText.text;
      
      _extractedOcrText = ocrText;
      _preScreenMetadata = preScreenOcrText(ocrText, patient.firstName, patient.lastName);
      
      _isProcessingOcr = false;
      notifyListeners();
      return ocrText;
    } catch (e) {
      _isProcessingOcr = false;
      _errorMessage = 'OCR extraction failed: ${e.toString()}';
      notifyListeners();
      rethrow;
    } finally {
      if (textRecognizer != null) {
        await textRecognizer.close();
      }
    }
  }

  /// Pre-screens extracted OCR text for key clinic checklist requirements.
  Map<String, dynamic> preScreenOcrText(String ocrText, String firstName, String lastName) {
    final text = ocrText.toLowerCase();
    
    // 1. Date Check (matches formats like MM/DD/YYYY, DD-MM-YYYY, YYYY/MM/DD)
    final dateRegex = RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}');
    final hasDate = dateRegex.hasMatch(ocrText);
    
    // 2. Doctor Check (matches "Dr.", "Dr", "M.D.", "MD")
    final doctorRegex = RegExp(r'\b(dr\.|dr|m\.d\.|md)\b');
    final hasDoctor = doctorRegex.hasMatch(text);
    
    // 3. Patient Name Check (verifies first and last name match tokens in OCR text)
    final cleanFirstName = firstName.toLowerCase().trim();
    final cleanLastName = lastName.toLowerCase().trim();
    final hasPatientName = text.contains(cleanFirstName) && text.contains(cleanLastName);
    
    // 4. Diagnostic Request Keywords Check
    final keywords = [
      'laboratory', 'request', 'referral', 'clinic', 'diagnostic', 
      'physician', 'cbc', 'xray', 'x-ray', 'ultrasound', 'ecg', 'blood', 'urine'
    ];
    final matchedKeywords = keywords.where((kw) => text.contains(kw)).toList();
    final hasKeywords = matchedKeywords.isNotEmpty;
    
    final matchedFields = <String>[];
    final missingFields = <String>[];
    
    if (hasDate) {
      matchedFields.add('date');
    } else {
      missingFields.add('date');
    }
    
    if (hasDoctor) {
      matchedFields.add('doctor');
    } else {
      missingFields.add('doctor');
    }
    
    if (hasPatientName) {
      matchedFields.add('patient_name');
    } else {
      missingFields.add('patient_name');
    }
    
    if (hasKeywords) {
      matchedFields.add('request_keyword');
    } else {
      missingFields.add('request_keyword');
    }
    
    return {
      'matched_fields': matchedFields,
      'missing_fields': missingFields,
      'ocr_text_length': ocrText.length,
      'keyword_set_version': '1.0',
      'ocr_engine_version': 'ml_kit_1.0',
      'matched_keywords': matchedKeywords,
    };
  }

  /// Submits a document. Uploads directly online, or queues in local SQLite if offline.
  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    bool isTest = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
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
    final metadata = _preScreenMetadata ?? preScreenOcrText(ocrText, patient.firstName, patient.lastName);
    
    try {
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
