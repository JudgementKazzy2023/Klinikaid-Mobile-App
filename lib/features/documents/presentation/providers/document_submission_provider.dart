import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final Map<String, int> _retryCounts = {};
  StreamSubscription<AuthState>? _authSubscription;
  bool _disposed = false;

  DocumentSubmissionProvider(this._localDb) {
    _loadQueuedSubmissions();
    _watchAuthIdentityChanges();
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
  
  /// Queued submissions owned by the signed-in identity only. Rows queued by
  /// another account are never exposed here.
  List<OfflineDocument> get queuedSubmissions => _queuedSubmissions;

  /// Signed-in user id, or null when it cannot be established.
  /// Fails closed: an unreadable auth client counts as unauthenticated.
  String? _currentUserId() {
    try {
      return SupabaseService.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Owner id used by the simulated-offline test hook in [submitDocument].
  static const _testOwnerId = 'user-uuid-123';

  /// Newest [submitDocument] call. A superseded operation must never write
  /// state that a newer operation owns.
  int _submitGeneration = 0;

  /// True while [owner] is still the signed-in identity. Fails closed with
  /// [_currentUserId]: an unreadable auth client is a different session.
  bool _ownerStill(String? owner) => _currentUserId() == owner;

  /// Applies this submit's completion state while it is still the newest
  /// operation; a superseded one writes nothing, so a newer operation's
  /// loading flag and message are never overwritten. A disposed provider is
  /// never mutated or notified either, even by a completion that finishes
  /// after its provider is gone.
  void _completeSubmit(int generation, {String? errorMessage}) {
    if (_disposed) return;
    if (generation != _submitGeneration) return;
    _isLoading = false;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  /// Abandons a submit whose session no longer owns it: no further write is
  /// dispatched, no success is reported and no newer state is touched.
  bool _abandonSubmit(int generation) {
    _completeSubmit(
        generation, errorMessage: 'Session changed. Please try again.');
    return false;
  }

  /// Completes the offline fallback shared by both network-failure branches:
  /// queues the owner-attributed draft, then re-checks ownership after each
  /// local await. A session that changed while the write or the reload waited
  /// is abandoned — never told the submit succeeded — and the draft already
  /// written stays attributed to its owner, never rewritten or deleted for
  /// the newer identity.
  Future<bool> _completeOfflineFallback({
    required int generation,
    required OfflineDocument doc,
    required bool Function() stillOwned,
    required String message,
  }) async {
    await _localDb.queueOfflineDocument(doc);
    // The local write resumed after an await: a session that changed while it
    // waited is abandoned. The row just written stays owned by the account
    // that started the submit and is never rewritten for the newer identity.
    if (!stillOwned()) return _abandonSubmit(generation);

    await _loadQueuedSubmissions();
    // The reload resumed after an await: the same switch during that read.
    if (!stillOwned()) return _abandonSubmit(generation);

    _completeSubmit(generation, errorMessage: message);
    return true;
  }

  /// Invalidates queue visibility on every auth change so getters can never
  /// keep showing a previous account's drafts, then reloads for the new
  /// identity.
  void _watchAuthIdentityChanges() {
    try {
      _authSubscription =
          SupabaseService.client.auth.onAuthStateChange.listen((_) {
        if (_disposed) return;
        _queuedSubmissions = [];
        notifyListeners();
        _loadQueuedSubmissions();
      });
    } catch (e) {
      debugPrint('Offline queue auth listener unavailable: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Loads the queued submissions owned by the current identity only.
  /// An unauthenticated state reveals nothing, and a result read for one
  /// identity is discarded instead of being applied after an identity switch.
  Future<void> _loadQueuedSubmissions() async {
    final ownerId = _currentUserId();
    if (ownerId == null) {
      _queuedSubmissions = [];
      notifyListeners();
      return;
    }
    try {
      final owned = await _localDb.getQueuedDocuments(ownerId);
      if (_disposed) return;
      if (_currentUserId() != ownerId) {
        // Identity changed while the read was in flight: discard the stale
        // result without touching current state, so a list already loaded
        // for the newer identity is never erased by an older read.
        debugPrint('Discarding queue read for $ownerId: identity changed.');
        return;
      }
      _queuedSubmissions = owned;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading offline queue: $e');
    }
  }

  /// Deletes a queued offline document owned by the signed-in identity.
  /// Foreign ids and signed-out calls are a no-op: the owner-scoped delete
  /// matches no row, so other accounts' drafts are never removed.
  Future<void> removeQueuedItem(String id) async {
    final ownerId = _currentUserId();
    if (ownerId == null) return;
    try {
      await _localDb.removeQueuedDocument(id, ownerId);
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
  ///
  /// The signed-in owner is captured before the first await and re-checked at
  /// every awaited boundary, so an account switch mid-flight can never write
  /// this patient's document under another uploader, report a stale success or
  /// overwrite the state of a newer operation.
  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    required String documentType,
    List<String>? selectedTestIds,
    bool isTest = false,
  }) async {
    // Capture the operation owner before the first async boundary: everything
    // below is judged against the identity that started this submit, never
    // against whichever account happens to be signed in when an await ends.
    final ownerId = isTest ? _testOwnerId : _currentUserId();
    final generation = ++_submitGeneration;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    if (ownerId == null) {
      _completeSubmit(
          generation, errorMessage: 'Session expired. Please log in again.');
      return false;
    }

    // A patient object belongs to the profile that loaded it. Submitted under
    // another session it would be written with that session as uploader, so it
    // is rejected instead. Test mode has no real profile to compare.
    if (!isTest && patient.profileId != ownerId) {
      return _abandonSubmit(generation);
    }

    // Re-checked at every awaited boundary below. Test mode drives a synthetic
    // owner with no session that could switch.
    bool stillOwned() => isTest || _ownerStill(ownerId);

    // Check duplicate
    if (!isTest) {
      final duplicateCheck = await checkPendingDuplicate(patient.id, documentType);
      // The lookup was awaited: if the account changed while it waited, this
      // patient object belongs to a different linked profile than the session
      // now holding it, so nothing further is read or written on its behalf.
      if (!stillOwned()) return _abandonSubmit(generation);
      final label = getCategoryLabel(documentType);
      if (duplicateCheck.state == DuplicateCheckState.duplicate) {
        _completeSubmit(
            generation,
            errorMessage:
                "You already have a pending [$label] submitted on ${duplicateCheck.duplicateDate}. You can submit a new one once it's reviewed.");
        return false;
      }
      if (duplicateCheck.state == DuplicateCheckState.failed) {
        // The existing documents could not be read, so the duplicate status is
        // unknown. Do not upload as if it were unique: ask the patient to
        // retry.
        _completeSubmit(
            generation,
            errorMessage:
                "Could not check for a pending [$label] submission. Please check your connection and try again.");
        return false;
      }
    }
    
    final uuid = UuidGenerator.generateV4();
    // Use clear test prefix directory in storage paths to support testing cleanup
    final storagePath = isTest 
        ? '$ownerId/__test__/${uuid}_$originalFileName'
        : '$ownerId/${uuid}_$originalFileName';
        
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

      // The file check resumed after an await: stop before the dispatched
      // upload rather than writing under a newer session.
      if (!stillOwned()) return _abandonSubmit(generation);
      
      await SupabaseService.client.storage
          .from('patient-documents')
          .upload(storagePath, file);

      // The upload resumed after an await: the dispatched upload itself cannot
      // be recalled, but no document row is written for a changed session.
      if (!stillOwned()) return _abandonSubmit(generation);
          
      // 2. Insert metadata document row to Supabase Postgres
      final docPayload = Document(
        id: uuid,
        patientId: patient.id,
        uploaderId: ownerId,
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

      // The insert resumed after an await: it cannot be recalled either, but a
      // changed session must not be told this submit succeeded.
      if (!stillOwned()) return _abandonSubmit(generation);

      _completeSubmit(generation);
      return true;
    } on SocketException catch (_) {
      // Offline fallback: Queue submission details locally in SQLite cache.
      // An account that changed while the upload failed must not be told the
      // submit succeeded, and nothing new is done on its behalf.
      if (!stillOwned()) return _abandonSubmit(generation);
      return _completeOfflineFallback(
        generation: generation,
        doc: OfflineDocument(
          id: uuid,
          patientId: patient.id,
          uploaderId: ownerId,
          fileName: originalFileName,
          localFilePath: localFilePath,
          fileType: fileExtension,
          ocrText: ocrText,
          extractedMetadata: jsonEncode(metadata),
          createdAt: DateTime.now(),
        ),
        stillOwned: stillOwned,
        message: 'You are currently offline. Document queued for sync.',
      );
    } catch (e) {
      final Failure failure = FailureMapper.fromException(e);
      // Map other network failures to offline queueing as well
      if (failure is NetworkFailure) {
        if (!stillOwned()) return _abandonSubmit(generation);
        return _completeOfflineFallback(
          generation: generation,
          doc: OfflineDocument(
            id: uuid,
            patientId: patient.id,
            uploaderId: ownerId,
            fileName: originalFileName,
            localFilePath: localFilePath,
            fileType: fileExtension,
            ocrText: ocrText,
            extractedMetadata: jsonEncode(metadata),
            createdAt: DateTime.now(),
          ),
          stillOwned: stillOwned,
          message: 'Network connection failed. Document queued for sync.',
        );
      }
      
      _completeSubmit(generation, errorMessage: failure.message);
      return false;
    }
  }

  /// Triggers background queue uploads syncing when online.
  ///
  /// Only rows owned by the identity that started the sync are uploaded or
  /// deleted. When the identity changes mid-flight the loop stops before any
  /// further write: a request already dispatched to the backend cannot be
  /// recalled from the client, but nothing new is written and no queued row
  /// is deleted under the newer identity.
  Future<void> syncOfflineQueue() async {
    await _loadQueuedSubmissions();
    final ownerId = _currentUserId();
    if (ownerId == null || _queuedSubmissions.isEmpty) return;

    final toSync = List<OfflineDocument>.from(_queuedSubmissions);

    for (final doc in toSync) {
      // Ownership: only this identity's rows are ever uploaded or deleted.
      if (doc.uploaderId != ownerId) continue;
      if (_currentUserId() != ownerId) {
        debugPrint('Sync stopped before touching ${doc.id}: identity changed.');
        return;
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
          if (_currentUserId() != ownerId) {
            debugPrint('Sync stopped before deleting ${doc.id}: identity changed.');
            return;
          }
          await _localDb.removeQueuedDocument(doc.id, ownerId);
          continue;
        }

        // The file check resumed after an await: re-check identity before
        // dispatching the write. A dispatched upload cannot be recalled
        // from the client, so nothing new may be sent under a new session.
        if (_currentUserId() != ownerId) {
          debugPrint('Sync stopped before uploading ${doc.id}: identity changed.');
          return;
        }

        // 1. Upload file
        final storagePath = '$ownerId/${doc.id}_${doc.fileName}';
        await SupabaseService.client.storage
            .from('patient-documents')
            .upload(storagePath, file);

        // Stop before the next write once the identity changed: the dispatched
        // upload itself cannot be cancelled without backend support.
        if (_currentUserId() != ownerId) {
          debugPrint('Sync stopped before writing ${doc.id}: identity changed.');
          return;
        }
            
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

        // The insert await resumed after an identity change: the dispatched
        // insert itself cannot be recalled or reconciled from the client,
        // but no queued row is deleted under the newer identity.
        if (_currentUserId() != ownerId) {
          debugPrint('Sync stopped before deleting ${doc.id}: identity changed.');
          return;
        }

        // Success: remove from local SQLite queue
        await _localDb.removeQueuedDocument(doc.id, ownerId);
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
