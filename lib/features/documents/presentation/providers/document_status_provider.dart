import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/models/document.dart';
import '../../../../core/repositories/documents_repository.dart';
import '../../../../core/supabase/supabase_client.dart';

class DocumentStatusProvider extends ChangeNotifier {
  final LocalDatabase _localDb;
  final _docsRepo = DocumentsRepository();

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  List<Document> _documents = [];
  RealtimeChannel? _realtimeChannel;

  DocumentStatusProvider(this._localDb);

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  List<Document> get documents => _documents;

  /// Fetches submitted documents for [uploaderId] and subscribes to Realtime review updates.
  Future<void> fetchDocumentsAndSubscribe(String uploaderId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final remoteDocs = await _docsRepo.getDocumentsForPatient(uploaderId);
      _documents = remoteDocs;
      _isOffline = false;

      // Cache documents locally
      final cachedDocs = remoteDocs.map((doc) => CachedDocument(
        id: doc.id,
        patientId: doc.patientId,
        uploaderId: doc.uploaderId,
        fileName: doc.fileName,
        filePath: doc.filePath,
        fileType: doc.fileType,
        status: doc.status.name,
        ocrText: doc.ocrText,
        extractedMetadata: doc.extractedMetadata != null ? jsonEncode(doc.extractedMetadata) : null,
        rejectionReason: doc.rejectionReason,
        createdAt: doc.createdAt,
        updatedAt: doc.updatedAt,
      )).toList();

      await _localDb.cacheDocuments(cachedDocs);
      _isLoading = false;
      notifyListeners();

      // Subscribe to updates (RLS scopes so patient only sees own uploads)
      subscribeToDocumentUpdates(uploaderId);
    } on NetworkFailure catch (_) {
      _isOffline = true;
      await _loadFromCache(uploaderId);
    } catch (e) {
      _errorMessage = FailureMapper.fromException(e).message;
      await _loadFromCache(uploaderId);
    }
  }

  Future<void> _loadFromCache(String uploaderId) async {
    try {
      final cachedList = await _localDb.getDocumentsForPatient(uploaderId);
      _documents = cachedList.map((driftDoc) {
        final Map<String, dynamic>? metadata = driftDoc.extractedMetadata != null
            ? jsonDecode(driftDoc.extractedMetadata!) as Map<String, dynamic>
            : null;

        return Document(
          id: driftDoc.id,
          patientId: driftDoc.patientId,
          uploaderId: driftDoc.uploaderId,
          fileName: driftDoc.fileName,
          filePath: driftDoc.filePath,
          fileType: driftDoc.fileType,
          status: DocumentStatus.fromString(driftDoc.status),
          ocrText: driftDoc.ocrText,
          extractedMetadata: metadata,
          rejectionReason: driftDoc.rejectionReason,
          createdAt: driftDoc.createdAt,
          updatedAt: driftDoc.updatedAt,
        );
      }).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to load cached documents: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Establishes realtime subscription channel for document status transitions (pending -> approved/rejected).
  void subscribeToDocumentUpdates(String uploaderId) {
    if (_realtimeChannel != null) return; // Already active

    _realtimeChannel = SupabaseService.client
        .channel('public:documents:uploader_id=eq.$uploaderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'documents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'uploader_id',
            value: uploaderId,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            final eventType = payload.eventType;

            if (newRecord.isEmpty) return;

            final updatedDoc = Document.fromJson(newRecord);

            if (eventType == PostgresChangeEvent.insert) {
              _documents.insert(0, updatedDoc);
            } else if (eventType == PostgresChangeEvent.update) {
              final index = _documents.indexWhere((doc) => doc.id == updatedDoc.id);
              if (index != -1) {
                _documents[index] = updatedDoc;
              } else {
                _documents.insert(0, updatedDoc);
              }
            } else if (eventType == PostgresChangeEvent.delete) {
              final oldRecord = payload.oldRecord;
              if (oldRecord.isNotEmpty) {
                final deletedId = oldRecord['id'];
                _documents.removeWhere((doc) => doc.id == deletedId);
              }
            }

            // Sync to local Drift DB
            final cachedItem = CachedDocument(
              id: updatedDoc.id,
              patientId: updatedDoc.patientId,
              uploaderId: updatedDoc.uploaderId,
              fileName: updatedDoc.fileName,
              filePath: updatedDoc.filePath,
              fileType: updatedDoc.fileType,
              status: updatedDoc.status.name,
              ocrText: updatedDoc.ocrText,
              extractedMetadata: updatedDoc.extractedMetadata != null
                  ? jsonEncode(updatedDoc.extractedMetadata)
                  : null,
              rejectionReason: updatedDoc.rejectionReason,
              createdAt: updatedDoc.createdAt,
              updatedAt: updatedDoc.updatedAt,
            );
            await _localDb.cacheDocuments([cachedItem]);

            notifyListeners();
          },
        );

    _realtimeChannel?.subscribe();
  }

  void unsubscribe() {
    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
