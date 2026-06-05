import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'local_database.g.dart';

@DataClassName('CachedPatient')
class CachedPatients extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().nullable()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  DateTimeColumn get dateOfBirth => dateTime()();
  TextColumn get gender => text()();
  TextColumn get contactNumber => text()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedDocument')
class CachedDocuments extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text().nullable()();
  TextColumn get uploaderId => text()();
  TextColumn get fileName => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()();
  TextColumn get status => text()();
  TextColumn get ocrText => text().nullable()();
  TextColumn get extractedMetadata => text().nullable()(); // JSON-serialized
  TextColumn get rejectionReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedPatientQueue')
class CachedPatientQueues extends Table {
  IntColumn get id => integer()();
  TextColumn get patientId => text()();
  TextColumn get status => text()();
  TextColumn get department => text()();
  TextColumn get triageNotes => text().nullable()();
  TextColumn get priorityLevel => text()();
  IntColumn get estimatedWaitMinutes => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CachedDepartmentRecord')
class CachedDepartmentRecords extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get recorderId => text()();
  TextColumn get department => text()();
  TextColumn get testType => text()();
  TextColumn get testResults => text()(); // JSON-serialized
  TextColumn get referenceRangeStatus => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OfflineDocument')
class OfflineDocumentsQueue extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text().nullable()();
  TextColumn get uploaderId => text()();
  TextColumn get fileName => text()();
  TextColumn get localFilePath => text()();
  TextColumn get fileType => text()();
  TextColumn get ocrText => text().nullable()();
  TextColumn get extractedMetadata => text().nullable()(); // JSON-serialized
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  CachedPatients,
  CachedDocuments,
  CachedPatientQueues,
  CachedDepartmentRecords,
  OfflineDocumentsQueue,
])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // Helpers to fetch and update cached dashboard data
  Future<void> cachePatient(CachedPatient patient) async {
    await into(cachedPatients).insertOnConflictUpdate(patient);
  }

  Future<CachedPatient?> getPatient(String id) async {
    return (select(cachedPatients)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> cacheDocuments(List<CachedDocument> docs) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedDocuments, docs);
    });
  }

  Future<List<CachedDocument>> getDocumentsForPatient(String uploaderId) async {
    return (select(cachedDocuments)
          ..where((t) => t.uploaderId.equals(uploaderId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> cacheQueueEntries(List<CachedPatientQueue> entries) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedPatientQueues, entries);
    });
  }

  Future<List<CachedPatientQueue>> getQueueForPatient(String patientId) async {
    return (select(cachedPatientQueues)
          ..where((t) => t.patientId.equals(patientId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> cacheDepartmentRecords(List<CachedDepartmentRecord> records) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(cachedDepartmentRecords, records);
    });
  }

  Future<List<CachedDepartmentRecord>> getRecordsForPatient(String patientId) async {
    return (select(cachedDepartmentRecords)
          ..where((t) => t.patientId.equals(patientId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  // Offline Upload Queue Helpers
  Future<void> queueOfflineDocument(OfflineDocument doc) async {
    await into(offlineDocumentsQueue).insert(doc);
  }

  Future<List<OfflineDocument>> getQueuedDocuments() async {
    return select(offlineDocumentsQueue).get();
  }

  Future<void> removeQueuedDocument(String id) async {
    await (delete(offlineDocumentsQueue)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearAllCache() async {
    await delete(cachedPatients).go();
    await delete(cachedDocuments).go();
    await delete(cachedPatientQueues).go();
    await delete(cachedDepartmentRecords).go();
    // Do not clear offlineDocumentsQueue as it contains unsubmitted files.
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'klinikaid_local.db'));
    return NativeDatabase.createInBackground(file);
  });
}
