import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/patient_submission_containment.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../data/uploads_repository.dart';

import '../../../../core/models/patient.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/utils/uuid_generator.dart';

import '../../clinic_test_catalog.dart';
import '../../../ocr/data/document_quality_service.dart';
import '../../../ocr/domain/quality_assessment.dart';
import '../../../ocr/domain/quality_thresholds.dart';
import '../../../patient/submissions/document_dedup.dart';

class DocumentSubmissionProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final UploadsRepository _uploads;
  final Directory? _draftDirectory;
  final SupabaseClient? _injectedClient;
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;
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

  StreamSubscription<AuthState>? _authSubscription;
  bool _disposed = false;

  DocumentSubmissionProvider(
    this._localDb, {
    SupabaseClient? client,
    Directory? draftDirectory,
  }) : _draftDirectory = draftDirectory,
       _injectedClient = client,
       _uploads = UploadsRepository(client: client) {
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
  bool get hasCachedSubmission =>
      _selectedImagePath != null && _preScreenMetadata != null;

  /// Queued submissions owned by the signed-in identity only. Rows queued by
  /// another account are never exposed here.
  List<OfflineDocument> get queuedSubmissions => List.unmodifiable(
    _queuedSubmissions.where((d) => d.uploaderId == _currentUserId()),
  );

  /// Signed-in user id, or null when it cannot be established.
  /// Fails closed: an unreadable auth client counts as unauthenticated.
  String? _currentUserId() {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Newest [submitDocument] call. A superseded operation must never write
  /// state that a newer operation owns.
  int _submitGeneration = 0;

  /// True while [owner] is still the signed-in identity. Fails closed with
  /// [_currentUserId]: an unreadable auth client is a different session.
  bool _ownerStill(String? owner) => !_disposed && _currentUserId() == owner;

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
      generation,
      errorMessage: 'Session changed. Please try again.',
    );
    return false;
  }

  /// Invalidates queue visibility on every auth change so getters can never
  /// keep showing a previous account's drafts, then reloads for the new
  /// identity.
  void _watchAuthIdentityChanges() {
    try {
      _authSubscription = _client.auth.onAuthStateChange.listen((_) {
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

  Future<void> selectPdf(String filePath) async {
    PatientSubmissionContainment.requireAvailable();
    final file = File(filePath);
    if (await file.length() > 5 * 1024 * 1024)
      throw const FormatException('Files must be at most 5 MB.');
    _selectedImagePath = filePath;
    _extractedOcrText = '';
    _detectedTests = [];
    _preScreenMetadata = {
      'quality_assessment': DocumentQualityService.fallbackAssessment.toJson(),
      'submitted_with_warnings': true,
    };
    notifyListeners();
  }

  Future<void> removeQueuedItem(String id) async {
    if (PatientSubmissionContainment.isActive) return;
    _errorMessage = 'Drafts are kept until the clinic confirms the outcome.';
    notifyListeners();
  }

  Future<String> processOnDeviceOcr(String imagePath, Patient patient) async {
    PatientSubmissionContainment.requireAvailable();
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
      final RecognizedText recognizedText = await textRecognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      final String ocrText = recognizedText.text;

      _extractedOcrText = ocrText;
      _detectedTests = detectRequestedTests(ocrText);

      // Perform AI Quality Assessment (Path A) via Edge Function
      final QualityAssessment assessment = await _qualityService.assess(
        ocrText: ocrText,
        patientName: '${patient.firstName} ${patient.lastName}',
      );

      final bool identityMatch = checkPatientName(
        ocrText,
        patient.firstName,
        patient.lastName,
      );
      final bool submittedWithWarnings =
          assessment.score < QualityThresholds.minOcrPassScore ||
          !identityMatch;

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
  Map<String, dynamic> preScreenOcrText(
    String ocrText,
    String firstName,
    String lastName,
  ) {
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

  String? _advisoryMessage;
  String? get advisoryMessage => _advisoryMessage;
  String? _activeDraftId;
  UploadFailure? _submissionError;
  String? _documentId;
  String? get submittedDocumentId => _documentId;
  String? get duplicateDocumentId =>
      _submissionError?.code == 'DUPLICATE_PENDING'
      ? _submissionError?.documentId
      : null;
  String? get errorCode => _submissionError?.code;
  Map<String, String> get fieldErrors => _submissionError?.field == null
      ? {}
      : {_submissionError!.field!: _errorMessage ?? _submissionError!.message};
  bool get canSubmit => !_isLoading && !_blocked;
  bool _blocked = false;
  String? get remediationRoute => switch (_submissionError?.code) {
    'UNAUTHENTICATED' => '/login',
    'EMAIL_NOT_CONFIRMED' => '/verify',
    'CONSENT_REQUIRED' => '/consent',
    'PASSWORD_CHANGE_REQUIRED' => 'change-password',
    _ => null,
  };

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void resumeAfterAccountFlow() {
    if (remediationRoute != null) {
      _blocked = false;
      notifyListeners();
    }
  }

  void _applyUploadFailure(UploadFailure error, String category) {
    _advisoryMessage = null;
    _submissionError = error;
    _blocked = ![
      'FIELD_REQUIRED',
      'FIELD_INVALID',
      'SERVER_ERROR',
    ].contains(error.code);
    _errorMessage = switch (error.code) {
      'DUPLICATE_PENDING' =>
        'You already have a pending ${getCategoryLabel(category)}',
      'IDEMPOTENCY_CONFLICT' ||
      'RECONCILIATION_REQUIRED' ||
      'ASSESSMENT_NOT_FOUND' =>
        'Please contact the clinic before submitting again. Your file and answers are still here.',
      'UNKNOWN_FIELD' ||
      'METHOD_NOT_ALLOWED' => 'This app version is out of date.',
      'UNAUTHENTICATED' ||
      'EMAIL_NOT_CONFIRMED' ||
      'CONSENT_REQUIRED' ||
      'PASSWORD_CHANGE_REQUIRED' ||
      'PATIENT_ACCOUNT_REQUIRED' ||
      'NO_PATIENT_RECORD' ||
      'PROFILE_INACTIVE' ||
      'SERVER_DATA_INVALID' ||
      'FIELD_REQUIRED' ||
      'FIELD_INVALID' => error.message,
      _ => UploadFailure.unknown.message,
    };
    if (error.code == 'SERVER_ERROR' ||
        ![
          'DUPLICATE_PENDING',
          'IDEMPOTENCY_CONFLICT',
          'RECONCILIATION_REQUIRED',
          'ASSESSMENT_NOT_FOUND',
          'UNKNOWN_FIELD',
          'METHOD_NOT_ALLOWED',
          'UNAUTHENTICATED',
          'EMAIL_NOT_CONFIRMED',
          'CONSENT_REQUIRED',
          'PASSWORD_CHANGE_REQUIRED',
          'PATIENT_ACCOUNT_REQUIRED',
          'NO_PATIENT_RECORD',
          'PROFILE_INACTIVE',
          'SERVER_DATA_INVALID',
          'FIELD_REQUIRED',
          'FIELD_INVALID',
        ].contains(error.code)) {
      _submissionError = UploadFailure.unknown;
      _blocked = false;
    }
  }

  /// The server confirmed this submission, so the app's private copy of the
  /// medical document is no longer needed on the device. Only files inside the
  /// owner's submission-drafts folder are touched, never the patient's original.
  Future<void> _deleteDraftCopy(String filePath, String owner) async {
    try {
      final root = _draftDirectory ?? await getApplicationDocumentsDirectory();
      final folder = path.join(root.path, 'submission-drafts', owner);
      if (!path.isWithin(folder, filePath)) return;
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The submission is confirmed; a leftover copy is not worth failing it.
    }
  }

  /// This compatibility entry never replays a queue, even with containment off.
  Future<void> syncOfflineQueue() async {
    if (PatientSubmissionContainment.isActive) return;
    await _loadQueuedSubmissions();
    _errorMessage = 'Review and submit one saved draft at a time.';
    notifyListeners();
  }

  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    required String documentType,
    List<String>? selectedTestIds,
    bool isTest = false,
  }) async {
    if (PatientSubmissionContainment.isActive) {
      _isLoading = false;
      _errorMessage = PatientSubmissionContainment.message;
      notifyListeners();
      return false;
    }
    if (_isLoading || _disposed) return false;
    final owner = _currentUserId();
    if (owner == null || patient.profileId != owner) {
      _errorMessage = 'Session changed. Please log in again.';
      notifyListeners();
      return false;
    }
    final owned = await _localDb.getQueuedDocuments(owner);
    if (!_ownerStill(owner)) return false;
    final matching = owned.where(
      (d) => d.id == _activeDraftId || d.localFilePath == localFilePath,
    );
    final existing = matching.isEmpty ? null : matching.first;
    if (existing == null && owned.any((d) => d.uploadState == 'unknown')) {
      _errorMessage =
          'Please check the uncertain saved draft below before starting another submission.';
      notifyListeners();
      return false;
    }
    return _runUpload(
      owner: owner,
      existing: existing,
      localFilePath: localFilePath,
      fileName: originalFileName,
      fileExtension: fileExtension,
      patientId: patient.id,
      category: documentType,
      ocr: _extractedOcrText ?? '',
      selected: selectedTestIds,
    );
  }

  /// Explicit owner action. No screen/lifecycle callback invokes this method.
  Future<bool> resolveQueuedDraft(String id) async {
    if (PatientSubmissionContainment.isActive || _isLoading || _disposed)
      return false;
    final owner = _currentUserId();
    if (owner == null) return false;
    final rows = await _localDb.getQueuedDocuments(owner);
    if (!_ownerStill(owner)) return false;
    final matches = rows.where((d) => d.id == id);
    if (matches.isEmpty) return false;
    final doc = matches.single;
    try {
      final metadata = doc.extractedMetadata == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(doc.extractedMetadata!));
      final saved = doc.submissionContent == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(doc.submissionContent!));
      final selected = saved != null
          ? (saved['selected'] == null
                ? null
                : List<String>.from(saved['selected']))
          : metadata['selected_tests'] is List
          ? (metadata['selected_tests'] as List)
                .map((t) => (t as Map)['id'] as String)
                .toList()
          : null;
      return await _runUpload(
        owner: owner,
        existing: doc,
        localFilePath: doc.localFilePath,
        fileName: doc.fileName,
        fileExtension: doc.fileType,
        patientId: doc.patientId,
        category:
            saved?['category'] as String? ??
            metadata['document_type'] as String? ??
            'other',
        ocr: doc.ocrText ?? '',
        selected: selected,
      );
    } catch (_) {
      _applyUploadFailure(
        const UploadFailure(
          'SERVER_DATA_INVALID',
          'This saved draft needs clinic review. Your draft and file are still here.',
        ),
        'other',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> _runUpload({
    required String owner,
    required OfflineDocument? existing,
    required String localFilePath,
    required String fileName,
    required String fileExtension,
    required String? patientId,
    required String category,
    required String ocr,
    List<String>? selected,
  }) async {
    if (_isLoading) return false;
    final generation = ++_submitGeneration;
    _isLoading = true;
    _submissionError = null;
    _errorMessage = null;
    _blocked = false;
    notifyListeners();
    OfflineDocument? draft = existing;
    try {
      if (draft != null && draft.uploadState.startsWith('blocked:')) {
        _applyUploadFailure(
          UploadFailure(
            draft.uploadState.substring(8),
            'Contact the clinic before trying again.',
          ),
          category,
        );
        return false;
      }
      if (draft?.uploadState == 'unknown' || draft?.uploadState == 'legacy') {
        final known = await _uploads.lookup(
          owner: owner,
          requestId: draft!.requestId!,
        );
        if (!_ownerStill(owner)) return _abandonSubmit(generation);
        switch (known) {
          case UploadLookup(state: 'committed'):
            _documentId = known.documentId;
            await _localDb.removeQueuedDocument(draft.id, owner);
            await _deleteDraftCopy(draft.localFilePath, owner);
            if (!_ownerStill(owner)) return _abandonSubmit(generation);
            return true;
          case UploadLookup(state: 'not_found'):
            draft = draft.copyWith(uploadState: 'draft');
            await _localDb.updateUploadDraft(draft, owner);
          case UploadLookup():
            _applyUploadFailure(
              const UploadFailure(
                'RECONCILIATION_REQUIRED',
                'Contact the clinic.',
              ),
              category,
            );
            await _localDb.updateUploadDraft(
              draft.copyWith(uploadState: 'blocked:RECONCILIATION_REQUIRED'),
              owner,
            );
            return false;
          case UploadFailure():
            _applyUploadFailure(known, category);
            return false;
          case UploadSuccess():
            _applyUploadFailure(UploadFailure.unknown, category);
            return false;
        }
      }
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      final file = File(localFilePath);
      if (!await file.exists()) {
        _errorMessage =
            'The saved file is missing. Your draft is kept; contact the clinic.';
        return false;
      }
      final bytes = await file.readAsBytes();
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      final mime = UploadsRepository.mimeFor(fileExtension);
      if (mime.isEmpty || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        _applyUploadFailure(
          const UploadFailure(
            'FIELD_INVALID',
            'Choose a PDF, JPEG or PNG file up to 5 MB.',
            field: 'file',
          ),
          category,
        );
        return false;
      }
      if (patientId == null) {
        _applyUploadFailure(
          const UploadFailure(
            'NO_PATIENT_RECORD',
            'Patient account is incomplete. Contact the clinic.',
          ),
          category,
        );
        return false;
      }
      final normalizedSelected = selected == null
          ? null
          : (selected.toSet().toList()..sort());
      final content = jsonEncode({
        'hash': sha256.convert(bytes).toString(),
        'category': category,
        'selected': normalizedSelected,
        'name': fileName,
        'mime': mime,
        'ocr': ocr,
        'patient': patientId,
      });
      final changed =
          draft?.submissionContent != null &&
          draft!.submissionContent != content;
      // Reaching here, an earlier attempt for this draft has no committed or
      // in-RPC submit: blocked states returned above, and unknown ones were
      // looked up (the lookup lock covers submits that reached the RPC).
      final superseded = changed && draft.assessmentId != null
          ? (id: draft.assessmentId!, mime: UploadsRepository.mimeFor(draft.fileType))
          : null;
      draft = OfflineDocument(
        id: draft?.id ?? UuidGenerator.generateV4(),
        patientId: patientId,
        uploaderId: owner,
        fileName: fileName,
        localFilePath: localFilePath,
        fileType: fileExtension,
        ocrText: ocr,
        extractedMetadata:
            draft?.extractedMetadata ?? jsonEncode({'document_type': category}),
        createdAt: draft?.createdAt ?? DateTime.now(),
        requestId: draft == null || changed
            ? UuidGenerator.generateV4()
            : draft.requestId,
        assessmentId: draft == null || changed
            ? UuidGenerator.generateV4()
            : draft.assessmentId,
        uploadState: 'draft',
        submissionContent: content,
      );
      if (existing == null) {
        final root =
            _draftDirectory ?? await getApplicationDocumentsDirectory();
        if (!_ownerStill(owner)) return _abandonSubmit(generation);
        final folder = Directory(
          path.join(root.path, 'submission-drafts', owner),
        );
        await folder.create(recursive: true);
        if (!_ownerStill(owner)) return _abandonSubmit(generation);
        final durable = await file.copy(
          path.join(folder.path, '${draft.id}.${fileExtension.toLowerCase()}'),
        );
        draft = draft.copyWith(localFilePath: durable.path);
      }
      _activeDraftId = draft.id;
      if (existing == null) {
        await _localDb.queueOfflineDocument(draft);
      } else {
        await _localDb.updateUploadDraft(draft, owner);
      }
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      // Only after the new draft is saved, so nothing the patient has is lost.
      if (superseded != null) {
        await _uploads.discardAssessment(
          owner: owner,
          assessmentId: superseded.id,
          mime: superseded.mime,
        );
        if (!_ownerStill(owner)) return _abandonSubmit(generation);
      }
      if (category != 'other' && existing?.uploadState != 'unknown') {
        final advisory = await checkPendingDuplicate(
          patientId,
          category,
          client: _client,
        );
        if (!_ownerStill(owner)) return _abandonSubmit(generation);
        if (advisory.state != DuplicateCheckState.clear) {
          _advisoryMessage = advisory.state == DuplicateCheckState.duplicate
              ? 'A pending document may already exist. The server will check.'
              : 'The pending-record check is unavailable. The server will check this submission.';
          notifyListeners();
        }
      }
      await _uploads.prepare(
        owner: owner,
        patientId: patientId,
        assessmentId: draft.assessmentId!,
        fileName: fileName,
        mime: mime,
        bytes: bytes,
        ocrText: ocr,
      );
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      // Persist uncertainty BEFORE dispatch, so app termination cannot turn a
      // possibly committed submission into an apparently never-sent draft.
      draft = draft.copyWith(uploadState: 'unknown');
      await _localDb.updateUploadDraft(draft, owner);
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      final result = await _uploads.submit(
        owner: owner,
        requestId: draft.requestId!,
        assessmentId: draft.assessmentId!,
        documentType: category,
        selectedTestIds: normalizedSelected,
      );
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      switch (result) {
        case UploadSuccess():
          _documentId = result.documentId;
          await _localDb.removeQueuedDocument(draft.id, owner);
          await _deleteDraftCopy(draft.localFilePath, owner);
          // A replay means a slow first attempt committed while this resend
          // re-inserted the pending row; that copy is unused now.
          if (result.replayed) {
            await _uploads.discardAssessment(
              owner: owner,
              assessmentId: draft.assessmentId!,
              mime: mime,
            );
          }
          if (!_ownerStill(owner)) return _abandonSubmit(generation);
          return true;
        case UploadFailure():
          _applyUploadFailure(result, category);
          final state = errorCode == 'SERVER_ERROR'
              ? 'unknown'
              : [
                  'IDEMPOTENCY_CONFLICT',
                  'RECONCILIATION_REQUIRED',
                  'ASSESSMENT_NOT_FOUND',
                ].contains(errorCode)
              ? 'blocked:$errorCode'
              : 'error:$errorCode';
          await _localDb.updateUploadDraft(
            draft.copyWith(uploadState: state),
            owner,
          );
          return false;
        case UploadLookup():
          _applyUploadFailure(UploadFailure.unknown, category);
          return false;
      }
    } catch (_) {
      if (!_ownerStill(owner)) return _abandonSubmit(generation);
      _applyUploadFailure(UploadFailure.unknown, category);
      // No new submission was dispatched on a preparation failure. Retain the
      // existing draft state and never delete the draft or original file.
      return false;
    } finally {
      if (!_disposed && generation == _submitGeneration) {
        _isLoading = false;
        if (_ownerStill(owner)) await _loadQueuedSubmissions();
        notifyListeners();
      }
    }
  }
}
