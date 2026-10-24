import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/repositories/documents_repository.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_status_provider.dart';

/// A documents repository that answers with a fixed list and never touches the
/// network.
class _FixedDocumentsRepository extends DocumentsRepository {
  _FixedDocumentsRepository(this.documents);

  final List<Document> documents;

  @override
  Future<List<Document>> getDocumentsForPatient(String uploaderId) async =>
      documents;
}

/// The live WebSocket is suppressed; changes are delivered by calling
/// [DocumentStatusProvider.handleDocumentChange] with a payload.
class _NoLiveChannelProvider extends DocumentStatusProvider {
  _NoLiveChannelProvider(super.db, {super.documentsRepository});

  @override
  void subscribeToDocumentUpdates(String uploaderId) {}
}

/// A row of the `documents` table, in the shape the server returns it.
Map<String, dynamic> _row(
  String id, {
  String status = 'pending',
}) =>
    <String, dynamic>{
      'id': id,
      'patient_id': 'patient-1',
      'uploader_id': 'uploader-1',
      'file_name': '$id.pdf',
      'file_path': 'uploader-1/$id.pdf',
      'file_type': 'application/pdf',
      'status': status,
      'created_at': '2026-10-24T08:00:00Z',
      'updated_at': '2026-10-24T08:00:00Z',
    };

/// A realtime payload for `documents`, as the channel delivers it. A DELETE
/// carries the old record only; an INSERT or UPDATE carries the new record.
PostgresChangePayload _change(
  PostgresChangeEvent type, {
  Map<String, dynamic> newRecord = const <String, dynamic>{},
  Map<String, dynamic> oldRecord = const <String, dynamic>{},
}) =>
    PostgresChangePayload(
      schema: 'public',
      table: 'documents',
      commitTimestamp: DateTime.utc(2026, 10, 24, 8),
      eventType: type,
      newRecord: newRecord,
      oldRecord: oldRecord,
      errors: null,
    );

void main() {
  late LocalDatabase db;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// A provider that has loaded [rows] and cached them, as a real read does.
  Future<DocumentStatusProvider> loadedProvider(
    List<Map<String, dynamic>> rows,
  ) async {
    final provider = _NoLiveChannelProvider(
      db,
      documentsRepository: _FixedDocumentsRepository(
        rows.map(Document.fromJson).toList(),
      ),
    );
    addTearDown(provider.dispose);
    await provider.fetchDocumentsAndSubscribe('uploader-1');
    return provider;
  }

  /// The cached ids, sorted: fixtures share a timestamp, so the cache's own
  /// order is not something these tests may depend on.
  Future<List<String>> cachedIds() async =>
      (await db.getDocumentsForPatient('uploader-1'))
          .map((doc) => doc.id)
          .toList()
        ..sort();

  group('document feed realtime changes', () {
    test('a DELETE removes the document from the list and from the cache',
        () async {
      final provider = await loadedProvider([_row('doc-1'), _row('doc-2')]);
      expect(await cachedIds(), ['doc-1', 'doc-2']);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.delete,
        oldRecord: {'id': 'doc-1'},
      ));

      expect(provider.documents.map((doc) => doc.id), ['doc-2']);
      expect(await cachedIds(), ['doc-2']);
      expect(provider.dataState, DocumentDataState.live);
    });

    test('a DELETE of the last document shows the empty state, not stale rows',
        () async {
      final provider = await loadedProvider([_row('doc-1')]);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.delete,
        oldRecord: {'id': 'doc-1'},
      ));

      expect(provider.documents, isEmpty);
      expect(provider.dataState, DocumentDataState.empty);
      expect(await cachedIds(), isEmpty);
    });

    test('a DELETE never re-creates a draft or offline-only upload', () async {
      final provider = await loadedProvider([_row('doc-1')]);
      await db.queueOfflineDocument(OfflineDocument(
        id: 'local-draft',
        uploaderId: 'uploader-1',
        fileName: 'draft.pdf',
        localFilePath: '/scratch/draft.pdf',
        fileType: 'application/pdf',
        uploadState: 'queued',
        createdAt: DateTime.utc(2026, 10, 24, 8),
      ));

      // The server's own id is deleted, and so is an id the server never had:
      // only the server's row may leave the list and the cache.
      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.delete,
        oldRecord: {'id': 'doc-1'},
      ));
      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.delete,
        oldRecord: {'id': 'local-draft'},
      ));

      expect(provider.documents, isEmpty);
      expect(await cachedIds(), isEmpty);
      final queued = await db.getQueuedDocuments('uploader-1');
      expect(queued.map((draft) => draft.id), ['local-draft']);
    });

    test('a DELETE without a primary key changes nothing', () async {
      final provider = await loadedProvider([_row('doc-1')]);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.delete,
        oldRecord: const <String, dynamic>{},
      ));

      expect(provider.documents.map((doc) => doc.id), ['doc-1']);
      expect(await cachedIds(), ['doc-1']);
    });

    test('an INSERT still puts the new document first and caches it',
        () async {
      final provider = await loadedProvider([_row('doc-1')]);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.insert,
        newRecord: _row('doc-2'),
      ));

      expect(provider.documents.map((doc) => doc.id), ['doc-2', 'doc-1']);
      expect(await cachedIds(), containsAll(['doc-1', 'doc-2']));
    });

    test('an UPDATE still replaces the document in place', () async {
      final provider = await loadedProvider([_row('doc-1'), _row('doc-2')]);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.update,
        newRecord: _row('doc-2', status: 'approved'),
      ));

      expect(provider.documents.map((doc) => doc.id), ['doc-1', 'doc-2']);
      expect(provider.documents[1].status, DocumentStatus.approved);
      final cached = await db.getDocumentsForPatient('uploader-1');
      expect(cached.firstWhere((doc) => doc.id == 'doc-2').status, 'approved');
    });

    test('an UPDATE for an unknown document still inserts it', () async {
      final provider = await loadedProvider([_row('doc-1')]);

      await provider.handleDocumentChange(_change(
        PostgresChangeEvent.update,
        newRecord: _row('doc-9'),
      ));

      expect(provider.documents.map((doc) => doc.id), ['doc-9', 'doc-1']);
    });

    test('an INSERT with no record is ignored', () async {
      final provider = await loadedProvider([_row('doc-1')]);

      await provider.handleDocumentChange(_change(PostgresChangeEvent.insert));

      expect(provider.documents.map((doc) => doc.id), ['doc-1']);
      expect(await cachedIds(), ['doc-1']);
    });
  });
}
