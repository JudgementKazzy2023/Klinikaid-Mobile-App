import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v1 migration preserves all fields/files, assigns unique IDs and keeps IDs across reopen',
    () async {
      final temp = await Directory.systemTemp.createTemp('upload-migration-');
      final file = File('${temp.path}/draft.pdf');
      await file.writeAsString('%PDF fixture');
      final databaseFile = File('${temp.path}/old.sqlite');
      final old = sqlite3.open(databaseFile.path);
      old.execute(
        'CREATE TABLE offline_documents_queue (id TEXT NOT NULL PRIMARY KEY, patient_id TEXT, uploader_id TEXT NOT NULL, file_name TEXT NOT NULL, local_file_path TEXT NOT NULL, file_type TEXT NOT NULL, ocr_text TEXT, extracted_metadata TEXT, created_at INTEGER NOT NULL)',
      );
      for (final owner in ['a', 'b']) {
        old.execute(
          'INSERT INTO offline_documents_queue VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            owner,
            'patient-$owner',
            owner,
            'request.pdf',
            file.path,
            'pdf',
            'original OCR',
            '{"document_type":"lab-request","legacy":"keep"}',
            123456,
          ],
        );
      }
      old.execute('PRAGMA user_version=1');
      old.close();
      var db = LocalDatabase(NativeDatabase(databaseFile));
      final a = (await db.getQueuedDocuments('a')).single;
      final b = (await db.getQueuedDocuments('b')).single;
      expect(a.id, 'a');
      expect(a.patientId, 'patient-a');
      expect(a.uploaderId, 'a');
      expect(a.fileName, 'request.pdf');
      expect(a.localFilePath, file.path);
      expect(a.fileType, 'pdf');
      expect(a.ocrText, 'original OCR');
      expect(
        a.extractedMetadata,
        '{"document_type":"lab-request","legacy":"keep"}',
      );
      expect(a.createdAt.millisecondsSinceEpoch, 123456000);
      expect(a.uploadState, 'legacy');
      expect(a.requestId, isNotNull);
      expect(a.requestId, isNot(b.requestId));
      expect(a.assessmentId, isNotNull);
      await db.close();
      db = LocalDatabase(NativeDatabase(databaseFile));
      expect((await db.getQueuedDocuments('a')).single, a);
      expect((await db.getQueuedDocuments('b')).single, b);
      expect(await file.readAsString(), '%PDF fixture');
      await db.close();
      await temp.delete(recursive: true);
    },
  );
}
