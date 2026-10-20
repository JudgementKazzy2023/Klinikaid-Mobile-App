import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';

// ---------------------------------------------------------------------------
// Mock auth identity: settable current user plus a pushable auth-change stream.
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

  /// Signed in as [userId], emitting the auth event a real client would emit.
  void signInAs(String userId) {
    currentUser = _mockUser(userId);
    _events.add(AuthState(AuthChangeEvent.signedIn, null));
  }

  /// Signed out, emitting the auth event a real client would emit.
  void emitSignedOut() {
    currentUser = null;
    _events.add(AuthState(AuthChangeEvent.signedOut, null));
  }

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
// Mock storage: records uploads and can stall an upload mid-flight.
// ---------------------------------------------------------------------------
class MockStorageApi extends Fake implements StorageFileApi {
  final List<String> uploads = [];
  Completer<void>? uploadStarted;
  Completer<void>? uploadGate;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upload) {
      return _upload(invocation.positionalArguments.first as String);
    }
    return super.noSuchMethod(invocation);
  }

  Future<String> _upload(String path) async {
    if (uploadStarted != null && !uploadStarted!.isCompleted) {
      uploadStarted!.complete();
    }
    if (uploadGate != null) {
      await uploadGate!.future;
    }
    uploads.add(path);
    return path;
  }
}

class MockStorageClient extends Fake implements SupabaseStorageClient {
  MockStorageClient(this.api);
  final MockStorageApi api;

  @override
  StorageFileApi from(String id) => api;
}

// ---------------------------------------------------------------------------
// Mock documents table: records insert payloads for insert(...).select().single()
// ---------------------------------------------------------------------------
class MockSingle extends Fake implements PostgrestTransformBuilder<PostgrestMap> {
  MockSingle(this._row);
  final PostgrestMap _row;

  @override
  Future<S> then<S>(FutureOr<S> Function(PostgrestMap value) onValue,
      {Function? onError}) {
    return Future<PostgrestMap>.value(_row).then(onValue, onError: onError);
  }

  @override
  Future<PostgrestMap> timeout(Duration timeLimit,
      {FutureOr<PostgrestMap> Function()? onTimeout}) {
    return Future<PostgrestMap>.value(_row).timeout(timeLimit,
        onTimeout: onTimeout);
  }

  @override
  Future<PostgrestMap> catchError(Function onError,
      {bool Function(Object error)? test}) {
    return Future<PostgrestMap>.value(_row).catchError(onError, test: test);
  }

  @override
  Future<PostgrestMap> whenComplete(FutureOr<void> Function() action) {
    return Future<PostgrestMap>.value(_row).whenComplete(action);
  }

  @override
  Stream<PostgrestMap> asStream() => Stream<PostgrestMap>.value(_row);
}

class MockSelect extends Fake implements PostgrestTransformBuilder<PostgrestList> {
  MockSelect(this._row);
  final PostgrestMap _row;

  @override
  PostgrestTransformBuilder<PostgrestMap> single() => MockSingle(_row);
}

class MockInsert extends Fake implements PostgrestFilterBuilder<dynamic> {
  MockInsert(this._row);
  final PostgrestMap _row;

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      MockSelect(_row);
}

class MockDocumentsTable extends Fake implements SupabaseQueryBuilder {
  final List<PostgrestMap> inserted = [];

  @override
  PostgrestFilterBuilder<dynamic> insert(Object values,
      {bool defaultToNull = true}) {
    final row = PostgrestMap.from(values as Map);
    inserted.add(row);
    return MockInsert(row);
  }
}

class MockSupabaseClient extends Fake implements SupabaseClient {
  MockSupabaseClient(this.auth);

  @override
  final MockAuthIdentity auth;
  @override
  final MockStorageClient storage = MockStorageClient(MockStorageApi());
  final MockDocumentsTable docsTable = MockDocumentsTable();

  MockStorageApi get storageApi => storage.api;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #from) {
      return docsTable;
    }
    return super.noSuchMethod(invocation);
  }
}

// ---------------------------------------------------------------------------
// Local database doubles.
// ---------------------------------------------------------------------------
/// Owner-scoped read behind an explicit gate, to interleave an identity switch
/// with an awaited queue load.
class GatedQueueDb extends LocalDatabase {
  GatedQueueDb() : super(NativeDatabase.memory());

  final Completer<void> readStarted = Completer<void>();
  final Completer<void> readGate = Completer<void>();

  @override
  Future<List<OfflineDocument>> getQueuedDocuments([String? uploaderId]) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate.future;
    final all = await select(offlineDocumentsQueue).get();
    if (uploaderId == null) return all;
    return all.where((d) => d.uploaderId == uploaderId).toList();
  }
}

/// Queue reads fail (own-item load failure path).
class FailingQueueDb extends LocalDatabase {
  FailingQueueDb() : super(NativeDatabase.memory());

  @override
  Future<List<OfflineDocument>> getQueuedDocuments([String? uploaderId]) =>
      Future<List<OfflineDocument>>.error(StateError('queue read failed'));
}

/// Queue deletes fail (own-item delete failure path).
class FailingDeleteDb extends LocalDatabase {
  FailingDeleteDb() : super(NativeDatabase.memory());

  @override
  Future<int> removeQueuedDocument(String id, [String? uploaderId]) =>
      Future<int>.error(StateError('queue delete failed'));
}

// ---------------------------------------------------------------------------
// AuthProvider double for the screen test.
// ---------------------------------------------------------------------------
class StaticPatientAuthProvider extends AuthProvider {
  StaticPatientAuthProvider(this._patient, {super.client});
  final Patient _patient;

  @override
  Patient? get patient => _patient;
  @override
  bool get isLoading => false;
  @override
  bool get isAuthenticated => true;
}

Patient _patient() => Patient(
      id: 'patient-uuid-1',
      profileId: 'profile-uuid-1',
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

  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(prefsChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') return <String, Object>{};
    return true;
  });

  const userA = 'user-a';
  const userB = 'user-b';

  late MockSupabaseClient client;
  late MockAuthIdentity auth;
  late LocalDatabase db;
  late Directory tempDir;

  setUp(() async {
    auth = MockAuthIdentity();
    client = MockSupabaseClient(auth);
    SupabaseService.mockClient = client;
    db = LocalDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('deferred_drafts');
  });

  tearDown(() async {
    SupabaseService.mockClient = null;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String draftPath(String id) => '${tempDir.path}/$id.jpg';

  Future<void> seedDraft(String id, String uploader, {bool withFile = true}) {
    if (withFile) {
      File(draftPath(id)).writeAsStringSync('draft bytes for $id');
    }
    return db.queueOfflineDocument(OfflineDocument(
      id: id,
      patientId: 'patient-uuid-1',
      uploaderId: uploader,
      fileName: '$id.jpg',
      localFilePath: draftPath(id),
      fileType: 'jpg',
      ocrText: 'ocr $id',
      extractedMetadata: null,
      createdAt: DateTime.now(),
    ));
  }

  Future<List<String>> queuedIds() async =>
      (await db.select(db.offlineDocumentsQueue).get())
          .map((d) => d.id)
          .toList();

  // -------------------------------------------------------------------------
  // Original failure: foreign draft metadata rendered on the signed-in
  // account's screen.
  // -------------------------------------------------------------------------
  testWidgets(
      'submit screen signed in as B does not render A\'s queued draft metadata',
      (tester) async {
    db = FailingDeleteDb();
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await tester.runAsync(() => pumpEventQueue());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: StaticPatientAuthProvider(_patient(), client: client),
          ),
          ChangeNotifierProvider<DocumentSubmissionProvider>.value(
            value: provider,
          ),
        ],
        child: const MaterialApp(home: SubmitDocumentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline Sync Queue'), findsOneWidget,
        reason: 'the account\'s own queue section is still shown');
    expect(find.text('draft-b.jpg'), findsOneWidget,
        reason: 'B sees its own draft');
    expect(find.text('draft-a.jpg'), findsNothing,
        reason: 'another account\'s draft metadata must not be rendered');
    expect(find.text('Account Mismatch (Submit blocked)'), findsNothing,
        reason: 'foreign rows are no longer surfaced as a queue state');

    provider.dispose();
  });

  // -------------------------------------------------------------------------
  // Original failure: cross-account deletion.
  // -------------------------------------------------------------------------
  test('removeQueuedItem for A\'s draft is a no-op while signed in as B',
      () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    await provider.removeQueuedItem('draft-a');

    expect(await queuedIds(), containsAll(<String>['draft-a', 'draft-b']),
        reason: 'B must not delete A\'s queued draft');
  });

  test('removeQueuedItem is a no-op while signed out', () async {
    await seedDraft('draft-a', userA);
    auth.currentUser = null;

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    await provider.removeQueuedItem('draft-a');

    expect(await queuedIds(), contains('draft-a'),
        reason: 'an unauthenticated caller must not delete queued drafts');
    expect(provider.queuedSubmissions, isEmpty,
        reason: 'an unauthenticated caller must not see queued drafts');
  });

  // -------------------------------------------------------------------------
  // Original failure: identity switched while the queue read is awaited.
  // -------------------------------------------------------------------------
  test('identity change during the awaited queue load applies no stale results',
      () async {
    final gatedDb = GatedQueueDb();
    db = gatedDb;
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await gatedDb.readStarted.future;
    auth.switchTo(userB);
    gatedDb.readGate.complete();
    await pumpEventQueue();

    expect(provider.queuedSubmissions, isEmpty,
        reason: 'results read for A must not be applied once identity is B');
    expect(await queuedIds(), containsAll(<String>['draft-a', 'draft-b']),
        reason: 'a discarded read deletes nothing');

    auth.signInAs(userB);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-b'],
        reason: 'after sign-in B only B\'s draft is visible');
  });

  // -------------------------------------------------------------------------
  // Original failure: identity switched while the sync upload is awaited.
  // -------------------------------------------------------------------------
  test('identity change during the awaited sync upload writes and deletes nothing',
      () async {
    await seedDraft('draft-a', userA);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-a']);

    final started = Completer<void>();
    final gate = Completer<void>();
    client.storageApi.uploadStarted = started;
    client.storageApi.uploadGate = gate;

    final sync = provider.syncOfflineQueue();
    await started.future;
    auth.switchTo(userB);
    gate.complete();
    await sync;

    expect(client.docsTable.inserted, isEmpty,
        reason: 'no document row may be written after the identity changed');
    expect(client.storageApi.uploads, hasLength(1),
        reason: 'the already-dispatched upload itself cannot be recalled');
    expect(await queuedIds(), contains('draft-a'),
        reason: 'A\'s queued draft must not be deleted under identity B');
  });

  // -------------------------------------------------------------------------
  // Acceptance: only the signed-in account's metadata is visible.
  // -------------------------------------------------------------------------
  test('sign in as B reveals only B\'s queued drafts', () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-b']);
    expect(await queuedIds(), containsAll(<String>['draft-a', 'draft-b']),
        reason: 'visibility scoping never drops the other account\'s rows');
  });

  test('A\'s drafts are restored on the next A login', () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-b']);

    auth.signInAs(userA);
    await pumpEventQueue();

    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-a'],
        reason: 'A\'s deferred draft comes back after A signs in again');
    expect(await queuedIds(), containsAll(<String>['draft-a', 'draft-b']),
        reason: 'the draft rows themselves were preserved meanwhile');
  });

  test('signed-out state reveals, deletes and syncs nothing', () async {
    await seedDraft('draft-a', userA);
    auth.currentUser = null;

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    expect(provider.queuedSubmissions, isEmpty);
    await provider.removeQueuedItem('draft-a');
    await provider.syncOfflineQueue();

    expect(client.storageApi.uploads, isEmpty);
    expect(client.docsTable.inserted, isEmpty);
    expect(await queuedIds(), contains('draft-a'),
        reason: 'signing out preserves the queued draft');
    expect(File(draftPath('draft-a')).existsSync(), isTrue,
        reason: 'the queued file itself is preserved');
  });

  test('logout preserves A\'s draft rows and files while revealing none',
      () async {
    await seedDraft('draft-a', userA);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-a']);

    auth.emitSignedOut();
    await pumpEventQueue();

    expect(provider.queuedSubmissions, isEmpty);
    expect(await queuedIds(), contains('draft-a'));
    expect(File(draftPath('draft-a')).existsSync(), isTrue);
  });

  test('account mismatch preserves the other account\'s draft', () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-b']);
    expect(await queuedIds(), contains('draft-a'),
        reason: 'A\'s row survives the account mismatch untouched');
    expect(File(draftPath('draft-a')).existsSync(), isTrue);
  });

  // -------------------------------------------------------------------------
  // Acceptance: B's sync can never upload or delete A's draft.
  // -------------------------------------------------------------------------
  test('B\'s sync uploads B\'s draft only and never touches A\'s', () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userB);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    await provider.syncOfflineQueue();

    expect(client.storageApi.uploads, hasLength(1));
    expect(client.storageApi.uploads.single, startsWith('$userB/'),
        reason: 'only B\'s storage path is written');
    expect(client.docsTable.inserted, hasLength(1));
    expect(client.docsTable.inserted.single['uploader_id'], userB);
    expect(await queuedIds(), contains('draft-a'),
        reason: 'A\'s draft is neither uploaded nor deleted by B\'s sync');
    expect(await queuedIds(), isNot(contains('draft-b')),
        reason: 'B\'s own draft completes normally');
  });

  // -------------------------------------------------------------------------
  // Failure paths and same-owner normal operations.
  // -------------------------------------------------------------------------
  test('failed queue read reveals nothing and does not throw', () async {
    db = FailingQueueDb();
    await seedDraft('draft-a', userA);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();

    expect(provider.queuedSubmissions, isEmpty);
    expect(await queuedIds(), contains('draft-a'),
        reason: 'a failed read deletes nothing');
  });

  test('failed queue delete keeps the row and does not throw', () async {
    db = FailingDeleteDb();
    await seedDraft('draft-a', userA);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-a']);

    await provider.removeQueuedItem('draft-a');

    expect(await queuedIds(), contains('draft-a'),
        reason: 'a failed delete leaves the owner\'s draft in place');
  });

  test('same-owner delete removes only the owner\'s row', () async {
    await seedDraft('draft-a', userA);
    await seedDraft('draft-b', userB);
    auth.switchTo(userA);

    final provider = DocumentSubmissionProvider(db);
    await pumpEventQueue();
    expect(provider.queuedSubmissions.map((d) => d.id).toList(),
        <String>['draft-a']);

    await provider.removeQueuedItem('draft-a');

    expect(await queuedIds(), <String>['draft-b'],
        reason: 'the owner can delete their own draft, nothing else');
    expect(provider.queuedSubmissions, isEmpty);
  });
}
