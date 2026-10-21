import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';

// ---------------------------------------------------------------------------
// Mock auth identity: settable current user plus an auth-change stream.
// ---------------------------------------------------------------------------
class MockAuthIdentity extends Fake implements GoTrueClient {
  @override
  User? currentUser;
  @override
  Session? currentSession;

  final StreamController<AuthState> _events =
      StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get onAuthStateChange => _events.stream;

  /// Identity change with no auth event at all (worst case for invalidation).
  void switchTo(String userId) {
    currentUser = _mockUser(userId);
  }

  User _mockUser(String userId) => User(
        id: userId,
        appMetadata: const <String, dynamic>{},
        userMetadata: const <String, dynamic>{},
        aud: 'authenticated',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
}

// ---------------------------------------------------------------------------
// Mock storage: records dispatched uploads, can stall or fail one mid-flight.
// ---------------------------------------------------------------------------
class StorageApi extends Fake implements StorageFileApi {
  final List<String> uploads = [];
  Completer<void>? uploadStarted;
  Completer<void>? uploadGate;
  bool failWithSocketException = false;
  bool failWithHandshake = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upload) {
      return _upload(invocation.positionalArguments.first as String);
    }
    return super.noSuchMethod(invocation);
  }

  Future<String> _upload(String path) async {
    final started = uploadStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = uploadGate;
    if (gate != null) await gate.future;
    // The request is on the wire before the simulated drop, so a failed
    // upload counts as dispatched and cannot be recalled.
    uploads.add(path);
    if (failWithSocketException) {
      throw const SocketException('Simulated offline drop');
    }
    if (failWithHandshake) {
      throw FakeHandshakeException();
    }
    return path;
  }
}

class StorageClient extends Fake implements SupabaseStorageClient {
  StorageClient(this.api);
  final StorageApi api;

  @override
  StorageFileApi from(String id) => api;
}

// ---------------------------------------------------------------------------
// Mock documents table: gated duplicate reads (the `select … eq … eq` used by
// checkPendingDuplicate) and recorded, optionally gated inserts.
// ---------------------------------------------------------------------------

/// Mutable state of the duplicate lookup, kept in a plain holder so the
/// mocked builder itself can stay final-field only.
class DuplicateReadState {
  int reads = 0;
  List<PostgrestMap> rows = [];
  Completer<void>? started;
  Completer<void>? gate;
  bool _gateNext = false;

  /// Stalls the next duplicate read until [gate] completes.
  void gateNextRead() {
    started = Completer<void>();
    gate = Completer<void>();
    _gateNext = true;
  }

  Future<List<PostgrestMap>> resolve() async {
    reads++;
    final begin = started;
    if (begin != null && !begin.isCompleted) begin.complete();
    if (_gateNext) {
      _gateNext = false;
      await gate!.future;
    }
    return rows;
  }
}

class InsertGate {
  Completer<void>? started;
  Completer<void>? gate;
}

class DocumentsApi extends Fake implements SupabaseQueryBuilder {
  final List<PostgrestMap> inserted = [];
  final DuplicateReadState duplicateState = DuplicateReadState();
  final InsertGate insertGate = InsertGate();

  @override
  PostgrestFilterBuilder<PostgrestList> select([String columns = '*']) =>
      DuplicateReadQuery(this);

  @override
  PostgrestFilterBuilder<dynamic> insert(Object values,
      {bool defaultToNull = true}) {
    final row = PostgrestMap.from(values as Map);
    inserted.add(row);
    return GatedInsert(row, started: insertGate.started, gate: insertGate.gate);
  }
}

class DuplicateReadQuery extends Fake
    implements PostgrestFilterBuilder<PostgrestList> {
  DuplicateReadQuery(this._api);
  final DocumentsApi _api;

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) => this;

  @override
  Future<S> then<S>(FutureOr<S> Function(PostgrestList value) onValue,
      {Function? onError}) {
    return _api.duplicateState.resolve().then(onValue, onError: onError);
  }

  @override
  Future<PostgrestList> timeout(Duration timeLimit,
      {FutureOr<PostgrestList> Function()? onTimeout}) {
    return _api.duplicateState
        .resolve()
        .timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<PostgrestList> catchError(Function onError,
      {bool Function(Object error)? test}) {
    return _api.duplicateState.resolve().catchError(onError, test: test);
  }

  @override
  Future<PostgrestList> whenComplete(FutureOr<void> Function() action) {
    return _api.duplicateState.resolve().whenComplete(action);
  }

  @override
  Stream<PostgrestList> asStream() => _api.duplicateState.resolve().asStream();
}

class GatedSingle extends Fake implements PostgrestTransformBuilder<PostgrestMap> {
  GatedSingle(this._row, {this.started, this.gate});
  final PostgrestMap _row;
  final Completer<void>? started;
  final Completer<void>? gate;

  Future<void> _wait() async {
    final begin = started;
    if (begin != null && !begin.isCompleted) begin.complete();
    final pending = gate;
    if (pending != null) await pending.future;
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(PostgrestMap value) onValue,
      {Function? onError}) {
    return _wait().then(
        (_) => Future<PostgrestMap>.value(_row).then(onValue, onError: onError));
  }

  @override
  Future<PostgrestMap> timeout(Duration timeLimit,
      {FutureOr<PostgrestMap> Function()? onTimeout}) {
    return _wait().then((_) => Future<PostgrestMap>.value(_row))
        .timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<PostgrestMap> catchError(Function onError,
      {bool Function(Object error)? test}) {
    return _wait()
        .then((_) => Future<PostgrestMap>.value(_row))
        .catchError(onError, test: test);
  }

  @override
  Future<PostgrestMap> whenComplete(FutureOr<void> Function() action) {
    return _wait().then((_) => Future<PostgrestMap>.value(_row)).whenComplete(action);
  }

  @override
  Stream<PostgrestMap> asStream() =>
      _wait().then((_) => Future<PostgrestMap>.value(_row)).asStream();
}

class GatedSelect extends Fake implements PostgrestTransformBuilder<PostgrestList> {
  GatedSelect(this._row, {this.started, this.gate});
  final PostgrestMap _row;
  final Completer<void>? started;
  final Completer<void>? gate;

  @override
  PostgrestTransformBuilder<PostgrestMap> single() =>
      GatedSingle(_row, started: started, gate: gate);
}

class GatedInsert extends Fake implements PostgrestFilterBuilder<dynamic> {
  GatedInsert(this._row, {this.started, this.gate});
  final PostgrestMap _row;
  final Completer<void>? started;
  final Completer<void>? gate;

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      GatedSelect(_row, started: started, gate: gate);
}

class MockSupabaseClient extends Fake implements SupabaseClient {
  MockSupabaseClient(this.auth);

  @override
  final MockAuthIdentity auth;
  @override
  late final StorageClient storage = StorageClient(StorageApi());
  final DocumentsApi docsApi = DocumentsApi();

  StorageApi get storageApi => storage.api;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #from) {
      return docsApi;
    }
    return super.noSuchMethod(invocation);
  }
}

/// A real [File] whose `exists` call can be stalled. Injected through
/// dart:io's own `IOOverrides` seam so the concrete `File(...)` built by the
/// provider is gated without a production abstraction.
class GatedExistsFile extends Fake implements File {
  GatedExistsFile(this._real, this.started, this.gate);
  final File _real;
  final Completer<void> started;
  final Completer<void> gate;

  @override
  Future<bool> exists() async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    return _real.exists();
  }
}

/// A non-socket network failure. [FailureMapper] maps it to NetworkFailure
/// only via its message, so it reaches the generic offline branch that the
/// earlier `on SocketException` clause can never cover.
class FakeHandshakeException implements Exception {
  @override
  String toString() => 'HandshakeException: simulated TLS drop';
}

/// Real local database whose offline-queue write and owner-scoped read can be
/// stalled, so an identity change can be injected while either local await
/// waits instead of racing it.
class GatedLocalDatabase extends LocalDatabase {
  GatedLocalDatabase([super.executor]);

  Completer<void>? queueStarted;
  Completer<void>? queueGate;
  Completer<void>? readStarted;
  Completer<void>? readGate;

  @override
  Future<void> queueOfflineDocument(OfflineDocument doc) async {
    final begin = queueStarted;
    if (begin != null && !begin.isCompleted) begin.complete();
    final gate = queueGate;
    if (gate != null) await gate.future;
    await super.queueOfflineDocument(doc);
  }

  @override
  Future<List<OfflineDocument>> getQueuedDocuments(String uploaderId) async {
    final begin = readStarted;
    if (begin != null && !begin.isCompleted) begin.complete();
    final gate = readGate;
    if (gate != null) await gate.future;
    return super.getQueuedDocuments(uploaderId);
  }
}

Patient _patient({String? profileId, String id = 'patient-uuid-1'}) => Patient(
      id: id,
      profileId: profileId,
      firstName: 'Alice',
      lastName: 'Nguyen',
      dateOfBirth: DateTime(1995, 4, 12),
      gender: Gender.female,
      contactNumber: '09170000000',
      address: 'Manila, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'user-a';
  const userB = 'user-b';
  const patientIdA = 'patient-uuid-1';

  late MockSupabaseClient client;
  late MockAuthIdentity auth;
  late GatedLocalDatabase db;
  late Directory tempDir;

  setUp(() async {
    auth = MockAuthIdentity();
    client = MockSupabaseClient(auth);
    SupabaseService.mockClient = client;
    db = GatedLocalDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('immediate_owner');
  });

  tearDown(() async {
    SupabaseService.mockClient = null;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String uploadPath(String name) => '${tempDir.path}/$name.jpg';

  void writeUpload(String name) =>
      File(uploadPath(name)).writeAsStringSync('bytes for $name');

  Future<List<String>> queuedIds() async =>
      (await db.select(db.offlineDocumentsQueue).get())
          .map((d) => d.id)
          .toList();

  Future<void> seedDraft(String id, String uploader) {
    File('${tempDir.path}/$id.jpg').writeAsStringSync('draft bytes for $id');
    return db.queueOfflineDocument(OfflineDocument(
      id: id,
      patientId: patientIdA,
      uploaderId: uploader,
      fileName: '$id.jpg',
      localFilePath: '${tempDir.path}/$id.jpg',
      fileType: 'jpg',
      ocrText: 'ocr $id',
      extractedMetadata: null,
      createdAt: DateTime.now(),
    ));
  }

  Future<bool> submit(
    DocumentSubmissionProvider provider, {
    required Patient patient,
    String name = 'submit-a',
    String documentType = 'laboratory',
  }) =>
      provider.submitDocument(
        localFilePath: uploadPath(name),
        originalFileName: '$name.jpg',
        fileExtension: 'jpg',
        patient: patient,
        documentType: documentType,
      );

  // -------------------------------------------------------------------------
  // H1: the owner used to be captured after the awaited duplicate lookup.
  // -------------------------------------------------------------------------
  test(
      'N1: identity change while the duplicate lookup awaits dispatches no write',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    client.docsApi.duplicateState.gateNextRead();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await client.docsApi.duplicateState.started!.future; // the lookup is pending now
    auth.switchTo(userB); // account changes while that read waits
    client.docsApi.duplicateState.gate!.complete();

    expect(await submitted, isFalse,
        reason: 'the submit belongs to A\'s session and must be abandoned');
    expect(client.storageApi.uploads, isEmpty,
        reason: 'no upload may be dispatched under the newer identity');
    expect(client.docsApi.inserted, isEmpty,
        reason: 'no document row may be written under the newer identity');
    expect(await queuedIds(), isEmpty,
        reason: 'an abandoned submit queues nothing');
    expect(provider.errorMessage, 'Session changed. Please try again.');
    expect(provider.isLoading, isFalse);
  });

  // -------------------------------------------------------------------------
  // H2: the insert used to be dispatched after the upload with no owner check.
  // -------------------------------------------------------------------------
  test('N2: identity change while the upload awaits writes nothing afterwards',
      () async {
    auth.switchTo(userA);
    await seedDraft('draft-a', userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    client.storageApi.uploadStarted = Completer<void>();
    client.storageApi.uploadGate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await client.storageApi.uploadStarted!.future; // the upload is pending now
    auth.switchTo(userB);
    client.storageApi.uploadGate!.complete();

    expect(await submitted, isFalse,
        reason: 'a changed session must not be told the submit succeeded');
    expect(client.docsApi.inserted, isEmpty,
        reason: 'no document row may be written once the identity changed');
    expect(client.storageApi.uploads, hasLength(1),
        reason: 'the already-dispatched upload cannot be recalled (limit)');
    expect(await queuedIds(), contains('draft-a'),
        reason: 'A\'s existing draft survives the abandoned submit');
  });

  test('N3: identity change while the insert awaits reports no stale success',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    client.docsApi.insertGate.started = Completer<void>();
    client.docsApi.insertGate.gate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await client.docsApi.insertGate.started!.future; // the insert is pending now
    auth.switchTo(userB);
    client.docsApi.insertGate.gate!.complete();

    expect(await submitted, isFalse,
        reason: 'the dispatched insert cannot be recalled, and neither can '
            'the success that would be reported for it');
    expect(provider.errorMessage, 'Session changed. Please try again.');
    expect(client.docsApi.inserted, hasLength(1),
        reason: 'the already-dispatched insert cannot be recalled (limit)');
  });

  // -------------------------------------------------------------------------
  // A patient object loaded for another profile must never be submitted under
  // this session, with or without an async boundary.
  // -------------------------------------------------------------------------
  test('N4: a patient object from a different linked profile is rejected',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final submitted =
        submit(provider, patient: _patient(profileId: 'profile-uuid-foreign'));

    expect(await submitted, isFalse);
    expect(client.docsApi.duplicateState.reads, 0,
        reason: 'nothing is read on behalf of a foreign patient object');
    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsApi.inserted, isEmpty);
    expect(provider.errorMessage, 'Session changed. Please try again.');
  });

  test('N5: a superseded submit cannot overwrite a newer operation\'s state',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    client.docsApi.duplicateState.gateNextRead();
    final stale =
        submit(provider, patient: _patient(profileId: userA), name: 'submit-a');
    await client.docsApi.duplicateState.started!.future; // the first submit waits

    auth.switchTo(userB);
    final newer = submit(provider,
        patient: _patient(profileId: userB, id: 'patient-uuid-2'),
        name: 'missing-b'); // its file does not exist: it fails on its own
    expect(await newer, isFalse);
    expect(provider.errorMessage,
        contains('Captured image file does not exist locally'),
        reason: 'the newer operation owns the visible state');

    client.docsApi.duplicateState.gate!.complete(); // the stale submit resumes now
    expect(await stale, isFalse);

    expect(provider.errorMessage,
        contains('Captured image file does not exist locally'),
        reason: 'the stale operation must not overwrite the newer state');
    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsApi.inserted, isEmpty);
  });

  // -------------------------------------------------------------------------
  // Preserved behaviour: same-owner online submit, offline draft, denial.
  // -------------------------------------------------------------------------
  test('N6: same-owner submit uploads and inserts under the captured owner',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final submitted = submit(provider, patient: _patient(profileId: userA));

    expect(await submitted, isTrue);
    expect(client.storageApi.uploads, hasLength(1));
    expect(client.storageApi.uploads.single, startsWith('$userA/'));
    expect(client.docsApi.inserted, hasLength(1));
    expect(client.docsApi.inserted.single['patient_id'], patientIdA);
    expect(client.docsApi.inserted.single['uploader_id'], userA);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
    expect(await queuedIds(), isEmpty);
  });

  test('N7: signed out rejects before any backend read or write', () async {
    auth.currentUser = null;
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final submitted = submit(provider, patient: _patient(profileId: userA));

    expect(await submitted, isFalse);
    expect(client.docsApi.duplicateState.reads, 0,
        reason: 'an unauthenticated caller triggers no backend read');
    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsApi.inserted, isEmpty);
    expect(provider.errorMessage, 'Session expired. Please log in again.');
    expect(await queuedIds(), isEmpty);
  });

  test('N8: a pending duplicate of the same category is still denied', () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.docsApi.duplicateState.rows = [
      <String, dynamic>{
        'file_type': 'jpg',
        'status': 'pending',
        'extracted_metadata': <String, dynamic>{'document_type': 'laboratory'},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }
    ];
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final submitted = submit(provider, patient: _patient(profileId: userA));

    expect(await submitted, isFalse);
    expect(provider.errorMessage, contains('You already have a pending'));
    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsApi.inserted, isEmpty);
  });

  test('N9: a dropped connection still queues the draft under its owner',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.storageApi.failWithSocketException = true;
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final submitted = submit(provider, patient: _patient(profileId: userA));

    expect(await submitted, isTrue,
        reason: 'the reviewed offline fallback is preserved');
    expect(provider.errorMessage, 'You are currently offline. Document queued for sync.');
    final queued = await db.select(db.offlineDocumentsQueue).get();
    expect(queued, hasLength(1));
    expect(queued.single.uploaderId, userA,
        reason: 'the offline draft stays attributed to the owner that started it');
    expect(queued.single.patientId, patientIdA);
  });

  test('N10: an account switch while the file lookup awaits queues nothing',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    final started = Completer<void>();
    final gate = Completer<void>();
    final realFile = File(uploadPath('submit-a'));
    final submitted = IOOverrides.runZoned(
      () => submit(provider, patient: _patient(profileId: userA)),
      createFile: (path) => GatedExistsFile(realFile, started, gate),
    );
    await started.future; // the concrete File.exists() call is pending now
    auth.switchTo(userB);
    gate.complete();

    expect(await submitted, isFalse);
    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsApi.inserted, isEmpty);
    expect(await queuedIds(), isEmpty);
  });

  // -------------------------------------------------------------------------
  // Round 2: the offline fallback used to check ownership only before the
  // local queue write, then unconditionally reported the fallback success
  // after two local awaits.
  // -------------------------------------------------------------------------
  test(
      'N11: session switch while the offline draft write awaits is not told the fallback succeeded',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.storageApi.failWithSocketException = true;
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    db.queueStarted = Completer<void>();
    db.queueGate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await db.queueStarted!.future; // the local draft write is pending now
    auth.switchTo(userB);
    db.queueGate!.complete();

    expect(await submitted, isFalse,
        reason: 'a session that changed while the draft was being written '
            'must be abandoned, not told the submit succeeded');
    expect(provider.errorMessage, 'Session changed. Please try again.');
    expect(provider.isLoading, isFalse);
    final queued = await db.select(db.offlineDocumentsQueue).get();
    expect(queued, hasLength(1),
        reason: 'the already-written local draft is preserved');
    expect(queued.single.uploaderId, userA,
        reason: 'it stays attributed to its owner and is never rewritten for B');
  });

  test(
      'N12: session switch while the offline queue reload awaits is not told the fallback succeeded',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.storageApi.failWithSocketException = true;
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    db.readStarted = Completer<void>();
    db.readGate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await db.readStarted!.future; // the post-write queue reload is pending now
    auth.switchTo(userB);
    db.readGate!.complete();

    expect(await submitted, isFalse);
    expect(provider.errorMessage, 'Session changed. Please try again.');
    expect(provider.isLoading, isFalse);
    final queued = await db.select(db.offlineDocumentsQueue).get();
    expect(queued.single.uploaderId, userA,
        reason: 'the draft already written stays owned by A, never rewritten');
  });

  test(
      'N13: session switch while the network-failure draft write awaits is not told the fallback succeeded',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.storageApi.failWithHandshake = true;
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    db.queueStarted = Completer<void>();
    db.queueGate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await db.queueStarted!.future;
    auth.switchTo(userB);
    db.queueGate!.complete();

    expect(await submitted, isFalse,
        reason: 'the generic NetworkFailure branch gets the same owner rule');
    expect(provider.errorMessage, 'Session changed. Please try again.');
    final queued = await db.select(db.offlineDocumentsQueue).get();
    expect(queued.single.uploaderId, userA);
  });

  test(
      'N14: session switch while the network-failure queue reload awaits is not told the fallback succeeded',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    client.storageApi.failWithHandshake = true;
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    db.readStarted = Completer<void>();
    db.readGate = Completer<void>();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await db.readStarted!.future;
    auth.switchTo(userB);
    db.readGate!.complete();

    expect(await submitted, isFalse);
    expect(provider.errorMessage, 'Session changed. Please try again.');
    final queued = await db.select(db.offlineDocumentsQueue).get();
    expect(queued.single.uploaderId, userA);
  });

  // -------------------------------------------------------------------------
  // Round 2: a completion that finishes after dispose must not mutate the
  // provider or notify. Actual scope: disposal suppresses state application;
  // an upload/insert dispatched before dispose is unchanged and unrecalled.
  // -------------------------------------------------------------------------
  test('N15: a submit completion after dispose mutates nothing and notifies nothing',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    var notifications = 0;
    provider.addListener(() => notifications++);

    client.docsApi.duplicateState.gateNextRead();
    final submitted = submit(provider, patient: _patient(profileId: userA));
    await client.docsApi.duplicateState.started!.future; // the lookup waits now
    provider.dispose();
    final seenBeforeRelease = notifications;
    client.docsApi.duplicateState.gate!.complete();

    expect(await submitted, isTrue,
        reason: 'the writes were dispatched while the provider was alive');
    expect(notifications, seenBeforeRelease,
        reason: 'a disposed provider is never notified');
    expect(provider.isLoading, isTrue,
        reason: 'visible state is frozen at dispose, not mutated late');
    expect(provider.errorMessage, isNull);
    expect(client.storageApi.uploads, hasLength(1));
    expect(client.docsApi.inserted, hasLength(1));
  });

  // Round 2 wording pin: same-owner generation supersession guards the visible
  // state only. The superseded call keeps its own result and its own writes;
  // it is a cross-session change, not a same-owner supersession, that abandons
  // a submit.
  test('N16: same-owner supersession guards visible state only, the superseded call still returns true',
      () async {
    auth.switchTo(userA);
    writeUpload('submit-a');
    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    client.docsApi.duplicateState.gateNextRead();
    final superseded =
        submit(provider, patient: _patient(profileId: userA), name: 'submit-a');
    await client.docsApi.duplicateState.started!.future; // the first call waits

    final newer = submit(provider,
        patient: _patient(profileId: userA, id: 'patient-uuid-2'),
        name: 'missing-b'); // its file does not exist: it fails on its own
    expect(await newer, isFalse);
    expect(provider.errorMessage,
        contains('Captured image file does not exist locally'));

    client.docsApi.duplicateState.gate!.complete();
    expect(await superseded, isTrue,
        reason: 'same-owner supersession is UI-state only: the older call '
            'completes its own writes and keeps its own return value');
    expect(provider.errorMessage,
        contains('Captured image file does not exist locally'),
        reason: 'the newer operation keeps the visible state');
    expect(client.storageApi.uploads, hasLength(1));
    expect(client.docsApi.inserted, hasLength(1));
    expect(client.docsApi.inserted.single['uploader_id'], userA);
  });
}
